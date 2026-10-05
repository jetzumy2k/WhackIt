--!strict
--[[
	Resolves any hammer id a player can hold to its stats and look: the regular
	shop hammers (HammerConfig) and Mystery Hammers bought with Robux, whose
	stats were rolled once at purchase and saved (MysteryHammers in the data).

	Mystery Hammer ids look like "mystery_<n>".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)

export type MysteryRoll = {
	Damage: number,
	CritDamagePercent: number,
}

export type HammerStats = {
	Id: string,
	DisplayName: string,
	Description: string,
	Damage: number,
	CritDamage: number, -- extra crit damage as a fraction (0.08 = +8 %)
	HeadColor: Color3,
	HandleColor: Color3,
}

local HammerRules = {}

local MYSTERY_PREFIX = "mystery_"

function HammerRules.isMysteryId(hammerId: string): boolean
	return string.sub(hammerId, 1, #MYSTERY_PREFIX) == MYSTERY_PREFIX
end

function HammerRules.mysteryId(number: number): string
	return MYSTERY_PREFIX .. number
end

-- Rolls a Mystery Hammer: each whole value in range equally likely.
function HammerRules.rollMystery(random: Random): MysteryRoll
	local mystery = StoreConfig.Mystery
	return {
		Damage = random:NextInteger(mystery.DamageMin, mystery.DamageMax),
		CritDamagePercent = random:NextInteger(
			mystery.CritDamageMinPercent,
			mystery.CritDamageMaxPercent
		),
	}
end

-- Clamps a saved roll back into the allowed ranges (never trust saved data).
function HammerRules.clampRoll(roll: MysteryRoll): MysteryRoll
	local mystery = StoreConfig.Mystery
	return {
		Damage = math.clamp(math.floor(roll.Damage), mystery.DamageMin, mystery.DamageMax),
		CritDamagePercent = math.clamp(
			math.floor(roll.CritDamagePercent),
			mystery.CritDamageMinPercent,
			mystery.CritDamageMaxPercent
		),
	}
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
			Description = string.format(
				"%d damage, +%d%% crit damage",
				roll.Damage,
				roll.CritDamagePercent
			),
			Damage = roll.Damage,
			CritDamage = roll.CritDamagePercent / 100,
			HeadColor = mystery.HeadColor,
			HandleColor = mystery.HandleColor,
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
		CritDamage = 0,
		HeadColor = hammer.HeadColor,
		HandleColor = hammer.HandleColor,
	}
end

return HammerRules
