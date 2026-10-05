--!strict
--[[
	Pure rules for timed buffs (XP, Damage, Crit Damage) bought in the store.

	* Time counts down only while the player is in the game (BuffService ticks
	  online players), so a 5-hour boost gives 5 hours of play.
	* Buying a buff of a kind that is already active: the durations add up and
	  the strongest percent applies to the combined time (never wastes a
	  purchase, and percentages can't stack to absurd values).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)

export type Buff = {
	Percent: number,
	SecondsLeft: number,
}

local BuffRules = {}

function BuffRules.add(current: Buff?, percent: number, seconds: number): Buff
	if current == nil or current.SecondsLeft <= 0 then
		return { Percent = percent, SecondsLeft = math.min(seconds, StoreConfig.MaxBuffSeconds) }
	end
	return {
		Percent = math.max(current.Percent, percent),
		SecondsLeft = math.min(current.SecondsLeft + seconds, StoreConfig.MaxBuffSeconds),
	}
end

-- Counts down `seconds` of play; nil once used up.
function BuffRules.tick(buff: Buff, seconds: number): Buff?
	local left = buff.SecondsLeft - seconds
	if left <= 0 then
		return nil
	end
	return { Percent = buff.Percent, SecondsLeft = left }
end

-- The active percent as a fraction (0 when there's no buff).
function BuffRules.fraction(buff: Buff?): number
	return if buff and buff.SecondsLeft > 0 then buff.Percent / 100 else 0
end

return BuffRules
