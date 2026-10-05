--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)

return function()
	describe("StoreConfig", function()
		it(
			"lists 3 XP, 3 Damage and 5 Crit Damage tiers, each in 3 durations, plus the Mystery Hammer",
			function()
				local counts: { [string]: number } = {}
				for _, product in StoreConfig.Products do
					counts[product.Kind] = (counts[product.Kind] or 0) + 1
				end
				expect(counts.Xp).to.equal(9)
				expect(counts.Damage).to.equal(9)
				expect(counts.CritDamage).to.equal(15)
				expect(counts.MysteryHammer).to.equal(1)
			end
		)

		it("has unique keys and sane buff values", function()
			local seen: { [string]: boolean } = {}
			for _, product in StoreConfig.Products do
				expect(seen[product.Key]).to.equal(nil)
				seen[product.Key] = true
				expect(StoreConfig.ByKey[product.Key]).to.equal(product)
				expect(product.SuggestedPrice > 0).to.equal(true)
				if product.Kind ~= "MysteryHammer" then
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
				if product.Kind ~= "MysteryHammer" then
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

		it("only indexes products that have a Developer Product id", function()
			for productId, product in StoreConfig.ByProductId do
				expect(product.ProductId).to.equal(productId)
				expect(productId ~= 0).to.equal(true)
			end
		end)

		it("has valid Mystery Hammer ranges", function()
			local mystery = StoreConfig.Mystery
			expect(mystery.DamageMin <= mystery.DamageMax).to.equal(true)
			expect(mystery.CritDamageMinPercent <= mystery.CritDamageMaxPercent).to.equal(true)
		end)
	end)
end
