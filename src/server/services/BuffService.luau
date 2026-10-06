--!strict
--[[
	Owns every buff a player can have (docs/STORE.md, docs/GAMEPLAY_RULES.md):
	  * timed store buffs (XP, Damage, Crit Damage) saved in the player's data;
	    they count down only while the player is online (Shared/BuffRules);
	  * the Zen buff (+flat damage, +crit chance) for ZenBuffSeconds after
	    reaching 0 stress; not saved, it's a moment-to-moment reward.
	  * admin-set damage (docs/ADMIN.md): a fixed damage per hit, for this
	    session only; hits with it earn no rewards (CombatService/RewardService).
	CombatService asks statsFor() and damageOverride() for each hit;
	RewardService asks xpMultiplier(). The server is the only place buffs are applied.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Attributes = require(ReplicatedStorage.Shared.Attributes)
local BuffRules = require(ReplicatedStorage.Shared.BuffRules)
local CombatRules = require(ReplicatedStorage.Shared.CombatRules)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local HammerRules = require(ReplicatedStorage.Shared.HammerRules)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)

local TICK_SECONDS = 1

local BuffService = {}

local zenBuffUntil: { [Player]: number } = {}
local damageOverrides: { [Player]: number? } = {}

-- Admin-set damage per hit, or nil for normal hammer damage.
function BuffService.damageOverride(player: Player): number?
	return damageOverrides[player]
end

-- nil clears it. Only AdminService calls this, after its own checks.
function BuffService.setDamageOverride(player: Player, damage: number?): ()
	damageOverrides[player] = damage
end

local function zenSecondsLeft(player: Player): number
	local untilTime = zenBuffUntil[player]
	return if untilTime then math.max(0, untilTime - os.clock()) else 0
end

function BuffService.zenSecondsLeft(player: Player): number
	return zenSecondsLeft(player)
end

-- The end time is published on the shared server clock so the HUD countdown
-- matches the server exactly.
function BuffService.grantZenBuff(player: Player): ()
	zenBuffUntil[player] = os.clock() + GameConfig.ZenBuffSeconds
	player:SetAttribute(
		Attributes.ZenBuffEnds,
		Workspace:GetServerTimeNow() + GameConfig.ZenBuffSeconds
	)
end

-- Adds a store buff (strongest percent wins, time adds up).
function BuffService.grantTimed(
	player: Player,
	kind: string,
	percent: number,
	seconds: number
): boolean
	local data = PlayerDataService.get(player)
	if data == nil then
		return false
	end
	data.Buffs[kind] = BuffRules.add(data.Buffs[kind], percent, seconds)
	ProgressService.sync(player)
	return true
end

-- Multiplier applied to XP earned (1 = no boost).
function BuffService.xpMultiplier(player: Player): number
	local data = PlayerDataService.get(player)
	return 1 + (if data then BuffRules.fraction(data.Buffs.Xp) else 0)
end

-- Everything that shapes this player's next hit, or nil if they can't hit.
function BuffService.statsFor(player: Player): (CombatRules.HitStats?, HammerRules.HammerStats?)
	local data = PlayerDataService.get(player)
	if data == nil then
		return nil, nil
	end
	local hammer = HammerRules.resolve(data.EquippedHammerId, data.MysteryHammers)
	if hammer == nil then
		return nil, nil
	end

	local stats = CombatRules.baseStats(hammer.Damage)
	stats.DamageBonus = BuffRules.fraction(data.Buffs.Damage)
	stats.CritDamage += hammer.CritDamage + BuffRules.fraction(data.Buffs.CritDamage)
	if zenSecondsLeft(player) > 0 then
		stats.FlatBonus += GameConfig.ZenBuffFlatDamage
		stats.CritChance += GameConfig.ZenBuffCritChance
	end
	return stats, hammer
end

-- Counts store buffs down for online players; refreshes the UI when one ends.
local function tick(): ()
	for _, player in Players:GetPlayers() do
		local data = PlayerDataService.get(player)
		if data == nil then
			continue
		end
		local changed = false
		for kind, buff in data.Buffs do
			local nextBuff = BuffRules.tick(buff, TICK_SECONDS)
			if nextBuff then
				data.Buffs[kind] = nextBuff
			else
				-- Removing the current key while iterating is safe in Luau.
				data.Buffs[kind] = nil :: any
				changed = true
			end
		end
		local untilTime = zenBuffUntil[player]
		if untilTime and os.clock() >= untilTime then
			zenBuffUntil[player] = nil
			player:SetAttribute(Attributes.ZenBuffEnds, 0)
		end
		if changed then
			ProgressService.sync(player)
		end
	end
end

function BuffService.init(): ()
	Players.PlayerRemoving:Connect(function(player: Player)
		zenBuffUntil[player] = nil
		damageOverrides[player] = nil
	end)
end

function BuffService.start(): ()
	while true do
		task.wait(TICK_SECONDS)
		tick()
	end
end

return BuffService
