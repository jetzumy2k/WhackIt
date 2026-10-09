--!strict
--[[
	Resolves any hammer id a player can hold to its stats and look: the regular
	shop hammers (HammerConfig) and Mystery Hammers bought with Robux. A Mystery
	Hammer has fixed base damage (StoreConfig.Mystery.BaseDamage) plus a bonus
	damage % and a crit damage % rolled once when it's opened and saved with
	the player's data (MysteryHammers); equipping, respawning or rejoining
	never rerolls them. Saved values are clamped back into range on load.

	Mystery Hammer ids look like "mystery_<n>".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)

export type MysteryRoll = {
	Damage: number, -- base damage (fixed: StoreConfig.Mystery.BaseDamage)
	BonusDamagePercent: number, -- extra damage on every hit, whole %
	CritDamagePercent: number, -- extra crit damage, whole %
}

-- A roll as saved by older versions (no BonusDamagePercent yet).
export type SavedRoll = {
	Damage: number,
	BonusDamagePercent: number?,
	CritDamagePercent: number,
}

export type HammerStats = {
	Id: string,
	DisplayName: string,
	Description: string,
	Damage: number,
	DamageBonus: number, -- extra damage on every hit as a fraction (0.2 = +20 %)
	CritDamage: number, -- extra crit damage as a fraction (0.08 = +8 %)
	HeadColor: Color3,
	HandleColor: Color3,
	Style: string, -- Config/HammerStyleConfig look
}

local HammerRules = {}

local MYSTERY_PREFIX = "mystery_"

function HammerRules.isMysteryId(hammerId: string): boolean
	return string.sub(hammerId, 1, #MYSTERY_PREFIX) == MYSTERY_PREFIX
end

function HammerRules.mysteryId(number: number): string
	return MYSTERY_PREFIX .. number
end

-- Rolls a Mystery Hammer: fixed base damage, and each whole bonus percent in
-- range equally likely. Server only (BagService), when the hammer is opened.
function HammerRules.rollMystery(random: Random): MysteryRoll
	local mystery = StoreConfig.Mystery
	return {
		Damage = mystery.BaseDamage,
		BonusDamagePercent = random:NextInteger(
			mystery.BonusDamageMinPercent,
			mystery.BonusDamageMaxPercent
		),
		CritDamagePercent = random:NextInteger(
			mystery.CritDamageMinPercent,
			mystery.CritDamageMaxPercent
		),
	}
end

-- Brings a saved roll back into the allowed ranges (never trust saved data).
-- Base damage is always the fixed value; a roll saved before the damage bonus
-- existed gets LegacyBonusDamagePercent, so old hammers keep working.
function HammerRules.clampRoll(roll: SavedRoll): MysteryRoll
	local mystery = StoreConfig.Mystery
	local bonus = roll.BonusDamagePercent or mystery.LegacyBonusDamagePercent
	return {
		Damage = mystery.BaseDamage,
		BonusDamagePercent = math.clamp(
			math.floor(bonus),
			mystery.BonusDamageMinPercent,
			mystery.BonusDamageMaxPercent
		),
		CritDamagePercent = math.clamp(
			math.floor(roll.CritDamagePercent),
			mystery.CritDamageMinPercent,
			mystery.CritDamageMaxPercent
		),
	}
end

-- "35 damage, +20% damage, +7% crit damage"
function HammerRules.mysteryText(roll: MysteryRoll): string
	return string.format(
		"%d damage, +%d%% damage, +%d%% crit damage",
		roll.Damage,
		roll.BonusDamagePercent,
		roll.CritDamagePercent
	)
end

function HammerRules.resolve(
	hammerId: string,
	mysteryHammers: { [string]: MysteryRoll }
): HammerStats?
	if HammerRules.isMysteryId(hammerId) then
		local roll = mysteryHammers[hammerId]
		if roll == nil then
			return nil
		end
		local mystery = StoreConfig.Mystery
		return {
			Id = hammerId,
			DisplayName = mystery.DisplayName,
			Description = HammerRules.mysteryText(roll),
			Damage = roll.Damage,
			DamageBonus = roll.BonusDamagePercent / 100,
			CritDamage = roll.CritDamagePercent / 100,
			HeadColor = mystery.HeadColor,
			HandleColor = mystery.HandleColor,
			Style = mystery.Style,
		}
	end
	local hammer = HammerConfig.ById[hammerId]
	if hammer == nil then
		return nil
	end
	return {
		Id = hammer.Id,
		DisplayName = hammer.DisplayName,
		Description = hammer.Description,
		Damage = hammer.Damage,
		DamageBonus = 0,
		CritDamage = 0,
		HeadColor = hammer.HeadColor,
		HandleColor = hammer.HandleColor,
		Style = hammer.Style,
	}
end

return HammerRules
