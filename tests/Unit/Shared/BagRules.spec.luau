--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BagRules = require(ReplicatedStorage.Shared.BagRules)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)

local function gift(id: string, key: string): { [string]: unknown }
	return { GiftId = id, ProductKey = key, FromUserId = 7, FromName = "Friend" }
end

return function()
	describe("BagRules items", function()
		it("lets every boost be gifted, but not the Mystery Hammer, a bundle or an egg", function()
			for _, product in StoreConfig.Products do
				local boost = StoreConfig.BuffKinds[product.Kind] == true
				expect(BagRules.isGiftable(product)).to.equal(boost)
			end
			expect(BagRules.isGiftable(StoreConfig.ByKey.egg_rare)).to.equal(false)
		end)

		it("describes items for players", function()
			local boost = StoreConfig.ByKey.xp_10_30m
			expect(BagRules.itemText(boost)).to.equal("+10% XP boost (30 min)")
			expect(BagRules.itemText(StoreConfig.ByKey.dmg_5_5h)).to.equal("+5% Damage boost (5 h)")
			expect(BagRules.itemText(StoreConfig.ByKey.mystery_hammer)).to.equal(
				StoreConfig.Mystery.DisplayName
			)
			expect(BagRules.itemText(StoreConfig.ByKey.beginner_bundle)).to.equal("Beginner Bundle")
		end)
	end)

	describe("BagRules.grant (bundles)", function()
		it(
			"puts the Beginner Bundle in the Bag as 3 x 30-minute XP, Damage and Crit boosts",
			function()
				local bag: BagRules.Bag = {}
				local added = BagRules.grant(bag, StoreConfig.ByKey.beginner_bundle, 1)
				expect(added).to.equal(9)
				expect(bag.beginner_bundle).to.equal(nil)
				local kinds: { [string]: number } = {}
				for key, count in bag do
					local product = StoreConfig.ByKey[key]
					expect(product.Seconds).to.equal(30 * 60)
					kinds[product.Kind] = (kinds[product.Kind] or 0) + count
				end
				expect(kinds.Xp).to.equal(3)
				expect(kinds.Damage).to.equal(3)
				expect(kinds.CritDamage).to.equal(3)
			end
		)

		it(
			"puts the Stress Reliever Package in as three separate 5-hour boosts of each kind",
			function()
				local bag: BagRules.Bag = {}
				BagRules.grant(bag, StoreConfig.ByKey.stress_reliever_package, 1)
				local kinds: { [string]: number } = {}
				for key, count in bag do
					local product = StoreConfig.ByKey[key]
					-- Separate 5-hour items, never one 15-hour boost.
					expect(product.Seconds).to.equal(5 * 60 * 60)
					kinds[product.Kind] = (kinds[product.Kind] or 0) + count
				end
				expect(kinds.Xp).to.equal(3)
				expect(kinds.Damage).to.equal(3)
				expect(kinds.CritDamage).to.equal(3)
			end
		)

		it(
			"adds to what is already in the Bag, so a second bundle never overwrites the first",
			function()
				local bag: BagRules.Bag = { xp_10_30m = 2, mystery_hammer = 1 }
				BagRules.grant(bag, StoreConfig.ByKey.beginner_bundle, 1)
				BagRules.grant(bag, StoreConfig.ByKey.beginner_bundle, 1)
				expect(bag.xp_10_30m).to.equal(2 + 6)
				expect(bag.mystery_hammer).to.equal(1)
			end
		)

		it("grants a plain item as itself", function()
			local bag: BagRules.Bag = {}
			expect(BagRules.grant(bag, StoreConfig.ByKey.dmg_3_1h, 2)).to.equal(2)
			expect(bag.dmg_3_1h).to.equal(2)
		end)

		it("lists a bundle's contents for the store", function()
			local lines = BagRules.contentsLines(StoreConfig.ByKey.beginner_bundle)
			expect(#lines).to.equal(3)
			expect(string.sub(lines[1], 1, 3)).to.equal("3x ")
			expect(#BagRules.contentsLines(StoreConfig.ByKey.xp_10_30m)).to.equal(0)
		end)
	end)

	describe("BagRules add and take", function()
		it("counts items up and down and removes the last one", function()
			local bag: BagRules.Bag = {}
			BagRules.add(bag, "xp_10_30m", 1)
			BagRules.add(bag, "xp_10_30m", 1)
			expect(bag.xp_10_30m).to.equal(2)
			expect(BagRules.take(bag, "xp_10_30m")).to.equal(true)
			expect(bag.xp_10_30m).to.equal(1)
			expect(BagRules.take(bag, "xp_10_30m")).to.equal(true)
			expect(bag.xp_10_30m).to.equal(nil)
		end)

		it("refuses to take an item the player doesn't have", function()
			local bag: BagRules.Bag = {}
			expect(BagRules.take(bag, "xp_10_30m")).to.equal(false)
			expect((next(bag))).to.equal(nil)
		end)

		it("caps counts", function()
			local bag: BagRules.Bag = { xp_10_30m = BagRules.MAX_COUNT }
			BagRules.add(bag, "xp_10_30m", 5)
			expect(bag.xp_10_30m).to.equal(BagRules.MAX_COUNT)
		end)
	end)

	describe("BagRules saved data", function()
		it("sanitizes a saved Bag", function()
			local bag = BagRules.sanitize({ xp_10_30m = 2.9, nope = 1, dmg_3_1h = -1, [5] = 1 })
			expect(bag.xp_10_30m).to.equal(2)
			expect(bag.nope).to.equal(nil)
			expect(bag.dmg_3_1h).to.equal(nil)
			expect((next(BagRules.sanitize("junk")))).to.equal(nil)
		end)

		it("accepts valid gifts and rejects Mystery Hammers or bad fields", function()
			expect(BagRules.parseGift(gift("p1", "xp_10_30m"))).never.to.equal(nil)
			expect(BagRules.parseGift(gift("p1", "mystery_hammer"))).to.equal(nil)
			expect(BagRules.parseGift(gift("p1", "no_such_item"))).to.equal(nil)
			local noSender = gift("p1", "xp_10_30m")
			noSender.FromUserId = 0
			expect(BagRules.parseGift(noSender)).to.equal(nil)
			expect(BagRules.parseGift("p1")).to.equal(nil)
		end)

		it("keeps unique valid gifts in order, at most MAX_INBOX", function()
			local raw: { unknown } = { gift("a", "xp_10_30m"), "junk", gift("a", "dmg_3_1h") }
			for index = 1, BagRules.MAX_INBOX + 3 do
				table.insert(raw, gift("g" .. index, "crit_3_30m"))
			end
			local gifts = BagRules.parseInbox(raw)
			expect(#gifts).to.equal(BagRules.MAX_INBOX)
			expect(gifts[1].GiftId).to.equal("a")
			expect(gifts[1].ProductKey).to.equal("xp_10_30m")
			expect(gifts[2].GiftId).to.equal("g1")
			expect(#BagRules.parseInbox(nil)).to.equal(0)
		end)
	end)
end
