--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)
local PlayerDataSchema = require(ServerScriptService.Lib.PlayerDataSchema)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)

local NAN = 0 / 0

local function validData(): PlayerDataSchema.RawData
	return {
		SchemaVersion = PlayerDataSchema.CURRENT_VERSION,
		Score = 1234,
		Stress = 42.5,
		TotalHits = 300,
		TotalBossesDefeated = 7,
		EquippedHammerId = GameConfig.DefaultHammerId,
		Coins = 250,
		OwnedHammers = {},
		BossDefeats = { [BossConfig.List[1].Id] = 7 },
		ZenLevel = 2,
		ZenArmed = false,
		Xp = 1500,
		Buffs = { Xp = { Percent = 10, SecondsLeft = 600 } },
		ProcessedPurchases = { "receipt-1" },
		MysteryHammers = { mystery_1 = { Damage = 30, CritDamagePercent = 7 } },
		NextMysteryNumber = 2,
	}
end

local function paidHammerId(): string
	for _, hammer in HammerConfig.List do
		if hammer.Price > 0 then
			return hammer.Id
		end
	end
	error("no paid hammer configured")
end

return function()
	describe("PlayerDataSchema.template", function()
		it("starts new players from the game config defaults", function()
			local data = PlayerDataSchema.template()
			expect(data.SchemaVersion).to.equal(PlayerDataSchema.CURRENT_VERSION)
			expect(data.Score).to.equal(GameConfig.StartingScore)
			expect(data.Stress).to.equal(GameConfig.StartingStress)
			expect(data.TotalHits).to.equal(0)
			expect(data.TotalBossesDefeated).to.equal(0)
			expect(data.EquippedHammerId).to.equal(GameConfig.DefaultHammerId)
			expect(data.Coins).to.equal(GameConfig.StartingCoins)
			expect((next(data.OwnedHammers))).to.equal(nil)
			expect((next(data.BossDefeats))).to.equal(nil)
		end)

		it("returns a fresh table each time", function()
			expect(PlayerDataSchema.template()).never.to.equal(PlayerDataSchema.template())
		end)
	end)

	describe("PlayerDataSchema.prepare", function()
		it("keeps valid saved progress unchanged", function()
			local data = validData()
			local ok = PlayerDataSchema.prepare(data)
			expect(ok).to.equal(true)
			expect(data.Score).to.equal(1234)
			expect(data.Stress).to.equal(42.5)
			expect(data.TotalHits).to.equal(300)
			expect(data.TotalBossesDefeated).to.equal(7)
		end)

		it("upgrades unversioned (v0) data and fills missing fields", function()
			local data: PlayerDataSchema.RawData = { Score = 50 }
			local ok = PlayerDataSchema.prepare(data)
			expect(ok).to.equal(true)
			expect(data.SchemaVersion).to.equal(PlayerDataSchema.CURRENT_VERSION)
			expect(data.Score).to.equal(50)
			expect(data.Stress).to.equal(GameConfig.StartingStress)
			expect(data.EquippedHammerId).to.equal(GameConfig.DefaultHammerId)
		end)

		it("repairs corrupt counters instead of trusting them", function()
			local data = validData()
			data.Score = NAN
			data.TotalHits = -5
			data.TotalBossesDefeated = "lots"
			PlayerDataSchema.prepare(data)
			expect(data.Score).to.equal(GameConfig.StartingScore)
			expect(data.TotalHits).to.equal(0)
			expect(data.TotalBossesDefeated).to.equal(0)
		end)

		it("rounds fractional counters down and caps huge ones", function()
			local data = validData()
			data.Score = 10.9
			data.TotalHits = math.huge
			data.TotalBossesDefeated = 1e300
			PlayerDataSchema.prepare(data)
			expect(data.Score).to.equal(10)
			expect(data.TotalHits).to.equal(0) -- infinity is invalid, not "very large"
			expect((data.TotalBossesDefeated :: number) <= 2 ^ 50).to.equal(true)
		end)

		it("keeps stress within 0..MaxStress", function()
			local high = validData()
			high.Stress = 999
			PlayerDataSchema.prepare(high)
			expect(high.Stress).to.equal(GameConfig.MaxStress)

			local low = validData()
			low.Stress = -3
			PlayerDataSchema.prepare(low)
			expect(low.Stress).to.equal(0)
		end)

		it("falls back to the default hammer for unknown hammers", function()
			local data = validData()
			data.EquippedHammerId = "golden_hammer_of_cheating"
			PlayerDataSchema.prepare(data)
			expect(data.EquippedHammerId).to.equal(GameConfig.DefaultHammerId)
		end)

		it("refuses data from a newer schema and leaves it untouched", function()
			local data = validData()
			data.SchemaVersion = PlayerDataSchema.CURRENT_VERSION + 1
			data.Score = NAN -- would be "repaired" if sanitize ran
			local ok, reason = PlayerDataSchema.prepare(data)
			expect(ok).to.equal(false)
			expect(reason).never.to.equal(nil)
			expect(data.Score ~= data.Score).to.equal(true) -- still NaN: untouched
		end)

		it("keeps unknown extra fields", function()
			local data = validData()
			data.FutureField = "keep me"
			PlayerDataSchema.prepare(data)
			expect(data.FutureField).to.equal("keep me")
		end)
	end)

	describe("PlayerDataSchema.migrate", function()
		it("runs each migration once, in order", function()
			local order: { number } = {}
			local migrations: { [number]: PlayerDataSchema.Migration } = {
				[1] = function()
					table.insert(order, 1)
				end,
				[2] = function()
					table.insert(order, 2)
				end,
				[3] = function()
					table.insert(order, 3)
				end,
			}
			local data: PlayerDataSchema.RawData = { SchemaVersion = 1 }
			local ok = PlayerDataSchema.migrate(data, migrations, 3)
			expect(ok).to.equal(true)
			expect(#order).to.equal(2)
			expect(order[1]).to.equal(2)
			expect(order[2]).to.equal(3)
			expect(data.SchemaVersion).to.equal(3) -- the target passed in, not CURRENT_VERSION
		end)

		it("is a no-op for data already at the target version", function()
			local data: PlayerDataSchema.RawData = { SchemaVersion = 2 }
			local ok = PlayerDataSchema.migrate(data, {}, 2)
			expect(ok).to.equal(true)
			-- Explicit target 2, independent of the current schema version.
			expect(data.SchemaVersion).to.equal(2)
		end)

		it("fails when a migration step is missing", function()
			local data: PlayerDataSchema.RawData = { SchemaVersion = 0 }
			local ok = PlayerDataSchema.migrate(data, {}, 1)
			expect(ok).to.equal(false)
		end)

		it("defines a migration for every version up to the current one", function()
			for version = 1, PlayerDataSchema.CURRENT_VERSION do
				expect(PlayerDataSchema.MIGRATIONS[version]).never.to.equal(nil)
			end
		end)
	end)
	describe("PlayerDataSchema v2 (coins, hammers, boss defeats)", function()
		it("migrates v1 data: no coins, nothing bought, Deadline defeats carried over", function()
			local data: PlayerDataSchema.RawData = {
				SchemaVersion = 1,
				Score = 900,
				Stress = 60,
				TotalHits = 120,
				TotalBossesDefeated = 4,
				EquippedHammerId = GameConfig.DefaultHammerId,
			}
			local ok = PlayerDataSchema.prepare(data)
			expect(ok).to.equal(true)
			expect(data.SchemaVersion).to.equal(PlayerDataSchema.CURRENT_VERSION)
			expect(data.Score).to.equal(900)
			expect(data.Coins).to.equal(0)
			expect((next(data.OwnedHammers :: { [string]: boolean }))).to.equal(nil)
			local defeats = data.BossDefeats :: { [string]: number }
			expect(defeats[BossConfig.List[1].Id]).to.equal(4)
		end)

		it("keeps bought hammers and drops unknown or non-true entries", function()
			local paid = paidHammerId()
			local data = validData()
			-- Deliberately invalid mix, as corrupt saved data might contain.
			local mixed: { [string]: unknown } =
				{ [paid] = true, fake_hammer = true, [GameConfig.DefaultHammerId] = "yes" }
			data.OwnedHammers = mixed
			PlayerDataSchema.prepare(data)
			local owned = data.OwnedHammers :: { [string]: boolean }
			expect(owned[paid]).to.equal(true)
			expect(owned.fake_hammer).to.equal(nil)
			expect(owned[GameConfig.DefaultHammerId]).to.equal(nil)
		end)

		it("repairs a non-table OwnedHammers", function()
			local data = validData()
			data.OwnedHammers = "everything"
			PlayerDataSchema.prepare(data)
			expect(typeof(data.OwnedHammers)).to.equal("table")
		end)

		it("keeps valid boss defeats and drops unknown bosses or bad counts", function()
			local data = validData()
			data.BossDefeats =
				{ [BossConfig.List[2].Id] = 3, imaginary_boss = 50, [BossConfig.List[3].Id] = -2 }
			PlayerDataSchema.prepare(data)
			local defeats = data.BossDefeats :: { [string]: number }
			expect(defeats[BossConfig.List[2].Id]).to.equal(3)
			expect(defeats.imaginary_boss).to.equal(nil)
			expect(defeats[BossConfig.List[3].Id]).to.equal(nil)
		end)

		it("unequips a hammer the player doesn't own", function()
			local data = validData()
			data.EquippedHammerId = paidHammerId()
			data.OwnedHammers = {}
			PlayerDataSchema.prepare(data)
			expect(data.EquippedHammerId).to.equal(GameConfig.DefaultHammerId)
		end)

		it("keeps an owned paid hammer equipped", function()
			local paid = paidHammerId()
			local data = validData()
			data.EquippedHammerId = paid
			data.OwnedHammers = { [paid] = true }
			PlayerDataSchema.prepare(data)
			expect(data.EquippedHammerId).to.equal(paid)
		end)

		it("repairs negative or invalid coins", function()
			local data = validData()
			data.Coins = -500
			PlayerDataSchema.prepare(data)
			expect(data.Coins).to.equal(0)
		end)
	end)
	describe("PlayerDataSchema v3 (Zen)", function()
		it("migrates v2 data to Zen Level 0 with the first Zen armed", function()
			local data: PlayerDataSchema.RawData = {
				SchemaVersion = 2,
				Score = 10,
				Stress = 40,
				TotalHits = 1,
				TotalBossesDefeated = 0,
				EquippedHammerId = GameConfig.DefaultHammerId,
				Coins = 5,
				OwnedHammers = {},
				BossDefeats = {},
			}
			expect((PlayerDataSchema.prepare(data))).to.equal(true)
			expect(data.SchemaVersion).to.equal(PlayerDataSchema.CURRENT_VERSION)
			expect(data.ZenLevel).to.equal(0)
			expect(data.ZenArmed).to.equal(true)
		end)

		it("keeps a saved Zen Level and disarmed state", function()
			local data = validData()
			PlayerDataSchema.prepare(data)
			expect(data.ZenLevel).to.equal(2)
			expect(data.ZenArmed).to.equal(false)
		end)

		it("repairs invalid Zen fields", function()
			local data = validData()
			data.ZenLevel = -4
			data.ZenArmed = "yes"
			PlayerDataSchema.prepare(data)
			expect(data.ZenLevel).to.equal(0)
			expect(data.ZenArmed).to.equal(true)
		end)
	end)
	describe("PlayerDataSchema v4 (XP, buffs, purchases, Mystery Hammers)", function()
		it("migrates v3 data: XP starts at the old Score, nothing bought", function()
			local data: PlayerDataSchema.RawData = {
				SchemaVersion = 3,
				Score = 4200,
				Stress = 40,
				TotalHits = 1,
				TotalBossesDefeated = 0,
				EquippedHammerId = GameConfig.DefaultHammerId,
				Coins = 5,
				OwnedHammers = {},
				BossDefeats = {},
				ZenLevel = 1,
				ZenArmed = true,
			}
			expect((PlayerDataSchema.prepare(data))).to.equal(true)
			expect(data.Xp).to.equal(4200)
			expect((next(data.Buffs :: {}))).to.equal(nil)
			expect(#(data.ProcessedPurchases :: {})).to.equal(0)
			expect((next(data.MysteryHammers :: {}))).to.equal(nil)
			expect(data.NextMysteryNumber).to.equal(1)
		end)

		it("keeps valid buffs, purchases and Mystery Hammers", function()
			local data = validData()
			PlayerDataSchema.prepare(data)
			local buffs = data.Buffs :: { [string]: { Percent: number, SecondsLeft: number } }
			expect(buffs.Xp.Percent).to.equal(10)
			expect(buffs.Xp.SecondsLeft).to.equal(600)
			expect((data.ProcessedPurchases :: { string })[1]).to.equal("receipt-1")
			local mystery = data.MysteryHammers :: { [string]: { Damage: number } }
			expect(mystery.mystery_1.Damage).to.equal(30)
		end)

		it("drops unknown buff kinds and clamps buff values", function()
			local data = validData()
			data.Buffs = {
				Xp = { Percent = 500, SecondsLeft = 1e12 },
				Damage = { Percent = 5, SecondsLeft = -1 },
				Godmode = { Percent = 100, SecondsLeft = 60 },
			}
			PlayerDataSchema.prepare(data)
			local buffs = data.Buffs :: { [string]: { Percent: number, SecondsLeft: number } }
			expect(buffs.Xp.Percent).to.equal(100)
			expect(buffs.Xp.SecondsLeft).to.equal(StoreConfig.MaxBuffSeconds)
			expect(buffs.Damage).to.equal(nil)
			expect(buffs.Godmode).to.equal(nil)
		end)

		it(
			"keeps only string purchase ids, at most MAX_PROCESSED_PURCHASES, newest kept",
			function()
				local data = validData()
				local ids: { unknown } = { 42, "" }
				for index = 1, PlayerDataSchema.MAX_PROCESSED_PURCHASES + 5 do
					table.insert(ids, "r" .. index)
				end
				data.ProcessedPurchases = ids
				PlayerDataSchema.prepare(data)
				local kept = data.ProcessedPurchases :: { string }
				expect(#kept).to.equal(PlayerDataSchema.MAX_PROCESSED_PURCHASES)
				expect(kept[#kept]).to.equal("r" .. (PlayerDataSchema.MAX_PROCESSED_PURCHASES + 5))
			end
		)

		it("clamps a paid Mystery Hammer's stats instead of deleting it", function()
			local data = validData()
			data.MysteryHammers = {
				mystery_1 = { Damage = 9999, CritDamagePercent = 1 },
				not_mystery = { Damage = 30, CritDamagePercent = 7 },
			}
			PlayerDataSchema.prepare(data)
			local mystery =
				data.MysteryHammers :: { [string]: { Damage: number, CritDamagePercent: number } }
			expect(mystery.mystery_1.Damage).to.equal(StoreConfig.Mystery.DamageMax)
			expect(mystery.mystery_1.CritDamagePercent).to.equal(
				StoreConfig.Mystery.CritDamageMinPercent
			)
			expect(mystery.not_mystery).to.equal(nil)
		end)

		it("lets a player keep an owned Mystery Hammer equipped, but not an unowned one", function()
			local owned = validData()
			owned.EquippedHammerId = "mystery_1"
			PlayerDataSchema.prepare(owned)
			expect(owned.EquippedHammerId).to.equal("mystery_1")

			local unowned = validData()
			unowned.EquippedHammerId = "mystery_99"
			PlayerDataSchema.prepare(unowned)
			expect(unowned.EquippedHammerId).to.equal(GameConfig.DefaultHammerId)
		end)
	end)
end
