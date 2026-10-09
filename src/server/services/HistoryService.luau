--!strict
--[[
	Player history and the admin audit log (2026-10-08, docs/ADMIN.md
	"History"). There was no history before this; purchases only kept their
	ids (ProcessedPurchases) to stop double grants, and events keep their own
	history (EventService).

	One DataStore (AdminConfig.HistoryStoreName), bounded keys:
	  Player_<UserId>   the player's last HistoryPerPlayer entries, newest first
	  Admin_<YYYYMMDD>  that UTC day's admin actions, at most HistoryPerAdminDay
	Writes are queued and flushed every HistoryFlushSeconds (and when the
	server shuts down) with UpdateAsync, so many actions cost few DataStore
	requests and nothing is written per frame. Reads merge what is still
	queued, so an admin sees an action at once. In Studio without API access
	the history lives in this server only.

	Recorded by the services that do the thing (all on the server):
	  Admin     every admin action (AdminService), in the admin log and, when it
	            targets a player, in that player's history
	  Purchase  Robux purchases delivered (PurchaseService)
	  Buff      boosts used from the Bag (BagService)
	  Item      Mystery Hammers opened, bundles unpacked (BagService)
	  Egg       eggs found, put in an incubator (PetService)
	  Pet       pets hatched, equipped, put away, given (PetService)
	  Event     items won from drop events (RewardService)
	Only admins can read it (AdminService checks before calling query).
]]

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local AdminConfig = require(ServerScriptService.Config.AdminConfig)

export type Entry = {
	At: number, -- unix seconds
	Type: string, -- "Admin" | "Purchase" | "Buff" | "Item" | "Egg" | "Pet" | "Event"
	Action: string, -- short code, e.g. "Reward", "Buy", "Hatch"
	Text: string, -- what happened, in words
	Status: string, -- "Success" | "Failed"
	By: string?, -- admin name, for admin actions
	ByUserId: number?,
	TargetName: string?,
	TargetUserId: number?,
}

export type Page = {
	Entries: { Entry },
	Page: number,
	HasMore: boolean,
}

local HistoryService = {}

HistoryService.TYPES = table.freeze({ "Admin", "Purchase", "Buff", "Item", "Egg", "Pet", "Event" })
HistoryService.PAGE_SIZE = 20

local historyStore: DataStore? = nil
-- Key -> entries waiting to be saved, oldest first.
local pending: { [string]: { Entry } } = {}
-- Studio without a DataStore: everything stays here, newest first.
local memory: { [string]: { Entry } } = {}

local function clip(text: string?, length: number): string?
	if text == nil then
		return nil
	end
	return string.sub(text, 1, length)
end

local function playerKey(userId: number): string
	return "Player_" .. userId
end

function HistoryService.adminKey(unix: number): string
	return "Admin_" .. DateTime.fromUnixTimestamp(unix):FormatUniversalTime("YYYYMMDD", "en-us")
end

local function limitFor(key: string): number
	return if string.sub(key, 1, 6) == "Admin_"
		then AdminConfig.HistoryPerAdminDay
		else AdminConfig.HistoryPerPlayer
end

local function enqueue(key: string, entry: Entry): ()
	local list = pending[key]
	if list == nil then
		list = {}
		pending[key] = list
	end
	table.insert(list, entry)
end

local function clean(entry: Entry): Entry
	return {
		At = entry.At,
		Type = clip(entry.Type, 16) :: string,
		Action = clip(entry.Action, 24) :: string,
		Text = clip(entry.Text, 200) :: string,
		Status = clip(entry.Status, 16) :: string,
		By = clip(entry.By, 64),
		ByUserId = entry.ByUserId,
		TargetName = clip(entry.TargetName, 64),
		TargetUserId = entry.TargetUserId,
	}
end

-- Adds an entry to a player's history.
function HistoryService.record(
	userId: number,
	entryType: string,
	action: string,
	text: string,
	status: string?
): ()
	enqueue(
		playerKey(userId),
		clean({
			At = os.time(),
			Type = entryType,
			Action = action,
			Text = text,
			Status = status or "Success",
		})
	)
end

-- Adds an admin action to the day's admin log and, if it targets a player,
-- to that player's history too.
function HistoryService.recordAdmin(
	admin: Player,
	action: string,
	text: string,
	status: string,
	target: { UserId: number, Name: string }?
): ()
	local entry = clean({
		At = os.time(),
		Type = "Admin",
		Action = action,
		Text = text,
		Status = status,
		By = admin.Name,
		ByUserId = admin.UserId,
		TargetName = if target then target.Name else nil,
		TargetUserId = if target then target.UserId else nil,
	})
	enqueue(HistoryService.adminKey(entry.At), entry)
	if target then
		enqueue(playerKey(target.UserId), entry)
	end
