--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local MissionConfig = require(ReplicatedStorage.Config.MissionConfig)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)

return function()
	describe("MissionConfig", function()
		it("has sensible team sizes", function()
			expect(MissionConfig.TeamMin >= 2).to.equal(true)
			expect(MissionConfig.TeamMax >= MissionConfig.TeamMin).to.equal(true)
			expect(MissionConfig.TeamMax <= 4).to.equal(true)
		end)

		it("borrows real boss looks and has waves that fit a room", function()
			for _, mission in MissionConfig.List do
				expect(MissionConfig.ById[mission.Id]).to.equal(mission)
				expect(#mission.Waves >= 1).to.equal(true)
				expect(mission.TimeLimit > 0).to.equal(true)
				for _, wave in mission.Waves do
					expect(BossConfig.ById[wave.Look]).to.be.ok()
					expect(wave.Count >= 1 and wave.Count <= 4).to.equal(true)
					expect(wave.Health >= 1).to.equal(true)
					expect(#wave.Name > 0).to.equal(true)
				end
			end
		end)

		it("rewards an egg that exists in the store", function()
			local found = false
			for _, product in StoreConfig.Products do
				if product.Key == MissionConfig.Reward.Egg then
					found = true
				end
			end
			expect(found).to.equal(true)
			expect(MissionConfig.Reward.EggChance >= 0 and MissionConfig.Reward.EggChance <= 1).to.equal(
				true
			)
		end)
	end)
end
