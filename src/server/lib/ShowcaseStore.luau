--!strict
--[[
	Where the Office Showcase keeps its data (docs/SHOWCASE.md): one DataStore
	for the snapshots and the Featured list, and OrderedDataStores ("boards")
	for the Newest list, each week's likes and the review queue.

	Two backends with the same methods:
	  * dataStore(): the real stores, shared by every server. Every call is
	    wrapped in pcall and returns ok = false on failure.
	  * memory(): plain tables in this server only. ShowcaseService uses it in
	    Studio when API access is off, so the Showcase can still be tried
	    out; it's also what the unit tests use.
]]

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

-- Most entries `top` reads (pages of 100).
local MAX_TOP = 500

export type Ranked = { UserId: number, Value: number }

export type Store = {
	Global: boolean, -- shared by every server
	-- The saved value at `key` (nil if none).
	get: (key: string) -> (boolean, unknown),
	-- `transform(old)` returns the new value, or nil to leave it as it is.
	-- Returns the value saved afterwards.
	update: (key: string, transform: (old: unknown) -> unknown) -> (boolean, unknown),
	setRank: (board: string, userId: number, value: number) -> boolean,
	addRank: (board: string, userId: number, delta: number) -> boolean,
	removeRank: (board: string, userId: number) -> boolean,
	-- The highest `size` entries of a board, highest first.
	top: (board: string, size: number) -> (boolean, { Ranked }),
}

local ShowcaseStore = {}

local function sorted(entries: { Ranked }, size: number): { Ranked }
	table.sort(entries, function(a, b)
		if a.Value ~= b.Value then
			return a.Value > b.Value
		end
		return a.UserId < b.UserId
	end)
	local first: { Ranked } = {}
	for index = 1, math.min(size, #entries) do
		table.insert(first, entries[index])
	end
	return first
end

function ShowcaseStore.memory(): Store
	local values: { [string]: unknown } = {}
	local boards: { [string]: { [number]: number } } = {}
	local function board(name: string): { [number]: number }
		local existing = boards[name]
		if existing == nil then
			existing = {}
			boards[name] = existing
		end
		return existing
	end
	return {
		Global = false,
		get = function(key: string): (boolean, unknown)
			return true, values[key]
		end,
		update = function(key: string, transform: (old: unknown) -> unknown): (boolean, unknown)
			local new = transform(values[key])
			if new ~= nil then
				values[key] = new
			end
			return true, values[key]
		end,
		setRank = function(name: string, userId: number, value: number): boolean
			board(name)[userId] = math.floor(value)
			return true
		end,
		addRank = function(name: string, userId: number, delta: number): boolean
			local ranks = board(name)
			ranks[userId] = (ranks[userId] or 0) + math.floor(delta)
			return true
		end,
		removeRank = function(name: string, userId: number): boolean
			board(name)[userId] = nil
			return true
		end,
		top = function(name: string, size: number): (boolean, { Ranked })
			local entries: { Ranked } = {}
			for userId, value in board(name) do
				table.insert(entries, { UserId = userId, Value = value })
			end
			return true, sorted(entries, size)
		end,
	}
end

-- `name`: the snapshot store; boards are OrderedDataStores `boardPrefix .. board`.
function ShowcaseStore.dataStore(name: string, boardPrefix: string): Store?
	local ok, store = pcall(function(): DataStore
		return DataStoreService:GetDataStore(name)
	end)
	if not ok then
		return nil
	end
	local ordered: { [string]: OrderedDataStore } = {}
	local function boardStore(board: string): OrderedDataStore?
		local existing = ordered[board]
		if existing then
			return existing
		end
		local found, result = pcall(function(): OrderedDataStore
			return DataStoreService:GetOrderedDataStore(boardPrefix .. board)
		end)
		if not found then
			return nil
		end
		ordered[board] = result
		return result
	end
	return {
		Global = true,
		get = function(key: string): (boolean, unknown)
			local success, value = pcall(function(): unknown
				return store:GetAsync(key)
			end)
			return success, if success then value else nil
		end,
		update = function(key: string, transform: (old: unknown) -> unknown): (boolean, unknown)
			local success, value = pcall(function(): unknown
				return store:UpdateAsync(key, function(old: unknown): unknown
					return transform(old)
				end)
			end)
			return success, if success then value else nil
		end,
		setRank = function(board: string, userId: number, value: number): boolean
			local target = boardStore(board)
			return target ~= nil
				and pcall(function()
					target:SetAsync(tostring(userId), math.floor(value))
				end)
		end,
		addRank = function(board: string, userId: number, delta: number): boolean
			local target = boardStore(board)
			return target ~= nil
				and pcall(function()
					target:IncrementAsync(tostring(userId), math.floor(delta))
				end)
		end,
		removeRank = function(board: string, userId: number): boolean
			local target = boardStore(board)
			return target ~= nil
				and pcall(function()
					target:RemoveAsync(tostring(userId))
				end)
		end,
		top = function(board: string, size: number): (boolean, { Ranked })
			local target = boardStore(board)
			if target == nil then
				return false, {}
			end
			local wanted = math.clamp(size, 1, MAX_TOP)
			local success, items = pcall(function(): { { key: string, value: number } }
				local pages = target:GetSortedAsync(false, math.min(wanted, 100))
				local all = pages:GetCurrentPage()
				while #all < wanted and not pages.IsFinished do
					pages:AdvanceToNextPageAsync()
					for _, item in pages:GetCurrentPage() do
						table.insert(all, item)
					end
				end
				return all
			end)
			if not success then
				return false, {}
			end
			local entries: { Ranked } = {}
			for _, item in items do
				local userId = tonumber(item.key)
				if userId and typeof(item.value) == "number" then
					table.insert(entries, { UserId = userId, Value = item.value })
				end
			end
			return true, entries
		end,
	}
end

--[[
	The store a service should use: the real stores; in Studio, if they can't
	be reached (API access off), a store in this server only. nil if the real
	stores are unavailable in a live server. `label` names it in warnings.
]]
function ShowcaseStore.choose(name: string, boardPrefix: string, label: string): Store?
	local real = ShowcaseStore.dataStore(name, boardPrefix)
	if RunService:IsStudio() then
		local reachable = real ~= nil and (real :: Store).get("Probe")
		if not reachable then
			warn(
				string.format(
					"[%s] no DataStore access in Studio: using a store in this server only",
					label
				)
			)
			return ShowcaseStore.memory()
		end
	end
	if real == nil then
		warn(string.format("[%s] store unavailable", label))
	end
	return real
end

return ShowcaseStore
