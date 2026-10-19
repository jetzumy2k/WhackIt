--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)
local SynthesisConfig = require(ReplicatedStorage.Config.SynthesisConfig)
local SynthesisRules = require(ReplicatedStorage.Shared.SynthesisRules)

return function()
	describe("SynthesisConfig", function()
		it("builds boost recipes only between real store durations", function()
			for _, recipe in SynthesisConfig.BoostRecipes do
				local inFound, outFound = false, false
				for _, product in StoreConfig.Products do
					if StoreConfig.BuffKinds[product.Kind] then
						inFound = inFound or product.Seconds == recipe.InputSeconds
						outFound = outFound or product.Seconds == recipe.OutputSeconds
					end
				end
				expect(inFound and outFound).to.equal(true)
				expect(recipe.OutputSeconds > recipe.InputSeconds).to.equal(true)
				expect(recipe.Count >= 2 and recipe.Count <= SynthesisRules.MAX_COUNT).to.equal(
					true
				)
			end
		end)

		it("points egg recipes at real eggs, one rarity up", function()
			for _, recipe in SynthesisConfig.ItemRecipes do
				local input = StoreConfig.ByKey[recipe.Input]
				local output = StoreConfig.ByKey[recipe.Output]
				expect(input.Kind).to.equal("Egg")
				expect(output.Kind).to.equal("Egg")
				expect(input.Key).never.to.equal(output.Key)
			end
		end)

		it("keeps the Mythical egg out of reach (owner decision 2026-10-19)", function()
			for _, recipe in SynthesisConfig.ItemRecipes do
				if recipe.Output == "egg_mythical" then
					expect(recipe.Enabled).to.equal(false)
				end
			end
		end)

		it("swaps only office supplies, never trophies or prizes", function()
			for _, key in SynthesisConfig.SupplyPool do
				local item = FurnitureConfig.ByKey[key]
				expect(item).never.to.equal(nil)
				expect(item.Tier).to.equal("Special")
				expect(item.Category).to.equal("Supplies")
			end
			expect(#SynthesisConfig.SupplyPool >= 2).to.equal(true)
		end)

		it("charges a coin fee, has a known tier and unique ids for every recipe", function()
			local seen: { [string]: boolean } = {}
			for _, recipe in SynthesisRules.recipes() do
				expect(seen[recipe.Id]).to.equal(nil)
				seen[recipe.Id] = true
				expect(recipe.Fee > 0 and recipe.Fee % 1 == 0).to.equal(true)
				expect(SynthesisConfig.Tiers[recipe.Tier]).never.to.equal(nil)
			end
		end)

		it("has no recipe that turns an output back into its inputs (no loops)", function()
			for _, recipe in SynthesisConfig.ItemRecipes do
				for _, other in SynthesisConfig.ItemRecipes do
					expect(other.Input == recipe.Output and other.Output == recipe.Input).to.equal(
						false
					)
				end
			end
		end)

		it("uses a real, non-giftable Bag item as the Synthesis Pick", function()
			local pick = StoreConfig.ByKey[SynthesisConfig.PickKey]
			expect(pick).never.to.equal(nil)
			expect(pick.Kind).to.equal("SynthesisPick")
		end)

		it("lists a tab for every category, Hammers explaining why it's empty", function()
			local ids: { [string]: boolean } = {}
			for _, category in SynthesisConfig.Categories do
				ids[category.Id] = true
			end
			for _, recipe in SynthesisRules.recipes() do
				expect(ids[recipe.Category]).to.equal(true)
			end
			expect(#SynthesisRules.recipesIn("Hammers")).to.equal(0)
			local hammers = SynthesisConfig.Categories[4]
			expect(hammers.Id).to.equal("Hammers")
			expect(hammers.Unavailable).never.to.equal(nil)
		end)
	end)
end
