--!strict
--[[
	Server authority for hammer hits (docs/REMOTE_CONTRACTS.md, docs/GAMEPLAY_RULES.md).
	The client only names the boss it swung at; everything else (cooldown, reach,
	damage, defeat, rewards, stress) is decided here.

	The hit handler never yields, so validation and the state change it guards
	happen atomically with respect to other players' hits.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local BossService = require(script.Parent.BossService)
local CombatRules = require(ReplicatedStorage.Shared.CombatRules)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)
local HammerTool = require(ServerScriptService.Lib.HammerTool)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressionRules = require(ReplicatedStorage.Shared.ProgressionRules)
local RemoteController = require(ServerScriptService.Controllers.RemoteController)
local RemoteLimits = require(ServerScriptService.Config.RemoteLimits)
local RewardService = require(script.Parent.RewardService)
local SessionService = require(script.Parent.SessionService)
local StressRules = require(ReplicatedStorage.Shared.StressRules)
local StressService = require(script.Parent.StressService)
local Types = require(ReplicatedStorage.Shared.Types)
local Validate = require(ReplicatedStorage.Shared.Validate)

local CombatRemotes = ReplicatedStorage.Remotes.Combat

local IS_STUDIO = RunService:IsStudio()
local dropLogLimiter = RateLimiter.new({ Capacity = 1, RefillPerSecond = 1 })

local REMOTE_NAME = "RequestHammerHit"

local CombatService = {}

local lastHitAt: { [Player]: number } = {}

-- Root position of a live character holding a hammer, or nil plus the reason.
-- The equipped Tool only gates the swing; damage comes from EquippedHammerId.
local function getSwingPosition(player: Player): (Vector3?, string?)
	local character = player.Character
	if character == nil then
		return nil, "no character"
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return nil, "character not alive"
	end
	local tool = character:FindFirstChildOfClass("Tool")
	if tool == nil or tool:GetAttribute(HammerTool.HAMMER_ID_ATTRIBUTE) == nil then
		return nil, "no hammer in hand"
	end
	return root.Position, nil
end

-- Studio-only: explain dropped hits during playtests (at most once per second
-- per player). Live servers stay silent so normal misses never spam the log.
local function explainDrop(player: Player, reason: string): ()
	if IS_STUDIO and dropLogLimiter.allow(player.UserId) then
		print(string.format("[Combat] hit from %s ignored: %s", player.Name, reason))
	end
end

-- Every contributor gets a share of the reward (RewardService decides how much
-- and whether the defeat counts for them) and hears about the defeat.
local function rewardContributors(live: BossService.LiveBoss): ()
	local state = live.State
	for userId in state.Contributions do
		local player = Players:GetPlayerByUserId(userId)
		if player == nil then
			continue -- left before the defeat; nothing to grant
		end

		local grant = RewardService.grantDefeat(player, state)
		local payload: Types.BossDefeated = {
			BossInstanceId = state.InstanceId,
			BossId = state.Definition.Id,
			Rewarded = grant ~= nil and grant.Qualified,
			ScoreAwarded = if grant then grant.Score else 0,
			CoinsAwarded = if grant then grant.Coins else 0,
			StressRelieved = if grant then grant.StressRelieved else 0,
			UnlockedBossIds = if grant then grant.UnlockedBossIds else {},
			SharePercent = if grant then math.floor(grant.Share * 100 + 0.5) else 0,
			LastHit = grant ~= nil and grant.LastHit,
		}
		CombatRemotes.BossDefeated:FireClient(player, payload)
	end
end

local function onHammerHit(player: Player, rawBossInstanceId: unknown): ()
	local bossInstanceId = Validate.id(rawBossInstanceId, RemoteLimits.MaxIdLength)
	if bossInstanceId == nil then
		return RemoteController.reject(player, REMOTE_NAME, "invalid bossInstanceId")
	end

	-- The checks below fail in normal play (lag, a boss just defeated, walking
	-- away), so they drop without warnings; explainDrop prints only in Studio.
	local session = SessionService.get(player)
	if session == nil then
		return explainDrop(player, "no session yet")
	end

	local now = os.clock()
	if not CombatRules.isOffCooldown(now, lastHitAt[player], GameConfig.HitCooldownGrace) then
		return explainDrop(player, "cooldown")
	end

	local live = BossService.getLive(bossInstanceId)
	if live == nil then
		return explainDrop(player, "boss " .. bossInstanceId .. " is gone or defeated")
	end

	local data = PlayerDataService.get(player)
	if data == nil then
		return explainDrop(player, "data not loaded")
	end
	if not ProgressionRules.isBossUnlocked(live.State.Definition.Id, data.BossDefeats) then
		return explainDrop(player, live.State.Definition.Id .. " is locked for this player")
	end

	local rootPosition, notReadyReason = getSwingPosition(player)
	if rootPosition == nil then
		return explainDrop(player, notReadyReason or "not ready")
	end
	if not CombatRules.isInReach(rootPosition, live.Body.Position, GameConfig.HitReachGrace) then
		local distance = (rootPosition - live.Body.Position).Magnitude
		return explainDrop(
			player,
			string.format(
				"out of reach (%.1f > %.1f studs)",
				distance,
				GameConfig.HitReach + GameConfig.HitReachGrace
			)
		)
	end

	local hammer = HammerConfig.ById[data.EquippedHammerId]
	if hammer == nil then
		return RemoteController.reject(player, REMOTE_NAME, "no equipped hammer")
	end

	local result = BossService.applyHit(
		live,
		player.UserId,
		CombatRules.computeHitDamage(hammer, live.State.Definition)
	)
	if result == nil then
		return
	end
	lastHitAt[player] = now

	data.TotalHits += 1
	StressService.noteActivity(player)

	StressService.relieve(player, StressRules.reliefForHit(result.Applied))

	local feedback: Types.CombatFeedback = {
		BossInstanceId = bossInstanceId,
		Health = result.Health,
		MaxHealth = live.State.Definition.MaxHealth,
		Damage = result.Applied,
		HitterUserId = player.UserId,
		Defeated = result.Defeated,
	}
	CombatRemotes.CombatFeedback:FireAllClients(feedback)

	if result.Defeated then
		rewardContributors(live)
	end
end

function CombatService.init(): ()
	RemoteController.bind(CombatRemotes.RequestHammerHit, {
		name = REMOTE_NAME,
		maxArgs = 1,
		rateLimit = RemoteLimits.RequestHammerHit,
	}, onHammerHit)

	Players.PlayerRemoving:Connect(function(player: Player)
		lastHitAt[player] = nil
		dropLogLimiter.remove(player.UserId)
	end)
end

return CombatService
