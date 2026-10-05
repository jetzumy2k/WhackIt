--!strict
--[[
	Owns each player's Stress Meter (saved in their data) and mirrors it to the
	Player's "Stress" attribute for display (meter, face, hammer glow).

	* Accepted hits relieve stress (CombatService -> relieve).
	* After StressIdleDelay seconds without an accepted hit, stress rises by
	  StressRegenStep every StressRegenInterval seconds.
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

local REGEN_TICK_SECONDS = 1

local StressService = {}

local lastActivityAt: { [Player]: number } = {}
local lastRegenAt: { [Player]: number } = {}

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

-- Records an accepted hit: resets the idle timer for stress coming back.
function StressService.noteActivity(player: Player): ()
	lastActivityAt[player] = os.clock()
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
	lastActivityAt[player] = os.clock()
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
	for player, activityAt in lastActivityAt do
		local data = PlayerDataService.get(player)
		if data == nil or data.Stress >= GameConfig.MaxStress then
			continue
		end
		-- Idle time counts from the later of the last hit and the last rise.
		local sinceRegen = now - (lastRegenAt[player] or activityAt)
		if StressRules.shouldRegen(now - activityAt, sinceRegen) then
			lastRegenAt[player] = now
			data.Stress = StressRules.applyRegen(data.Stress)
			if StressRules.shouldRearm(data.Stress) then
				data.ZenArmed = true
			end
			publish(player, data.Stress)
		end
	end
end

function StressService.init(): ()
	PlayerDataService.onLoaded(function(player: Player, data: PlayerDataService.PlayerData)
		lastActivityAt[player] = os.clock()
		publish(player, data.Stress)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastActivityAt[player] = nil
		lastRegenAt[player] = nil
	end)
end

function StressService.start(): ()
	while true do
		task.wait(REGEN_TICK_SECONDS)
		regenTick()
	end
end

return StressService
