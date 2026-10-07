--!strict
--[[
	Owns each player's Stress Meter (saved in their data) and mirrors it to the
	Player's "Stress" attribute for display (meter, face, hammer glow).

	* Accepted hits relieve stress (CombatService -> relieve).
	* Passive stress: every accepted boss hit (CombatService ->
	  resetStressTimer, only after the server has applied the hit) restarts a
	  StressIdleDelay (15 s) grace period. After it, stress rises by
	  StressRegenStep every StressRegenInterval (5 s), up to MaxStress, until
	  the next accepted hit. Moving, swinging and missing, clicking, menus or
	  respawning never touch it.
	  One deadline per player (nextRiseAt) checked by a single loop for all
	  players every TICK_SECONDS, so there are no per-player threads, nothing
	  per frame, and a reset simply moves the deadline: an earlier schedule can
	  never fire later.
	* Reaching 0 from above while armed is a Zen moment: +ZenBonusCoins, +1 Zen
	  Level, announced to everyone. The next Zen is armed again only once stress
	  has climbed back to ZenRearmStress (see StressRules.isZenMoment).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require(ReplicatedStorage.Shared.Attributes)
local BuffService = require(script.Parent.BuffService)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)
local SessionService = require(script.Parent.SessionService)
local StressRules = require(ReplicatedStorage.Shared.StressRules)
local Types = require(ReplicatedStorage.Shared.Types)

local ZenAchievedRemote = ReplicatedStorage.Remotes.Mood.ZenAchieved

-- How often the one loop checks every player's deadline: rises land within
-- this of their exact time, without drifting.
local TICK_SECONDS = 0.25

local StressService = {}

-- Player -> when their passive stress rises next. One entry per player.
local nextRiseAt: { [Player]: number } = {}

local function publish(player: Player, stress: number): ()
	player:SetAttribute(Attributes.Stress, stress)
end

local function celebrateZen(player: Player, data: PlayerDataService.PlayerData): ()
	data.ZenArmed = false
	data.ZenLevel += 1
	SessionService.addCoins(player, GameConfig.ZenBonusCoins)
	BuffService.grantZenBuff(player)
	ProgressService.sync(player)

	local payload: Types.ZenAchieved = {
		UserId = player.UserId,
		DisplayName = player.DisplayName,
		ZenLevel = data.ZenLevel,
		BonusCoins = GameConfig.ZenBonusCoins,
	}
	ZenAchievedRemote:FireAllClients(payload)
end

-- A server-accepted boss hit: restarts the grace period (and stops any
-- passive rises until it has passed again).
function StressService.resetStressTimer(player: Player): ()
	nextRiseAt[player] = StressRules.firstRiseAt(os.clock())
end

-- Sets stress straight to the maximum (entering the Executive Floor). Re-arms
-- Zen, since the player now has a full meter to work back down.
function StressService.spike(player: Player): ()
	local data = PlayerDataService.get(player)
	if data == nil then
		return
	end
	data.Stress = GameConfig.MaxStress
	data.ZenArmed = true
	StressService.resetStressTimer(player)
	publish(player, data.Stress)
end

-- Returns the stress actually relieved (less than requested near zero).
function StressService.relieve(player: Player, relief: number): number
	local data = PlayerDataService.get(player)
	if data == nil or relief <= 0 then
		return 0
	end
	local current = data.Stress
	local nextStress = StressRules.applyRelief(current, relief)
	data.Stress = nextStress
	publish(player, nextStress)

	if StressRules.isZenMoment(current, nextStress, data.ZenArmed) then
		celebrateZen(player, data)
	end
	return current - nextStress
end

local function regenTick(): ()
	local now = os.clock()
	for player, riseAt in nextRiseAt do
		if now < riseAt then
			continue
		end
		nextRiseAt[player] = StressRules.nextRiseAfter(riseAt, now)
		local data = PlayerDataService.get(player)
		if data == nil or data.Stress >= GameConfig.MaxStress then
			continue -- already full: stays at MaxStress
		end
		data.Stress = StressRules.applyRegen(data.Stress)
		if StressRules.shouldRearm(data.Stress) then
			data.ZenArmed = true
		end
		publish(player, data.Stress)
	end
end

function StressService.init(): ()
	PlayerDataService.onLoaded(function(player: Player, data: PlayerDataService.PlayerData)
		-- Joining starts a grace period, like a hit.
		StressService.resetStressTimer(player)
		publish(player, data.Stress)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		nextRiseAt[player] = nil
	end)
end

function StressService.start(): ()
	while true do
		task.wait(TICK_SECONDS)
		regenTick()
	end
end

return StressService
