--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local LevelRules = require(ReplicatedStorage.Shared.LevelRules)

return function()
	describe("LevelRules", function()
		it("starts every player at Level 1", function()
			expect(LevelRules.levelFor(0)).to.equal(1)
			expect(LevelRules.levelFor(GameConfig.LevelScoreFactor - 1)).to.equal(1)
		end)

		it("reaches each level exactly at its score threshold", function()
			for level = 2, 15 do
				local needed = LevelRules.scoreForLevel(level)
				expect(LevelRules.levelFor(needed)).to.equal(level)
				expect(LevelRules.levelFor(needed - 1)).to.equal(level - 1)
			end
		end)

		it("never goes down as score grows", function()
			local previous = 1
			for score = 0, 200000, 997 do
				local level = LevelRules.levelFor(score)
				expect(level >= previous).to.equal(true)
				previous = level
			end
		end)

		it("treats negative or NaN score as Level 1", function()
			expect(LevelRules.levelFor(-50)).to.equal(1)
			expect(LevelRules.levelFor(0 / 0)).to.equal(1)
		end)

		it("puts the upstairs level within reach of dedicated play", function()
			-- Sanity: needs real effort (>10k score) but not an absurd grind (<500k).
			local needed = LevelRules.scoreForLevel(GameConfig.UpstairsMinLevel)
			expect(needed > 10000).to.equal(true)
			expect(needed < 500000).to.equal(true)
		end)
	end)
end
