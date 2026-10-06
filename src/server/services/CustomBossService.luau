--!strict
--[[
	Admin-created bosses (docs/ADMIN.md). The list lives in one DataStore key
	shared by every server; changes go through UpdateAsync (so two servers
	editing at once can't lose each other's bosses) and a MessagingService
	ping tells other servers to reload. A periodic reload covers missed pings.

	Saved data is validated on every load (Shared/CustomBossRules.parseList).
	If loading fails, the bosses already spawned stay as they are.
	AdminService does the permission and input checks before calling in here.
]]

local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AdminConfig = require(ServerScriptService.Config.AdminConfig)
local BossService = require(script.Parent.BossService)
local CustomBossConfig = require(ReplicatedStorage.Config.CustomBossConfig)
local CustomBossRules = require(ReplicatedStorage.Shared.CustomBossRules)

local CustomBossService = {}

local records: { CustomBossRules.Record } = {}
local bossStore: DataStore? = nil
local changedCallbacks: { () -> () } = {}
local idRandom = Random.new()

local function signature(record: CustomBossRules.Record): string
	return string.format(
		"%s|%s|%d|%d|%d|%.2f|%.2f|%.2f",
		record.Name,
		record.LookId,
		record.MaxHealth,
		record.ScoreReward,
		record.CoinReward,
		record.X,
		record.Y,
		record.Z
	)
end

local function apply(list: { CustomBossRules.Record }): ()
	records = list
	local wanted: { BossService.CustomSpawn } = {}
	for _, record in list do
		local size = CustomBossConfig.Size
		table.insert(wanted, {
			Definition = CustomBossRules.definitionFor(record),
			Spawn = table.freeze({
				BossId = record.Id,
				Position = Vector3.new(record.X, record.Y, record.Z),
				Size = size,
				FloorY = record.Y - size.Y / 2,
			}),
			Signature = signature(record),
		})
	end
	BossService.setCustomBosses(wanted)
	for _, callback in changedCallbacks do
		task.spawn(callback)
	end
end

local function load(): ()
	local store = bossStore
	if store == nil then
		return
	end
	local ok, saved = pcall(function()
		return store:GetAsync(AdminConfig.CustomBossKey)
	end)
	if ok then
		apply(CustomBossRules.parseList(saved))
	else
		warn("[CustomBoss] couldn't load custom bosses, keeping current ones: " .. tostring(saved))
	end
end

-- Runs `change` on the saved list inside UpdateAsync. `change` returns the new
-- list, or nil plus a message to cancel. Returns (ok, message).
local function mutate(
	change: ({ CustomBossRules.Record }) -> ({ CustomBossRules.Record }?, string?)
): (boolean, string)
	local store = bossStore
	if store == nil then
		return false, "Custom bosses are unavailable (no DataStore access)."
	end
	local cancelMessage: string? = nil
	local result: { CustomBossRules.Record }? = nil
	local ok, err = pcall(function()
		store:UpdateAsync(AdminConfig.CustomBossKey, function(old: unknown)
			local nextList, message = change(CustomBossRules.parseList(old))
			cancelMessage = message
			result = nextList
			return nextList -- nil cancels the write
		end)
	end)
	if not ok then
		warn("[CustomBoss] save failed: " .. tostring(err))
		return false, "Saving failed. Try again in a moment."
	end
	local saved = result
	if saved == nil then
		return false, cancelMessage or "Nothing changed."
	end
	apply(saved)
	local published, publishErr = pcall(function()
		MessagingService:PublishAsync(AdminConfig.CustomBossTopic, "changed")
	end)
	if not published then
		-- Other servers still pick it up on their next refresh.
		warn("[CustomBoss] couldn't notify other servers: " .. tostring(publishErr))
	end
	return true, "Saved for all servers."
end

local function findIndex(list: { CustomBossRules.Record }, bossId: string): number?
	for index, record in list do
		if record.Id == bossId then
			return index
		end
	end
	return nil
end

-- Positions of every boss except `exceptId`, for spacing checks.
local function otherPositions(exceptId: string?): { Vector3 }
	local positions: { Vector3 } = {}
	local skip: Vector3? = nil
	for _, record in records do
		if record.Id == exceptId then
			skip = Vector3.new(record.X, record.Y, record.Z)
		end
	end
	for _, position in BossService.spawnPositions() do
		if position ~= skip then
			table.insert(positions, position)
		end
	end
	return positions
end

function CustomBossService.list(): { CustomBossRules.Record }
	return records
end

function CustomBossService.onChanged(callback: () -> ()): ()
	table.insert(changedCallbacks, callback)
end

-- `name` must already be text-filtered. Yields.
function CustomBossService.create(
	creatorUserId: number,
	spec: CustomBossRules.Spec,
	name: string,
	position: Vector3
): (boolean, string)
	if not CustomBossRules.hasSpace(position, otherPositions(nil)) then
		return false, "Too close to another boss. Move a bit further away."
	end
	return mutate(function(list)
		if #list >= CustomBossConfig.MaxBosses then
			return nil,
				string.format("You can have at most %d custom bosses.", CustomBossConfig.MaxBosses)
		end
		local id: string
		repeat
			id = string.format(
				"%s%d_%d",
				CustomBossConfig.IdPrefix,
				os.time(),
				idRandom:NextInteger(1000, 9999)
			)
		until findIndex(list, id) == nil
		table.insert(list, {
			Id = id,
			Name = name,
			LookId = spec.LookId,
			MaxHealth = spec.MaxHealth,
			ScoreReward = spec.ScoreReward,
			CoinReward = spec.CoinReward,
			X = position.X,
			Y = position.Y,
			Z = position.Z,
			CreatedBy = creatorUserId,
		})
		return list, nil
	end)
end

function CustomBossService.move(bossId: string, position: Vector3): (boolean, string)
	if not CustomBossRules.hasSpace(position, otherPositions(bossId)) then
		return false, "Too close to another boss. Move a bit further away."
	end
	return mutate(function(list)
		local index = findIndex(list, bossId)
		if index == nil then
			return nil, "That boss no longer exists."
		end
		local record = list[index]
		record.X, record.Y, record.Z = position.X, position.Y, position.Z
		return list, nil
	end)
end

function CustomBossService.remove(bossId: string): (boolean, string)
	return mutate(function(list)
		local index = findIndex(list, bossId)
		if index == nil then
			return nil, "That boss no longer exists."
		end
		table.remove(list, index)
		return list, nil
	end)
end

function CustomBossService.init(): ()
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(AdminConfig.CustomBossStoreName)
	end)
	if ok then
		bossStore = store
	else
		warn("[CustomBoss] DataStore unavailable: " .. tostring(store))
	end
end

function CustomBossService.start(): ()
	load()
	local subscribed, err = pcall(function()
		MessagingService:SubscribeAsync(AdminConfig.CustomBossTopic, function()
			load()
		end)
	end)
	if not subscribed then
		warn(
			"[CustomBoss] cross-server updates unavailable, using periodic refresh: "
				.. tostring(err)
		)
	end
	while true do
		task.wait(AdminConfig.CustomBossRefreshSeconds)
		load()
	end
end

return CustomBossService
