--!strict
--[[
	Spawns shared bosses and owns their authoritative state (via Lib/BossState).
	Each spawn gets a fresh server-issued instance id, so hits aimed at a boss's
	previous life can never land on the respawned one.

	Clients see a boss as a Model under Workspace.Bosses whose attributes
	(Shared/Attributes) mirror the server state for display only.

	Besides the office bosses (ArenaConfig), admin-created custom bosses come
	and go at runtime: CustomBossService hands over the full list whenever it
	changes, and setCustomBosses() spawns, replaces or removes them. A custom
	boss with RespawnMode "Once" is not respawned after its defeat; listeners
	of onOnceBossDefeated (CustomBossService) record that for every server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local Attributes = require(ReplicatedStorage.Shared.Attributes)
local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local BossState = require(ServerScriptService.Lib.BossState)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local OfficeBuilder = require(ServerScriptService.Lib.OfficeBuilder)
local OutdoorBuilder = require(ServerScriptService.Lib.OutdoorBuilder)

export type LiveBoss = {
	State: BossState.BossState,
	Model: Model,
	Body: BasePart,
	Spawn: ArenaConfig.BossSpawn,
}

-- A custom boss to keep spawned. Signature changes when anything about it
-- changes, so an edited boss is respawned with its new stats.
export type CustomSpawn = {
	Definition: BossConfig.BossDefinition,
	Spawn: ArenaConfig.BossSpawn,
	Signature: string,
	Respawns: boolean, -- false for a "Once" boss
	-- A "Once" boss already beaten (here or in another server): never spawned
	-- again. A life already in progress here may still be finished.
	Spent: boolean,
}

local BossService = {}

local bossesFolder: Folder
local liveBosses: { [string]: LiveBoss } = {}
local nextInstanceNumber = 0
-- Custom boss id -> what should be spawned for it right now.
local customSpawns: { [string]: CustomSpawn } = {}
local onceDefeatedCallbacks: { (bossId: string) -> () } = {}

local function newInstanceId(): string
	nextInstanceNumber += 1
	return "boss-" .. nextInstanceNumber
end

local function buildModel(
	state: BossState.BossState,
	spawn: ArenaConfig.BossSpawn
): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = state.Definition.DisplayName
	-- Stream the whole boss in or out at once so clients never see half a model.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Anchored = true
	body.Size = spawn.Size
	body.Color = ArenaConfig.PlaceholderBossColor
	body.Material = Enum.Material.SmoothPlastic
	-- Invisible hitbox: each client draws the cartoon monster over it (Shared/BossVisual).
	body.Transparency = 1
	body.CFrame = CFrame.new(spawn.Position)
	body.Parent = model
	model.PrimaryPart = body

	model:SetAttribute(Attributes.BossInstanceId, state.InstanceId)
	model:SetAttribute(Attributes.BossId, state.Definition.Id)
	model:SetAttribute(Attributes.Health, state.Health)
	model:SetAttribute(Attributes.MaxHealth, state.Definition.MaxHealth)
	model:SetAttribute(Attributes.Defeated, false)
	if state.Definition.Custom then
		model:SetAttribute(Attributes.BossName, state.Definition.DisplayName)
		model:SetAttribute(Attributes.BossLook, state.Definition.LookId)
	end

	return model, body
end

-- The definition for a spawn: an office boss, or a custom boss still wanted.
local function definitionFor(spawn: ArenaConfig.BossSpawn): BossConfig.BossDefinition?
	local custom = customSpawns[spawn.BossId]
	if custom then
		return if custom.Spawn == spawn and not custom.Spent then custom.Definition else nil
	end
	return BossConfig.ById[spawn.BossId]
end

local function spawnBoss(spawn: ArenaConfig.BossSpawn): ()
	local definition = definitionFor(spawn)
	if definition == nil then
		-- A custom boss that was removed, replaced or spent while it was respawning.
		return
	end

	local state = BossState.new(definition, newInstanceId())
	local model, body = buildModel(state, spawn)
	liveBosses[state.InstanceId] = { State = state, Model = model, Body = body, Spawn = spawn }
	model.Parent = bossesFolder
end

-- Defeated bosses linger (so clients can play the defeat effect) and then are
-- replaced by a fresh spawn with a new instance id.
local function scheduleRespawn(live: LiveBoss): ()
	task.delay(GameConfig.BossRespawnDelay, function()
		liveBosses[live.State.InstanceId] = nil
		live.Model:Destroy()
		spawnBoss(live.Spawn)
	end)
end

local function despawnBossId(bossId: string): ()
	for instanceId, live in liveBosses do
		if live.State.Definition.Id == bossId then
			liveBosses[instanceId] = nil
			-- Ends the fight for this life: late hits find no live boss.
			live.State.Defeated = true
			live.Model:Destroy()
		end
	end
end

-- Makes the spawned custom bosses match `wanted` (by Definition.Id): new ones
-- spawn, removed ones disappear, changed ones respawn fresh.
function BossService.setCustomBosses(wanted: { CustomSpawn }): ()
	local wantedById: { [string]: CustomSpawn } = {}
	for _, entry in wanted do
		wantedById[entry.Definition.Id] = entry
	end
	for bossId, current in customSpawns do
		local wantedEntry = wantedById[bossId]
		if wantedEntry == nil or wantedEntry.Signature ~= current.Signature then
			customSpawns[bossId] = nil
			despawnBossId(bossId)
		end
	end
	for bossId, entry in wantedById do
		local current = customSpawns[bossId]
		if current == nil then
			customSpawns[bossId] = entry
			spawnBoss(entry.Spawn)
		else
			-- Spent only ever turns on: a stale load can't bring a beaten boss back.
			current.Spent = current.Spent or entry.Spent
		end
	end
end

-- Where every boss stands (office and custom), for spacing checks.
-- Called with the boss id when a "Once" custom boss is defeated in this server.
function BossService.onOnceBossDefeated(callback: (bossId: string) -> ()): ()
	table.insert(onceDefeatedCallbacks, callback)
end

function BossService.spawnPositions(): { Vector3 }
	local positions: { Vector3 } = {}
	for _, spawn in ArenaConfig.BossSpawns do
		table.insert(positions, spawn.Position)
	end
	for _, entry in customSpawns do
		table.insert(positions, entry.Spawn.Position)
	end
	return positions
end

-- Every boss that can currently be hit (for ShoutService).
function BossService.allLive(): { LiveBoss }
	local list: { LiveBoss } = {}
	for _, live in liveBosses do
		if not live.State.Defeated then
			table.insert(list, live)
		end
	end
	return list
end

-- Returns the boss only while it can still be hit.
function BossService.getLive(instanceId: string): LiveBoss?
	local live = liveBosses[instanceId]
	if live == nil or live.State.Defeated then
		return nil
	end
	return live
end

-- Must be called without yielding between getLive and here (see BossState).
function BossService.applyHit(live: LiveBoss, userId: number, damage: number): BossState.HitResult?
	local result = BossState.applyDamage(live.State, userId, damage)
	if result == nil then
		return nil
	end

	live.Model:SetAttribute(Attributes.Health, result.Health)
	if result.Defeated then
		live.Model:SetAttribute(Attributes.Defeated, true)
		local bossId = live.State.Definition.Id
		local custom = customSpawns[bossId]
		if custom and custom.Spawn == live.Spawn and not custom.Respawns then
			-- Set before the respawn timer runs, so this life is the last one here.
			custom.Spent = true
			for _, callback in onceDefeatedCallbacks do
				task.spawn(callback, bossId)
			end
		end
		scheduleRespawn(live)
	end
	return result
end

function BossService.init(): ()
	-- The office building the bosses stand in (ArenaConfig) and its surroundings.
	OfficeBuilder.build(Workspace)
	OutdoorBuilder.build(Workspace, Workspace.Terrain)

	local folder = Instance.new("Folder")
	folder.Name = "Bosses"
	folder.Parent = Workspace
	bossesFolder = folder
end

function BossService.start(): ()
	for _, spawn in ArenaConfig.BossSpawns do
		spawnBoss(spawn)
	end
end

return BossService
