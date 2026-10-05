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

-- Score needed to reach `level` (inverse of levelFor).
function LevelRules.scoreForLevel(level: number): number
	local steps = math.max(0, math.floor(level) - 1)
	return steps * steps * GameConfig.LevelScoreFactor
end

return LevelRules
