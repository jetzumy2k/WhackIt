--!strict
--[[
	Spawns shared bosses and owns their authoritative state (via Lib/BossState).
	Each spawn gets a fresh server-issued instance id, so hits aimed at a boss's
	previous life can never land on the respawned one.

	Clients see a boss as a Model under Workspace.Bosses whose attributes
	(Shared/Attributes) mirror the server state for display only.
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

local BossService = {}

local bossesFolder: Folder
local liveBosses: { [string]: LiveBoss } = {}
local nextInstanceNumber = 0

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

	return model, body
end

local function spawnBoss(spawn: ArenaConfig.BossSpawn): ()
	local definition = BossConfig.ById[spawn.BossId]
	if definition == nil then
		warn(string.format("[BossService] unknown BossId %q in ArenaConfig", spawn.BossId))
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
