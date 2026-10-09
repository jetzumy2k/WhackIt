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

		it("reaches each level exactly at its XP threshold, all the way to the cap", function()
			for level = 2, LevelRules.MAX_LEVEL do
				local needed = LevelRules.scoreForLevel(level)
				expect(LevelRules.levelFor(needed)).to.equal(level)
				expect(LevelRules.levelFor(needed - 1)).to.equal(level - 1)
			end
		end)

		it("keeps the old curve below LevelCurveStartsAt (Level 10 at 48,600 XP)", function()
			for level = 1, GameConfig.LevelCurveStartsAt do
				expect(LevelRules.scoreForLevel(level)).to.equal(600 * (level - 1) ^ 2)
				expect(LevelRules.legacyLevelFor(LevelRules.scoreForLevel(level))).to.equal(level)
			end
			expect(LevelRules.scoreForLevel(10)).to.equal(48600)
		end)

		it("makes every level cost more than the one before", function()
			for level = 2, LevelRules.MAX_LEVEL - 1 do
				expect(LevelRules.costOf(level) > LevelRules.costOf(level - 1)).to.equal(true)
			end
		end)

		it("makes the cap a long-term goal, but reachable", function()
			-- About 70-75 million XP: ~130 hours of ideal solo farming (design
			-- target, docs/GAMEPLAY_RULES.md "Player Level").
			local total = LevelRules.scoreForLevel(LevelRules.MAX_LEVEL)
			expect(total > 60e6 and total < 90e6).to.equal(true)
		end)

		it("stops at the max level while XP keeps counting", function()
			local atMax = LevelRules.scoreForLevel(LevelRules.MAX_LEVEL)
			expect(LevelRules.levelFor(atMax)).to.equal(LevelRules.MAX_LEVEL)
			expect(LevelRules.levelFor(atMax * 10)).to.equal(LevelRules.MAX_LEVEL)
			expect(LevelRules.scoreForLevel(LevelRules.MAX_LEVEL + 5)).to.equal(atMax)
			expect(LevelRules.isMax(LevelRules.MAX_LEVEL)).to.equal(true)
			expect(LevelRules.isMax(LevelRules.MAX_LEVEL - 1)).to.equal(false)
		end)

		it("never goes down as XP grows", function()
			local previous = 1
			for xp = 0, 3000000, 4999 do
				local level = LevelRules.levelFor(xp)
				expect(level >= previous).to.equal(true)
				previous = level
			end
		end)

		it("treats negative or NaN XP as Level 1", function()
			expect(LevelRules.levelFor(-50)).to.equal(1)
			expect(LevelRules.levelFor(0 / 0)).to.equal(1)
			expect(LevelRules.legacyLevelFor(0 / 0)).to.equal(1)
		end)

		it("puts the upstairs level within reach of dedicated play", function()
			local needed = LevelRules.scoreForLevel(GameConfig.UpstairsMinLevel)
			expect(needed > 10000).to.equal(true)
			expect(needed < 500000).to.equal(true)
		end)
	end)

	describe("LevelRules level bonuses", function()
		it(
			"gives +3 damage per level up to Lv 10, then +1, and +0.05 points crit per level",
			function()
				expect(LevelRules.bonusDamage(1)).to.equal(0)
				expect(LevelRules.bonusCritChance(1)).to.equal(0)
				expect(LevelRules.bonusDamage(2)).to.equal(3)
				expect(LevelRules.bonusDamage(10)).to.equal(27)
				expect(LevelRules.bonusDamage(11)).to.equal(28)
				expect(LevelRules.bonusDamage(50)).to.equal(67)
				expect(LevelRules.bonusDamage(100)).to.equal(117)
				-- 0.05 percentage points per level, not 5 %.
				expect(math.abs(LevelRules.bonusCritChance(2) - 0.0005) < 1e-12).to.equal(true)
				expect(math.abs(LevelRules.bonusCritChance(100) - 0.0495) < 1e-12).to.equal(true)
			end
		)

		it("stops growing at the max level", function()
			expect(LevelRules.bonusDamage(LevelRules.MAX_LEVEL + 50)).to.equal(
				LevelRules.bonusDamage(LevelRules.MAX_LEVEL)
			)
			expect(LevelRules.bonusCritChance(500)).to.equal(LevelRules.bonusCritChance(100))
		end)

		it("keeps level damage below what hammers and boosts add at the top", function()
			-- At the cap the level bonus is under 4x the best coin hammer (it was 9x).
			expect(LevelRules.bonusDamage(LevelRules.MAX_LEVEL) < 4 * 32).to.equal(true)
		end)

		it("adds every level of a multi-level jump", function()
			local damage, crit = LevelRules.gains(8, 13)
			expect(damage).to.equal(3 + 3 + 1 + 1 + 1) -- 9, 10, then 11-13
			expect(math.abs(crit - 0.0025) < 1e-12).to.equal(true)
			local bigDamage, bigCrit = LevelRules.gains(50, 100)
			expect(bigDamage).to.equal(50)
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
