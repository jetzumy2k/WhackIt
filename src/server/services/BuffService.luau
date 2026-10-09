--!strict
--[[
	Owns every buff a player can have (docs/STORE.md, docs/GAMEPLAY_RULES.md):
	  * timed store buffs (XP, Damage, Crit Damage) saved in the player's data;
	    they count down only while the player is online (Shared/BuffRules);
	  * the Zen buff (+flat damage, +crit chance) for ZenBuffSeconds after
	    reaching 0 stress; not saved, it's a moment-to-moment reward.
	  * admin-set damage (docs/ADMIN.md): a fixed damage per hit, for this
	    session only; hits with it earn no rewards (CombatService/RewardService).
	  * the equipped pet's buffs (docs/PETS.md), read from the player's saved
	    pet, so nothing a client sends can change them.
	CombatService asks statsFor() and damageOverride() for each hit;
	RewardService asks xpMultiplier(). The server is the only place buffs are applied.

	How bonuses combine (one formula, CombatRules.hitDamage):
	  base          = hammer damage + Player Level bonus (+3 per level above 1)
	  damage bonus  = Damage boost + Mystery Hammer bonus + pet Damage (added)
	  crit chance   = base 5 % + Player Level (+0.05 points per level) + Zen
	  crit damage   = base +50 % + hammer + Crit Damage boost + pet CritDamage
	  XP multiplier = 1 + XP boost + pet XP (then x the XP event, RewardService)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Attributes = require(ReplicatedStorage.Shared.Attributes)
local BuffRules = require(ReplicatedStorage.Shared.BuffRules)
local CombatRules = require(ReplicatedStorage.Shared.CombatRules)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local HammerRules = require(ReplicatedStorage.Shared.HammerRules)
local LevelRules = require(ReplicatedStorage.Shared.LevelRules)
local PetRules = require(ReplicatedStorage.Shared.PetRules)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)

local TICK_SECONDS = 1

local BuffService = {}

local zenBuffUntil: { [Player]: number } = {}
local damageOverrides: { [Player]: number? } = {}
-- Admins with the boss-access bypass on (this session only, docs/ADMIN.md).
local bossBypass: { [Player]: boolean? } = {}

-- True when an admin turned on the bypass for themselves: every boss and
-- door opens for them. Only AdminService sets it, after its own checks.
function BuffService.hasBossBypass(player: Player): boolean
	return bossBypass[player] == true
end

function BuffService.setBossBypass(player: Player, enabled: boolean): ()
	bossBypass[player] = if enabled then true else nil
	player:SetAttribute(Attributes.AdminBypass, if enabled then true else nil)
end

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

-- The equipped pet's modifiers (all zero without one).
local function petBonuses(data: PlayerDataService.PlayerData): PetRules.Bonuses
	local pet = if data.EquippedPetId ~= "" then data.Pets[data.EquippedPetId] else nil
	return PetRules.bonuses(pet)
end

-- Multiplier applied to XP earned (1 = no boost).
function BuffService.xpMultiplier(player: Player): number
	local data = PlayerDataService.get(player)
	if data == nil then
		return 1
	end
	return 1 + BuffRules.fraction(data.Buffs.Xp) + petBonuses(data).Xp
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
	-- Permanent character progression, from the saved XP (never stored or
	-- re-awarded); temporary boosts, pets and events stay separate below.
	local level = LevelRules.levelFor(data.Xp)
	stats.LevelDamage = LevelRules.bonusDamage(level)
	stats.CritChance += LevelRules.bonusCritChance(level)
	local pet = petBonuses(data)
	-- A Mystery Hammer's and a pet's damage bonus add to a Damage boost's.
	stats.DamageBonus = BuffRules.fraction(data.Buffs.Damage) + hammer.DamageBonus + pet.Damage
	stats.CritDamage += hammer.CritDamage + BuffRules.fraction(data.Buffs.CritDamage) + pet.CritDamage
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
		bossBypass[player] = nil
	end)
end

function BuffService.start(): ()
	while true do
		task.wait(TICK_SECONDS)
		tick()
	end
end

return BuffService
