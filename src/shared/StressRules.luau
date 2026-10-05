--!strict
-- Pure Stress Meter formulas. Each player's stress starts at StartingStress and
-- falls as they whack bosses; the server owns the value, clients only display it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)

local StressRules = {}

-- Relief scales with damage, so stronger hammers relieve stress faster.
function StressRules.reliefForHit(damage: number): number
	return math.max(0, damage * GameConfig.StressReliefPerDamage)
end

-- Clamped to [0, MaxStress] and rounded to hundredths so repeated fractional
-- relief (e.g. 12 x 0.1 = 1.2000000000000002) can't accumulate float drift.
function StressRules.applyRelief(stress: number, relief: number): number
	local next = math.clamp(stress - relief, 0, GameConfig.MaxStress)
	return math.floor(next * 100 + 0.5) / 100
end

return StressRules
