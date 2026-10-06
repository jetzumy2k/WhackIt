--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CustomBossConfig = require(ReplicatedStorage.Config.CustomBossConfig)
local CustomBossRules = require(ReplicatedStorage.Shared.CustomBossRules)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)

local function validSpec(): { [string]: unknown }
	return {
		Name = "Printer Jam",
		LookId = CustomBossConfig.LookIds[1],
		MaxHealth = 500,
		ScoreReward = 300,
		CoinReward = 50,
	}
end

local function validRecord(id: string): { [string]: unknown }
	local record = validSpec()
	record.Id = id
	record.X = 10
	record.Y = 4
	record.Z = -20
	record.CreatedBy = 123
	return record
end

local function product(
	kind: string,
	percent: number,
	productId: number,
	seconds: number?
): StoreConfig.Product
	local fake: { [string]: unknown } = {
		Key = string.format("%s_%d_%d", kind, percent, productId),
		Kind = kind,
		Percent = percent,
		Seconds = seconds or CustomBossConfig.BuffDropSeconds,
		SuggestedPrice = 10,
		ProductId = productId,
	}
	return (fake :: any) :: StoreConfig.Product
end

local function pick(options: { CustomBossRules.Drop }, roll: number): string?
	local drop = CustomBossRules.pickDrop(options, roll)
	return if drop then drop.Kind else nil
end

