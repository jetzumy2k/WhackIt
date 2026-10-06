--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BagRules = require(ReplicatedStorage.Shared.BagRules)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)

local function gift(id: string, key: string): { [string]: unknown }
	return { GiftId = id, ProductKey = key, FromUserId = 7, FromName = "Friend" }
end

return function()
	describe("BagRules items", function()
		it("lets every boost be gifted, but not the Mystery Hammer", function()
			for _, product in StoreConfig.Products do
				expect(BagRules.isGiftable(product)).to.equal(product.Kind ~= "MysteryHammer")
			end
		end)

		it("describes items for players", function()
			local boost = StoreConfig.ByKey.xp_10_30m
			expect(BagRules.itemText(boost)).to.equal("+10% XP boost (30 min)")
			expect(BagRules.itemText(StoreConfig.ByKey.dmg_5_5h)).to.equal("+5% Damage boost (5 h)")
			expect(BagRules.itemText(StoreConfig.ByKey.mystery_hammer)).to.equal(
				StoreConfig.Mystery.DisplayName
			)
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
