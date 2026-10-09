--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetConfig = require(ReplicatedStorage.Config.PetConfig)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)

return function()
	describe("StoreConfig", function()
		it(
			"lists 3 XP, 3 Damage and 5 Crit Damage tiers, each in 3 durations, the Mystery Hammer and 2 bundles",
			function()
				local counts: { [string]: number } = {}
				for _, product in StoreConfig.Products do
					counts[product.Kind] = (counts[product.Kind] or 0) + 1
				end
				expect(counts.Xp).to.equal(9)
				expect(counts.Damage).to.equal(9)
				expect(counts.CritDamage).to.equal(15)
				expect(counts.MysteryHammer).to.equal(1)
				expect(counts.Bundle).to.equal(2)
				expect(counts.Egg).to.equal(3)
			end
		)

		it("has unique keys and sane buff values", function()
			local seen: { [string]: boolean } = {}
			for _, product in StoreConfig.Products do
				expect(seen[product.Key]).to.equal(nil)
				seen[product.Key] = true
				expect(StoreConfig.ByKey[product.Key]).to.equal(product)
				expect(product.SuggestedPrice > 0).to.equal(true)
				if StoreConfig.BuffKinds[product.Kind] then
					expect(product.Percent > 0 and product.Percent <= 100).to.equal(true)
					expect(product.Seconds > 0 and product.Seconds <= StoreConfig.MaxBuffSeconds).to.equal(
						true
					)
				end
			end
		end)

		it("prices longer durations higher within a tier", function()
			local byTier: { [string]: { number } } = {}
			for _, product in StoreConfig.Products do
				if StoreConfig.BuffKinds[product.Kind] then
					local tier = product.Kind .. product.Percent
					byTier[tier] = byTier[tier] or {}
					table.insert(byTier[tier], product.SuggestedPrice)
				end
			end
			for _, prices in byTier do
				for index = 2, #prices do
					expect(prices[index] > prices[index - 1]).to.equal(true)
				end
			end
		end)

		it("builds bundles only from boosts on the menu, 3 of each kind", function()
			for _, product in StoreConfig.Products do
				if product.Kind == "Bundle" then
					local contents = product.Contents :: { StoreConfig.BundleItem }
					expect(contents).never.to.equal(nil)
					expect(product.DisplayName).never.to.equal(nil)
					local kinds: { [string]: number } = {}
					for _, item in contents do
						local boost = StoreConfig.ByKey[item.Key]
						expect(StoreConfig.BuffKinds[boost.Kind]).to.equal(true)
						kinds[boost.Kind] = (kinds[boost.Kind] or 0) + item.Count
					end
					expect(kinds.Xp).to.equal(3)
					expect(kinds.Damage).to.equal(3)
					expect(kinds.CritDamage).to.equal(3)
				end
			end
		end)

		it("prices each bundle below buying its contents one by one", function()
			for _, product in StoreConfig.Products do
				if product.Kind == "Bundle" then
					local separate = 0
					for _, item in product.Contents :: { StoreConfig.BundleItem } do
						separate += StoreConfig.ByKey[item.Key].SuggestedPrice * item.Count
					end
					expect(product.SuggestedPrice < separate).to.equal(true)
				end
			end
		end)

		it("sells one egg per pet rarity, named after it", function()
			for _, rarity in PetConfig.Rarities do
				local product = StoreConfig.ByKey[PetConfig.EggKeys[rarity]]
				expect(product).never.to.equal(nil)
				expect(product.Kind).to.equal("Egg")
				expect(product.Rarity).to.equal(rarity)
				expect(product.DisplayName).to.equal(rarity .. " Egg")
			end
		end)

		it("only indexes products that have a Developer Product id", function()
			for productId, product in StoreConfig.ByProductId do
				expect(product.ProductId).to.equal(productId)
				expect(productId ~= 0).to.equal(true)
			end
		end)

		it("has valid Mystery Hammer ranges", function()
			local mystery = StoreConfig.Mystery
			expect(mystery.BaseDamage).to.equal(35)
			expect(mystery.BonusDamageMinPercent).to.equal(15)
			expect(mystery.BonusDamageMaxPercent).to.equal(25)
			expect(mystery.CritDamageMinPercent).to.equal(5)
			expect(mystery.CritDamageMaxPercent).to.equal(10)
			expect(mystery.LegacyBonusDamagePercent >= mystery.BonusDamageMinPercent).to.equal(true)
			expect(mystery.LegacyBonusDamagePercent <= mystery.BonusDamageMaxPercent).to.equal(true)
		end)
	end)
end
