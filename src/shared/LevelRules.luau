--!strict
--[[
	Player Level, derived from saved XP and never stored, so it can't drift
	from the XP. (When the curve got steeper on 2026-10-09, PlayerDataSchema
	v10 raised existing players' XP once so nobody lost a level.)

	XP to go from level L to L + 1 (GameConfig, 2026-10-09):
	  cost(L) = LevelScoreFactor x (2L - 1)                  below LevelCurveStartsAt
	          x (1 + LevelCurveGrowth x (L - start + 1))      from LevelCurveStartsAt on
	Below the start this is exactly the old curve (Level 10 at 48,600 XP);
	after it each level costs a little more than the last. Levels stop at
	MaxLevel (100); XP keeps counting for the leaderboard.

	`scoreForLevel` keeps its old name (the level used to come from Score):
	it is the total XP needed to reach a level.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)

local LevelRules = {}

LevelRules.MAX_LEVEL = GameConfig.MaxLevel

-- XP to go from `level` to `level + 1`.
function LevelRules.costOf(level: number): number
	local base = GameConfig.LevelScoreFactor * (2 * level - 1)
	local start = GameConfig.LevelCurveStartsAt
	if level >= start then
		base *= 1 + GameConfig.LevelCurveGrowth * (level - start + 1)
	end
	return math.floor(base + 0.5)
end

-- thresholds[L] = total XP needed to reach level L.
local thresholds: { number } = { 0 }
for level = 1, LevelRules.MAX_LEVEL - 1 do
	thresholds[level + 1] = thresholds[level] + LevelRules.costOf(level)
end

function LevelRules.levelFor(xp: number): number
	if xp ~= xp or xp <= 0 then
		return 1
	end
	-- Highest level whose threshold is reached (binary search).
	local low, high = 1, LevelRules.MAX_LEVEL
	while low < high do
		local middle = (low + high + 1) // 2
		if thresholds[middle] <= xp then
			low = middle
		else
			high = middle - 1
		end
	end
	return low
end

-- Total XP needed to reach `level` (inverse of levelFor), clamped to 1..MAX.
function LevelRules.scoreForLevel(level: number): number
	local clamped = math.clamp(math.floor(level), 1, LevelRules.MAX_LEVEL)
	return thresholds[clamped]
end

function LevelRules.isMax(level: number): boolean
	return level >= LevelRules.MAX_LEVEL
end

local function counted(level: number): number
	return math.clamp(math.floor(level), 1, LevelRules.MAX_LEVEL)
end

-- Character progression (docs/GAMEPLAY_RULES.md "Level bonuses"): base
-- damage and crit chance a level gives, compared with Level 1. Worked out
-- from the level (itself from saved XP), so nothing is stored: rejoining,
-- respawning or equipping can never award them twice, and a jump of
-- several levels gives every level's share at once.
function LevelRules.bonusDamage(level: number): number
	local steps = counted(level) - 1
	local slowsAt = GameConfig.LevelDamageSlowsAt
	local early = math.min(steps, slowsAt - 1)
	local late = math.max(0, steps - (slowsAt - 1))
	return early * GameConfig.LevelDamagePerLevel + late * GameConfig.LevelDamagePerLevelAfter
end

-- As a fraction: 0.0005 per level = 0.05 percentage points.
function LevelRules.bonusCritChance(level: number): number
	return (counted(level) - 1) * GameConfig.LevelCritChancePerLevel
end

-- What going from `oldLevel` to `newLevel` adds (zero if it isn't up).
function LevelRules.gains(oldLevel: number, newLevel: number): (number, number)
	if newLevel <= oldLevel then
		return 0, 0
	end
	return LevelRules.bonusDamage(newLevel) - LevelRules.bonusDamage(oldLevel),
		LevelRules.bonusCritChance(newLevel) - LevelRules.bonusCritChance(oldLevel)
end

-- The curve before 2026-10-09, frozen here: floor(sqrt(xp / 600)) + 1, no
-- cap. Only for the one-time level protection in PlayerDataSchema v10.
local LEGACY_FACTOR = 600

function LevelRules.legacyLevelFor(xp: number): number
	if xp ~= xp or xp <= 0 then
		return 1
	end
	return math.floor(math.sqrt(xp / LEGACY_FACTOR)) + 1
end

return LevelRules
