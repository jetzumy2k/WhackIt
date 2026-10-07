--!strict
-- Pure Stress Meter rules. Each player's stress starts at StartingStress, falls
-- as they whack bosses, and creeps back up when they stop landing hits. The
-- server owns the value; clients only display it (meter, face, hammer glow).

export type Mood = "Zen" | "Relaxed" | "Neutral" | "Stressed" | "Frazzled"

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

-- Face shown for a stress value (GameConfig mood bands).
function StressRules.moodFor(stress: number): Mood
	if stress <= 0 then
		return "Zen"
	elseif stress <= GameConfig.MoodRelaxedMax then
		return "Relaxed"
	elseif stress <= GameConfig.MoodNeutralMax then
		return "Neutral"
	elseif stress <= GameConfig.MoodStressedMax then
		return "Stressed"
	end
	return "Frazzled"
end

-- Passive stress schedule (StressService). After an accepted hit at `hitAt`
-- there's a StressIdleDelay grace period, then a rise every StressRegenInterval:
-- hit at 0 s -> rises at 20, 25, 30 s... (with the defaults).
function StressRules.firstRiseAt(hitAt: number): number
	return hitAt + GameConfig.StressIdleDelay + GameConfig.StressRegenInterval
end

-- The rise after one due at `riseAt`. If the server fell behind (a hitch),
-- it continues from `now` instead of firing a burst of missed rises.
function StressRules.nextRiseAfter(riseAt: number, now: number): number
	local nextAt = riseAt + GameConfig.StressRegenInterval
	if nextAt <= now then
		return now + GameConfig.StressRegenInterval
	end
	return nextAt
end

function StressRules.applyRegen(stress: number): number
	return math.min(GameConfig.MaxStress, stress + GameConfig.StressRegenStep)
end

-- A Zen moment pays out when stress reaches 0 from above while armed. Arming
-- needs stress to have climbed back to ZenRearmStress since the last Zen, so
-- idling a little and landing one hit can't farm Zen rewards.
function StressRules.isZenMoment(previous: number, current: number, armed: boolean): boolean
	return armed and previous > 0 and current <= 0
end

function StressRules.shouldRearm(stress: number): boolean
	return stress >= GameConfig.ZenRearmStress
end

return StressRules
