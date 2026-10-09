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
	describe("LevelRules level bonuses", function()
		it("gives nothing at Level 1 and +3 damage / +0.05 points crit per level after", function()
			expect(LevelRules.bonusDamage(1)).to.equal(0)
			expect(LevelRules.bonusCritChance(1)).to.equal(0)
			expect(LevelRules.bonusDamage(2)).to.equal(3)
			expect(LevelRules.bonusDamage(5)).to.equal(12)
			-- 0.05 percentage points per level, not 5 %.
			expect(math.abs(LevelRules.bonusCritChance(2) - 0.0005) < 1e-12).to.equal(true)
			expect(math.abs(LevelRules.bonusCritChance(5) - 0.002) < 1e-12).to.equal(true)
		end)

		it("matches the configured rates", function()
			expect(GameConfig.LevelDamagePerLevel).to.equal(3)
			expect(GameConfig.LevelCritChancePerLevel).to.equal(0.0005)
		end)

		it("adds every level of a multi-level jump", function()
			local damage, crit = LevelRules.gains(10, 13)
			expect(damage).to.equal(9)
			expect(math.abs(crit - 0.0015) < 1e-12).to.equal(true)
			local bigDamage, bigCrit = LevelRules.gains(50, 100)
			expect(bigDamage).to.equal(150)
			expect(math.abs(bigCrit - 0.025) < 1e-12).to.equal(true)
		end)

		it("gives nothing for staying put or going down", function()
			expect((LevelRules.gains(7, 7))).to.equal(0)
			expect((LevelRules.gains(9, 4))).to.equal(0)
		end)

		it("comes from the level alone, so rejoining can't award it twice", function()
			local xp = LevelRules.scoreForLevel(10)
			local first = LevelRules.bonusDamage(LevelRules.levelFor(xp))
			local again = LevelRules.bonusDamage(LevelRules.levelFor(xp))
			expect(first).to.equal(27)
			expect(again).to.equal(first)
		end)
	end)
end