return function()
	describe("CustomBossRules ids and names", function()
		it("recognises custom ids by prefix", function()
			expect(CustomBossRules.isCustomId("custom_1_2345")).to.equal(true)
			expect(CustomBossRules.isCustomId("deadline_boss")).to.equal(false)
			expect(CustomBossRules.isCustomId("custom")).to.equal(false)
		end)

		it("trims and collapses whitespace in names", function()
			expect(CustomBossRules.cleanName("  Printer   Jam  ")).to.equal("Printer Jam")
			expect(CustomBossRules.cleanName("   ")).to.equal("")
		end)
	end)

	describe("CustomBossRules.parseSpec", function()
		it("accepts a valid spec", function()
			local spec = CustomBossRules.parseSpec(validSpec())
			expect(spec).never.to.equal(nil)
			local parsed = spec :: CustomBossRules.Spec
			expect(parsed.Name).to.equal("Printer Jam")
			expect(parsed.MaxHealth).to.equal(500)
		end)

		it("rejects non-tables, empty or long names, and unknown looks", function()
			expect((CustomBossRules.parseSpec("boss"))).to.equal(nil)
			local empty = validSpec()
			empty.Name = "    "
			expect((CustomBossRules.parseSpec(empty))).to.equal(nil)
			local long = validSpec()
			long.Name = string.rep("a", CustomBossConfig.NameMaxLength + 1)
			expect((CustomBossRules.parseSpec(long))).to.equal(nil)
			local look = validSpec()
			look.LookId = "the_ceo"
			expect((CustomBossRules.parseSpec(look))).to.equal(nil)
		end)

		it("rejects out-of-range, fractional and non-finite numbers", function()
			local bads: { unknown } =
				{ 0, CustomBossConfig.MaxHealth + 1, 12.5, 0 / 0, math.huge, "500" }
			for _, bad in bads do
				local spec = validSpec()
				spec.MaxHealth = bad
				expect((CustomBossRules.parseSpec(spec))).to.equal(nil)
			end
			local score = validSpec()
			score.ScoreReward = CustomBossConfig.MaxScoreReward + 1
			expect((CustomBossRules.parseSpec(score))).to.equal(nil)
			local coins = validSpec()
			coins.CoinReward = -1
			expect((CustomBossRules.parseSpec(coins))).to.equal(nil)
		end)
	end)

	describe("CustomBossRules saved records", function()
		it("parses a valid record", function()
			local record = CustomBossRules.parseRecord(validRecord("custom_1_1000"))
			expect(record).never.to.equal(nil)
			expect((record :: CustomBossRules.Record).Z).to.equal(-20)
		end)

		it("rejects records with a non-custom id or a bad position", function()
			expect(CustomBossRules.parseRecord(validRecord("deadline_boss"))).to.equal(nil)
			local far = validRecord("custom_1_1000")
			far.X = 1e9
			expect(CustomBossRules.parseRecord(far)).to.equal(nil)
		end)

		it("drops bad entries and duplicates and keeps at most MaxBosses", function()
			local raw: { unknown } =
				{ validRecord("custom_1_1000"), "junk", validRecord("custom_1_1000") }
			for index = 1, CustomBossConfig.MaxBosses + 5 do
				table.insert(raw, validRecord("custom_2_" .. (1000 + index)))
			end
			local list = CustomBossRules.parseList(raw)
			expect(#list).to.equal(CustomBossConfig.MaxBosses)
			expect(list[1].Id).to.equal("custom_1_1000")
			expect(list[2].Id).never.to.equal("custom_1_1000")
			expect(#CustomBossRules.parseList(nil)).to.equal(0)
		end)

		it("turns a record into an open, normal-damage, custom definition", function()
			local record = CustomBossRules.parseRecord(validRecord("custom_1_1000"))
			local definition = CustomBossRules.definitionFor(record :: CustomBossRules.Record)
			expect(definition.Id).to.equal("custom_1_1000")
			expect(definition.DisplayName).to.equal("Printer Jam")
			expect(definition.DamageTakenMultiplier).to.equal(1)
			expect(definition.Custom).to.equal(true)
			expect(definition.LookId).to.equal(CustomBossConfig.LookIds[1])
			expect(definition.UnlockAfterBossId).to.equal(nil)
			expect(definition.MinLevel).to.equal(nil)
		end)
	end)

	describe("CustomBossRules spacing", function()
		it("needs MinSpacing from every other boss", function()
			local others = { Vector3.new(0, 4, 0) }
			local spacing = CustomBossConfig.MinSpacing
			expect(CustomBossRules.hasSpace(Vector3.new(spacing, 4, 0), others)).to.equal(true)
			expect(CustomBossRules.hasSpace(Vector3.new(spacing - 1, 4, 0), others)).to.equal(false)
			expect(CustomBossRules.hasSpace(Vector3.zero, {})).to.equal(true)
		end)
	end)

	describe("CustomBossRules buff drops", function()
		it(
			"offers each strength on sale once, as its 30-minute item, never the Mystery Hammer",
			function()
				local options = CustomBossRules.dropOptions({
					product("Xp", 10, 0), -- 30 min not on sale...
					product("Xp", 10, 2, 3600), -- ...but the 1 h is, so XP +10% can drop
					product("Damage", 5, 3),
					product("CritDamage", 20, 0), -- not on sale at all
					product("MysteryHammer", 0, 4),
				})
				expect(#options).to.equal(2)
				for _, drop in options do
					expect(drop.Kind).never.to.equal("MysteryHammer")
					expect(drop.Kind).never.to.equal("CritDamage")
				end
				-- The Bag item is always the 30-minute product.
				expect(options[1].Key).to.equal("Xp_10_0")
			end
		)

		it("falls back to every boost when none is on sale yet", function()
			local options =
				CustomBossRules.dropOptions({ product("Xp", 10, 0), product("Damage", 5, 0) })
			expect(#options).to.equal(2)
		end)

		it("picks within the list for any roll", function()
			local options = {
				{ Kind = "Xp", Percent = 10, Key = "a" },
				{ Kind = "Damage", Percent = 5, Key = "b" },
			}
			expect(pick(options, 0)).to.equal("Xp")
			expect(pick(options, 0.999)).to.equal("Damage")
			expect(pick(options, 1)).to.equal("Damage")
			expect(pick({}, 0.5)).to.equal(nil)
		end)

		it("can drop from the real store config, only real 30-minute products", function()
			local options = CustomBossRules.dropOptions(StoreConfig.Products)
			expect(#options > 0).to.equal(true)
			for _, drop in options do
				local item = StoreConfig.ByKey[drop.Key]
				expect(item).never.to.equal(nil)
				expect(item.Seconds).to.equal(CustomBossConfig.BuffDropSeconds)
			end
		end)
	end)
end