end

-- Saved entries are untrusted: keep only well-formed ones.
local function parseList(raw: unknown): { Entry }
	local list: { Entry } = {}
	if typeof(raw) ~= "table" then
		return list
	end
	for _, value in raw :: { unknown } do
		if typeof(value) == "table" then
			local data = value :: { [string]: any }
			if
				typeof(data.At) == "number"
				and typeof(data.Type) == "string"
				and typeof(data.Action) == "string"
				and typeof(data.Text) == "string"
				and typeof(data.Status) == "string"
			then
				table.insert(list, clean(data :: Entry))
			end
		end
	end
	return list
end

-- Newest first, at most the key's limit.
local function merge(stored: { Entry }, newOldestFirst: { Entry }, limit: number): { Entry }
	local merged: { Entry } = {}
	for index = #newOldestFirst, 1, -1 do
		table.insert(merged, newOldestFirst[index])
	end
	for _, entry in stored do
		if #merged >= limit then
			break
		end
		table.insert(merged, entry)
	end
	while #merged > limit do
		table.remove(merged)
	end
	return merged
end

-- Saves everything queued. Yields. Failed keys go back in the queue.
function HistoryService.flush(): ()
	local batch = pending
	pending = {}
	for key, entries in batch do
		local store = historyStore
		local ok = false
		if store then
			ok = pcall(function()
				store:UpdateAsync(key, function(old: unknown)
					return merge(parseList(old), entries, limitFor(key))
				end)
			end)
		end
		if not ok then
			if store == nil or RunService:IsStudio() then
				-- No DataStore (Studio): keep it in this server.
				memory[key] = merge(memory[key] or {}, entries, limitFor(key))
			else
				-- Try again next time, in order, ahead of anything newer.
				local requeue = table.clone(entries)
				local newer = pending[key]
				if newer then
					for _, entry in newer do
						table.insert(requeue, entry)
					end
				end
				pending[key] = requeue
				warn("[History] couldn't save " .. key .. ", will retry")
			end
		end
	end
end

local function load(key: string): { Entry }
	local store = historyStore
	local stored: { Entry } = memory[key] or {}
	if store then
		local ok, raw = pcall(function()
			return store:GetAsync(key)
		end)
		if ok and raw ~= nil then
			stored = parseList(raw)
		end
	end
	return merge(stored, pending[key] or {}, limitFor(key))
end

local function pageOf(list: { Entry }, entryType: string?, sinceUnix: number?, page: number): Page
	local filtered: { Entry } = {}
	for _, entry in list do
		if
			(entryType == nil or entry.Type == entryType)
			and (sinceUnix == nil or entry.At >= sinceUnix)
		then
			table.insert(filtered, entry)
		end
	end
	local first = (page - 1) * HistoryService.PAGE_SIZE + 1
	local entries: { Entry } = {}
	for index = first, math.min(#filtered, first + HistoryService.PAGE_SIZE - 1) do
		table.insert(entries, filtered[index])
	end
	return {
		Entries = entries,
		Page = page,
		HasMore = #filtered >= first + HistoryService.PAGE_SIZE,
	}
end

-- One page of a player's history (newest first). Yields.
function HistoryService.queryPlayer(
	userId: number,
	entryType: string?,
	sinceUnix: number?,
	page: number
): Page
	return pageOf(load(playerKey(userId)), entryType, sinceUnix, page)
end

-- One page of the admin log for the UTC day `daysAgo` days back. Yields.
function HistoryService.queryAdmin(daysAgo: number, action: string?, page: number): Page
	local key = HistoryService.adminKey(os.time() - daysAgo * 86400)
	local list = load(key)
	local filtered: { Entry } = {}
	for _, entry in list do
		if action == nil or entry.Action == action then
			table.insert(filtered, entry)
		end
	end
	return pageOf(filtered, nil, nil, page)
end

function HistoryService.init(): ()
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(AdminConfig.HistoryStoreName)
	end)
	if ok then
		historyStore = store
	else
		warn(
			"[History] DataStore unavailable, keeping history in this server only: "
				.. tostring(store)
		)
	end
	game:BindToClose(function()
		HistoryService.flush()
	end)
end

function HistoryService.start(): ()
	while true do
		task.wait(AdminConfig.HistoryFlushSeconds)
		HistoryService.flush()
	end
end

return HistoryService
