--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local LevelRewardConfig = require(ReplicatedStorage.Config.LevelRewardConfig)
local LevelRewardRules = require(ReplicatedStorage.Shared.LevelRewardRules)

return function()
	describe("LevelRewardRules titles and coins", function()
		it("gives the highest title reached", function()
			expect(LevelRewardRules.titleFor(1)).to.equal("Intern")
			expect(LevelRewardRules.titleFor(4)).to.equal("Intern")
			expect(LevelRewardRules.titleFor(10)).to.equal("Associate")
			expect(LevelRewardRules.titleFor(19)).to.equal("Associate")
			expect(LevelRewardRules.titleFor(100)).to.equal("Chief Calm Officer")
		end)

		it("pays CoinsPerLevel x level for every new level, never past the cap", function()
			local per = LevelRewardConfig.CoinsPerLevel
			expect(LevelRewardRules.coinsBetween(1, 2)).to.equal(per * 2)
			expect(LevelRewardRules.coinsBetween(9, 12)).to.equal(per * (10 + 11 + 12))
			expect(LevelRewardRules.coinsBetween(12, 12)).to.equal(0)
			expect(LevelRewardRules.coinsBetween(12, 5)).to.equal(0)
			expect(LevelRewardRules.coinsBetween(99, 150)).to.equal(per * 100)
		end)
	end)

	describe("LevelRewardRules reward track", function()
		it("unlocks something every 5 levels, up to the cap", function()
			for level = 5, GameConfig.MaxLevel, 5 do
				expect(#LevelRewardRules.rewardsAt(level) > 0).to.equal(true)
			end
		end)

		it("lists the Senior floor, the hammer requirements and the golden tag", function()
			local function has(level: number, needle: string): boolean
				for _, line in LevelRewardRules.rewardsAt(level) do
					if string.find(line, needle, 1, true) then
						return true
					end
				end
				return false
			end
			expect(has(GameConfig.UpstairsMinLevel, "Senior floor")).to.equal(true)
			expect(has(15, "Fire Hammer")).to.equal(true)
			expect(has(40, "Stress Crusher")).to.equal(true)
			expect(has(GameConfig.MaxLevel, "golden")).to.equal(true)
		end)

		it("points to the next milestone, and to nothing at the cap", function()
			local nextLevel, lines = LevelRewardRules.nextMilestone(1)
			expect(nextLevel).to.equal(5)
			expect(#lines > 0).to.equal(true)
			expect((LevelRewardRules.nextMilestone(GameConfig.MaxLevel))).to.equal(nil)
		end)
	end)

	describe("LevelRewardRules looks", function()
		it("unlocks a trail or glow at its level, and the default always", function()
			local mint = LevelRewardConfig.TrailsById.mint
			expect(LevelRewardRules.isUnlocked("Trail", "mint", mint.Level - 1)).to.equal(false)
			expect(LevelRewardRules.isUnlocked("Trail", "mint", mint.Level)).to.equal(true)
			expect(LevelRewardRules.isUnlocked("Glow", "", 1)).to.equal(true)
			expect(LevelRewardRules.isUnlocked("Glow", "mint", 100)).to.equal(false) -- a trail id
		end)

		it("falls back to the default look while a pick is locked", function()
			expect(LevelRewardRules.effective("Trail", "mint", 1)).to.equal("")
			expect(LevelRewardRules.effective("Trail", "mint", 99)).to.equal("mint")
		end)

		it("accepts only known kinds and ids from the client", function()
			local kind, id = LevelRewardRules.parseChoice("Glow", "ocean")
			expect(kind).to.equal("Glow")
			expect(id).to.equal("ocean")
			kind, id = LevelRewardRules.parseChoice("Trail", "")
			expect(kind).to.equal("Trail")
			expect(id).to.equal("")
			for _, bad in
				{ { "Hat", "ocean" }, { "Glow", "nope" }, { "Glow", 5 }, { nil, "" } } :: { { unknown } }
			do
				local badKind, badId = LevelRewardRules.parseChoice(bad[1], bad[2])
				expect(badKind).to.equal(nil)
				expect(badId).to.equal(nil)
			end
		end)

		it("handles office themes as a third look", function()
			local kind, id = LevelRewardRules.parseChoice("Office", "garden")
			expect(kind).to.equal("Office")
			expect(id).to.equal("garden")
			local garden = LevelRewardConfig.OfficeThemesById.garden
			expect(LevelRewardRules.isUnlocked("Office", "garden", garden.Level - 1)).to.equal(
				false
			)
			expect(LevelRewardRules.isUnlocked("Office", "garden", garden.Level)).to.equal(true)
			expect(LevelRewardRules.sanitizeCosmetics({ Office = "garden" }).Office).to.equal(
				"garden"
			)
			expect(LevelRewardRules.sanitizeCosmetics({ Office = "ocean" }).Office).to.equal("")
		end)

		it("lists office themes and level-reward furniture on the track", function()
			local function has(level: number, needle: string): boolean
				for _, line in LevelRewardRules.rewardsAt(level) do
					if string.find(line, needle, 1, true) then
						return true
					end
				end
				return false
			end
			expect(has(10, "Warm Wood Office")).to.equal(true)
			expect(has(30, "Office: Aquarium")).to.equal(true)
			expect(has(100, "Office: Golden Hammer Statue")).to.equal(true)
		end)

		it("keeps saved picks that exist, even while locked, and drops the rest", function()
			local picks = LevelRewardRules.sanitizeCosmetics({ Trail = "prism", Glow = "disco" })
			expect(picks.Trail).to.equal("prism")
			expect(picks.Glow).to.equal("")
			local empty = LevelRewardRules.sanitizeCosmetics("broken")
			expect(empty.Trail).to.equal("")
		end)
	end)
end
