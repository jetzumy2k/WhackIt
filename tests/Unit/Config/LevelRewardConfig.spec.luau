--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)
local LevelRewardConfig = require(ReplicatedStorage.Config.LevelRewardConfig)

return function()
	describe("LevelRewardConfig", function()
		it("starts titles at Level 1, one per milestone, the last at the cap", function()
			local titles = LevelRewardConfig.Titles
			expect(titles[1].Level).to.equal(1)
			expect(titles[#titles].Level).to.equal(GameConfig.MaxLevel)
			for index = 2, #titles do
				expect(titles[index].Level > titles[index - 1].Level).to.equal(true)
				expect(#titles[index].Name > 0 and #titles[index].Name <= 24).to.equal(true)
			end
		end)

		it("puts trails and glows on multiples of 5 within the cap, indexed by id", function()
			local function check(
				list: { LevelRewardConfig.Cosmetic },
				byId: { [string]: LevelRewardConfig.Cosmetic }
			): ()
				for _, item in list do
					expect(byId[item.Id]).to.equal(item)
					expect(item.Level % 5).to.equal(0)
					expect(item.Level > 1 and item.Level <= GameConfig.MaxLevel).to.equal(true)
				end
			end
			check(LevelRewardConfig.Trails, LevelRewardConfig.TrailsById)
			check(LevelRewardConfig.Glows, LevelRewardConfig.GlowsById)
		end)

		it("never puts two rewards of the track on the same level", function()
			local used: { [number]: string } = {}
			local function claim(level: number, what: string): ()
				if used[level] then
					error(string.format("Lv %d has both %s and %s", level, used[level], what))
				end
				used[level] = what
			end
			for _, title in LevelRewardConfig.Titles do
				if title.Level > 1 then
					claim(title.Level, title.Name)
				end
			end
			for _, item in LevelRewardConfig.Trails do
				claim(item.Level, item.Name)
			end
			for _, item in LevelRewardConfig.Glows do
				claim(item.Level, item.Name)
			end
		end)

		it("pays a sensible amount over the whole climb", function()
			local total = 0
			for level = 2, GameConfig.MaxLevel do
				total += LevelRewardConfig.CoinsPerLevel * level
			end
			-- About 100k coins: worth having next to 8,000-coin hammers, not a flood.
			expect(total > 50000 and total < 200000).to.equal(true)
		end)
	end)

	describe("HammerConfig level requirements", function()
		it("only puts them on paid hammers, within the cap, rising down the shop", function()
			local previous = 0
			for _, hammer in HammerConfig.List do
				local need = hammer.MinLevel
				if need then
					expect(hammer.Price > 0).to.equal(true)
					expect(need >= previous and need <= GameConfig.MaxLevel).to.equal(true)
					previous = need
				end
			end
			expect(previous > 0).to.equal(true)
		end)
	end)
end
