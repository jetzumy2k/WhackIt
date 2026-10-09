--!strict
--[[
	Player Level, derived from lifetime Score (never stored, so it can't drift
	from the score and needs no save migration).

	  level = floor( sqrt(score / LevelScoreFactor) ) + 1

	Every player starts at Level 1; each level needs a little more score than the
	last. With LevelScoreFactor 600, Level 10 needs 48,600 score.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)

local LevelRules = {}

function LevelRules.levelFor(score: number): number
	if score ~= score or score <= 0 then
		return 1
	end
	return math.floor(math.sqrt(score / GameConfig.LevelScoreFactor)) + 1
end

-- Character progression (docs/GAMEPLAY_RULES.md "Level bonuses"): base
-- damage and crit chance a level gives, compared with Level 1. Worked out
-- from the level (itself from saved XP), so nothing is stored: rejoining,
-- respawning or equipping can never award them twice, and a jump of
-- several levels gives every level's share at once.
function LevelRules.bonusDamage(level: number): number
	return math.max(0, math.floor(level) - 1) * GameConfig.LevelDamagePerLevel
end

-- As a fraction: 0.0005 per level = 0.05 percentage points.
function LevelRules.bonusCritChance(level: number): number
	return math.max(0, math.floor(level) - 1) * GameConfig.LevelCritChancePerLevel
end

-- What going from `oldLevel` to `newLevel` adds (zero if it isn't up).
function LevelRules.gains(oldLevel: number, newLevel: number): (number, number)
	if newLevel <= oldLevel then
		return 0, 0
	end
	return LevelRules.bonusDamage(newLevel) - LevelRules.bonusDamage(oldLevel),
		LevelRules.bonusCritChance(newLevel) - LevelRules.bonusCritChance(oldLevel)
end

-- Score needed to reach `level` (inverse of levelFor).
function LevelRules.scoreForLevel(level: number): number
	local steps = math.max(0, math.floor(level) - 1)
	return steps * steps * GameConfig.LevelScoreFactor
end

return LevelRules
