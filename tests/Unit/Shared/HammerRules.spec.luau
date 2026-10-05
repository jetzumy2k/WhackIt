--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)
local HammerRules = require(ReplicatedStorage.Shared.HammerRules)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)

return function()
	local mystery = StoreConfig.Mystery

	describe("HammerRules ids", function()
		it("recognises Mystery Hammer ids", function()
			expect(HammerRules.isMysteryId(HammerRules.mysteryId(3))).to.equal(true)
			expect(HammerRules.isMysteryId(GameConfig.DefaultHammerId)).to.equal(false)
		end)
	end)

	describe("HammerRules.rollMystery", function()
		it("only rolls whole values inside the advertised ranges, and reaches every one", function()
			local random = Random.new(42)
			local seenDamage: { [number]: boolean } = {}
			local seenCrit: { [number]: boolean } = {}
			for _ = 1, 2000 do
				local roll = HammerRules.rollMystery(random)
				expect(roll.Damage >= mystery.DamageMin and roll.Damage <= mystery.DamageMax).to.equal(
					true
				)
				expect(roll.Damage % 1).to.equal(0)
				expect(roll.CritDamagePercent >= mystery.CritDamageMinPercent).to.equal(true)
				expect(roll.CritDamagePercent <= mystery.CritDamageMaxPercent).to.equal(true)
				seenDamage[roll.Damage] = true
				seenCrit[roll.CritDamagePercent] = true
			end
			for value = mystery.DamageMin, mystery.DamageMax do
				expect(seenDamage[value]).to.equal(true)
			end
			for value = mystery.CritDamageMinPercent, mystery.CritDamageMaxPercent do
				expect(seenCrit[value]).to.equal(true)
			end
		end)
	end)

	describe("HammerRules.clampRoll", function()
		it("pulls out-of-range saved stats back into range", function()
			local roll = HammerRules.clampRoll({ Damage = 999, CritDamagePercent = -5 })
			expect(roll.Damage).to.equal(mystery.DamageMax)
			expect(roll.CritDamagePercent).to.equal(mystery.CritDamageMinPercent)
		end)
	end)

	describe("HammerRules.resolve", function()
		it("resolves regular hammers with no crit bonus", function()
			local hammer = HammerConfig.ById[GameConfig.DefaultHammerId]
			local stats = HammerRules.resolve(hammer.Id, {})
			expect(stats).never.to.equal(nil)
			expect((stats :: HammerRules.HammerStats).Damage).to.equal(hammer.Damage)
			expect((stats :: HammerRules.HammerStats).CritDamage).to.equal(0)
		end)

		it("resolves an owned Mystery Hammer from its saved roll", function()
			local id = HammerRules.mysteryId(1)
			local stats = HammerRules.resolve(id, { [id] = { Damage = 27, CritDamagePercent = 8 } })
			expect(stats).never.to.equal(nil)
			expect((stats :: HammerRules.HammerStats).Damage).to.equal(27)
			expect((stats :: HammerRules.HammerStats).CritDamage).to.equal(0.08)
		end)

		it("returns nil for unknown or unowned hammers", function()
			expect(HammerRules.resolve("fake_hammer", {})).to.equal(nil)
			expect(HammerRules.resolve(HammerRules.mysteryId(9), {})).to.equal(nil)
		end)
	end)
end
