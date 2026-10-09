--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local CombatRules = require(ReplicatedStorage.Shared.CombatRules)
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
		it("always has 35 base damage and whole bonuses in range, reaching every value", function()
			local random = Random.new(42)
			local seenBonus: { [number]: boolean } = {}
			local seenCrit: { [number]: boolean } = {}
			for _ = 1, 2000 do
				local roll = HammerRules.rollMystery(random)
				expect(roll.Damage).to.equal(35)
				expect(roll.BonusDamagePercent >= 15 and roll.BonusDamagePercent <= 25).to.equal(
					true
				)
				expect(roll.BonusDamagePercent % 1).to.equal(0)
				expect(roll.CritDamagePercent >= 5 and roll.CritDamagePercent <= 10).to.equal(true)
				expect(roll.CritDamagePercent % 1).to.equal(0)
				seenBonus[roll.BonusDamagePercent] = true
				seenCrit[roll.CritDamagePercent] = true
			end
			for value = mystery.BonusDamageMinPercent, mystery.BonusDamageMaxPercent do
				expect(seenBonus[value]).to.equal(true)
			end
			for value = mystery.CritDamageMinPercent, mystery.CritDamageMaxPercent do
				expect(seenCrit[value]).to.equal(true)
			end
		end)
	end)

	describe("HammerRules.clampRoll", function()
		it("pulls out-of-range saved stats back into range and fixes the base damage", function()
			local roll = HammerRules.clampRoll({
				Damage = 999,
				BonusDamagePercent = 400,
				CritDamagePercent = -5,
			})
			expect(roll.Damage).to.equal(mystery.BaseDamage)
			expect(roll.BonusDamagePercent).to.equal(mystery.BonusDamageMaxPercent)
			expect(roll.CritDamagePercent).to.equal(mystery.CritDamageMinPercent)
		end)

		it("keeps a valid roll exactly as it was (no reroll)", function()
			local roll = HammerRules.clampRoll({
				Damage = 35,
				BonusDamagePercent = 20,
				CritDamagePercent = 7,
			})
			expect(roll.Damage).to.equal(35)
			expect(roll.BonusDamagePercent).to.equal(20)
			expect(roll.CritDamagePercent).to.equal(7)
		end)

		it("upgrades a hammer saved before the damage bonus existed", function()
			local roll = HammerRules.clampRoll({ Damage = 22, CritDamagePercent = 9 })
			expect(roll.Damage).to.equal(mystery.BaseDamage)
			expect(roll.BonusDamagePercent).to.equal(mystery.LegacyBonusDamagePercent)
			-- Its crit roll is kept.
			expect(roll.CritDamagePercent).to.equal(9)
		end)
	end)

	describe("HammerRules.resolve", function()
		it("resolves regular hammers with no crit bonus", function()
			local hammer = HammerConfig.ById[GameConfig.DefaultHammerId]
			local stats = HammerRules.resolve(hammer.Id, {})
			expect(stats).never.to.equal(nil)
			expect((stats :: HammerRules.HammerStats).Damage).to.equal(hammer.Damage)
			expect((stats :: HammerRules.HammerStats).DamageBonus).to.equal(0)
			expect((stats :: HammerRules.HammerStats).CritDamage).to.equal(0)
		end)

		it("resolves an owned Mystery Hammer from its saved roll", function()
			local id = HammerRules.mysteryId(1)
			local stats = HammerRules.resolve(
				id,
				{ [id] = { Damage = 35, BonusDamagePercent = 20, CritDamagePercent = 8 } }
			)
			expect(stats).never.to.equal(nil)
			expect((stats :: HammerRules.HammerStats).Damage).to.equal(35)
			expect((stats :: HammerRules.HammerStats).DamageBonus).to.equal(0.2)
			expect((stats :: HammerRules.HammerStats).CritDamage).to.equal(0.08)
		end)

		it("hits for 35 x (1 + bonus), and the crit bonus only on crits", function()
			local id = HammerRules.mysteryId(1)
			local hammer = HammerRules.resolve(
				id,
				{ [id] = { Damage = 35, BonusDamagePercent = 20, CritDamagePercent = 10 } }
			) :: HammerRules.HammerStats
			local stats = CombatRules.baseStats(hammer.Damage)
			stats.DamageBonus += hammer.DamageBonus
			stats.CritDamage += hammer.CritDamage
			local boss = BossConfig.ById.deadline_boss -- takes damage x1
			local normal, normalCrit = CombatRules.hitDamage(stats, boss, 0.99)
			expect(normalCrit).to.equal(false)
			expect(normal).to.equal(42) -- 35 x 1.2
			local crit, isCrit = CombatRules.hitDamage(stats, boss, 0)
			expect(isCrit).to.equal(true)
			-- 42 x (1 + base crit + 10 %)
			expect(crit).to.equal(math.floor(42 * (1 + GameConfig.BaseCritDamage + 0.1) + 0.5))
		end)

		it("returns nil for unknown or unowned hammers", function()
			expect(HammerRules.resolve("fake_hammer", {})).to.equal(nil)
			expect(HammerRules.resolve(HammerRules.mysteryId(9), {})).to.equal(nil)
		end)
	end)
end
