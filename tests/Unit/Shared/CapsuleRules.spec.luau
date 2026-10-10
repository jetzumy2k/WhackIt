--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CapsuleConfig = require(ReplicatedStorage.Config.CapsuleConfig)
local CapsuleRules = require(ReplicatedStorage.Shared.CapsuleRules)
local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)

return function()
	describe("CapsuleConfig", function()
		it("has weights adding up to 1000 and only real items", function()
			local total = 0
			for _, prize in CapsuleConfig.Prizes do
				total += prize.Weight
				expect(CapsuleConfig.Tiers[prize.Tier]).never.to.equal(nil)
				if prize.Kind == "Bag" then
					local found = false
					for _, product in StoreConfig.Products do
						if product.Key == prize.Key then
							found = true
						end
					end
					expect(found).to.equal(true)
				end
			end
			expect(total).to.equal(1000)
			for _, entry in CapsuleConfig.SupplyPool do
				local item = FurnitureConfig.ByKey[entry.Item]
				expect(item ~= nil and item.Tier == "Special").to.equal(true)
			end
		end)

		it(
			"never pays out more coins on average than a spin costs (a coin sink, not a money printer)",
			function()
				local coins = 0
				for _, prize in CapsuleConfig.Prizes do
					if prize.Kind == "Coins" then
						coins += prize.Amount * prize.Weight / 1000
					end
				end
				expect(coins < CapsuleConfig.Cost).to.equal(true)
			end
		)
	end)

	describe("CapsuleRules", function()
		it("needs the level, coins and a spin left today", function()
			local state = CapsuleRules.defaultState()
			expect((CapsuleRules.canSpin(CapsuleConfig.MinLevel - 1, 9999, state, "D1"))).to.equal(
				false
			)
			expect((CapsuleRules.canSpin(10, CapsuleConfig.Cost - 1, state, "D1"))).to.equal(false)
			expect((CapsuleRules.canSpin(10, CapsuleConfig.Cost, state, "D1"))).to.equal(true)
			for _ = 1, CapsuleConfig.DailySpins do
				CapsuleRules.noteSpin(state, "D1")
			end
			expect((CapsuleRules.canSpin(10, 9999, state, "D1"))).to.equal(false)
			expect((CapsuleRules.canSpin(10, 9999, state, "D2"))).to.equal(true)
			expect(state.TotalSpins).to.equal(CapsuleConfig.DailySpins)
		end)

		it("makes the last spin of the day the lucky one", function()
			local state = CapsuleRules.defaultState()
			for _ = 1, CapsuleConfig.DailySpins - 1 do
				expect(CapsuleRules.nextIsLucky(state, "D1")).to.equal(false)
				CapsuleRules.noteSpin(state, "D1")
			end
			expect(CapsuleRules.nextIsLucky(state, "D1")).to.equal(true)
		end)

		it(
			"picks every prize somewhere in the roll range, and only lucky tiers on a lucky spin",
			function()
				local seen: { [string]: boolean } = {}
				for step = 0, 999 do
					seen[CapsuleRules.pick(step / 1000, false).Id] = true
				end
				for _, prize in CapsuleConfig.Prizes do
					expect(seen[prize.Id]).to.equal(true)
				end
				for step = 0, 99 do
					local prize = CapsuleRules.pick(step / 100, true)
					expect(table.find(CapsuleConfig.LuckyTiers, prize.Tier)).never.to.equal(nil)
				end
				expect(CapsuleRules.pick(1, false)).never.to.equal(nil)
			end
		)

		it("shows odds that add up to 100 %", function()
			for _, lucky in { false, true } do
				local total = 0
				for _, entry in CapsuleRules.odds(lucky) do
					total += entry.Percent
				end
				expect(math.abs(total - 100) < 1e-6).to.equal(true)
			end
		end)

		it("repairs saved state", function()
			local state = CapsuleRules.sanitizeState({ DayKey = "D1", Spins = 99, TotalSpins = -4 })
			expect(state.Spins).to.equal(CapsuleConfig.DailySpins)
			expect(state.TotalSpins).to.equal(0)
		end)
	end)
end
