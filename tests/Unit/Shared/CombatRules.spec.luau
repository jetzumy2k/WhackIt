--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local CombatRules = require(ReplicatedStorage.Shared.CombatRules)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)

local function hammerWith(damage: number): HammerConfig.HammerDefinition
	return { Id = "test_hammer", DisplayName = "Test", Description = "Test", Damage = damage }
end

local function bossWith(multiplier: number): BossConfig.BossDefinition
	return {
		Id = "test_boss",
		DisplayName = "Test",
		Description = "Test",
		MaxHealth = 100,
		DamageTakenMultiplier = multiplier,
		ScoreReward = 1,
	}
end

return function()
	describe("CombatRules.computeHitDamage", function()
		it("multiplies hammer damage by the boss multiplier", function()
			expect(CombatRules.computeHitDamage(hammerWith(10), bossWith(2))).to.equal(20)
		end)

		it("returns whole numbers despite floating-point error", function()
			-- 10 * 1.2 is 12.000000000000002 in floating point.
			expect(CombatRules.computeHitDamage(hammerWith(10), bossWith(1.2))).to.equal(12)
		end)

		it("rounds halves up", function()
			expect(CombatRules.computeHitDamage(hammerWith(5), bossWith(0.5))).to.equal(3)
		end)

		it("never goes below MinHitDamage", function()
			expect(CombatRules.computeHitDamage(hammerWith(1), bossWith(0.01))).to.equal(
				GameConfig.MinHitDamage
			)
		end)

		it("keeps pre-hammer balance: same hits-to-defeat with the default hammer", function()
			-- Before hammer-driven damage, bosses took fixed HitDamage per hit. This guards
			-- the migration only; update or delete it when bosses are deliberately rebalanced.
			local legacyHitDamage: { [string]: number } = {
				deadline_boss = 10,
				meeting_master = 8,
				reply_all_boss = 12,
				production_bug = 15,
				monday_monster = 20,
			}
			local hammer = HammerConfig.ById[GameConfig.DefaultHammerId]
			for id, damage in legacyHitDamage do
				expect(CombatRules.computeHitDamage(hammer, BossConfig.ById[id])).to.equal(damage)
			end
		end)
	end)

	describe("CombatRules.isOffCooldown", function()
		local cooldown = GameConfig.HitCooldown

		it("allows the first hit", function()
			expect(CombatRules.isOffCooldown(10, nil, 0)).to.equal(true)
		end)

		it("blocks hits inside the cooldown and allows them after", function()
			expect(CombatRules.isOffCooldown(cooldown / 2, 0, 0)).to.equal(false)
			expect(CombatRules.isOffCooldown(cooldown, 0, 0)).to.equal(true)
		end)

		it("forgives exactly the grace period and no more", function()
			local grace = GameConfig.HitCooldownGrace
			expect(CombatRules.isOffCooldown(cooldown - grace, 0, grace)).to.equal(true)
			expect(CombatRules.isOffCooldown(cooldown - grace * 2, 0, grace)).to.equal(false)
		end)
	end)

	describe("CombatRules.isInReach", function()
		it("accepts positions within HitReach, inclusive", function()
			local origin = Vector3.new(0, 0, 0)
			expect(CombatRules.isInReach(origin, Vector3.new(GameConfig.HitReach, 0, 0))).to.equal(
				true
			)
			expect(CombatRules.isInReach(origin, origin)).to.equal(true)
		end)

		it("rejects positions beyond HitReach", function()
			local beyond = Vector3.new(GameConfig.HitReach + 0.1, 0, 0)
			expect(CombatRules.isInReach(Vector3.new(0, 0, 0), beyond)).to.equal(false)
		end)
	end)
end
