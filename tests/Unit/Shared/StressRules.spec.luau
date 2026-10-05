--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local StressRules = require(ReplicatedStorage.Shared.StressRules)

return function()
	describe("StressRules.reliefForHit", function()
		it("scales with damage", function()
			expect(StressRules.reliefForHit(10)).to.equal(10 * GameConfig.StressReliefPerDamage)
			expect(StressRules.reliefForHit(20) > StressRules.reliefForHit(10)).to.equal(true)
		end)

		it("never returns negative relief", function()
			expect(StressRules.reliefForHit(-5)).to.equal(0)
		end)
	end)

	describe("StressRules.applyRelief", function()
		it("subtracts relief from stress", function()
			expect(StressRules.applyRelief(50, 5)).to.equal(45)
		end)

		it("never drops below zero", function()
			expect(StressRules.applyRelief(3, 10)).to.equal(0)
		end)

		it("never exceeds MaxStress", function()
			expect(StressRules.applyRelief(GameConfig.MaxStress, -10)).to.equal(
				GameConfig.MaxStress
			)
		end)

		it("does not accumulate floating-point drift", function()
			local stress = 100
			for _ = 1, 50 do
				stress = StressRules.applyRelief(stress, 1.2000000000000002)
			end
			expect(stress).to.equal(40)
		end)
	end)

	describe("Stress config", function()
		it("uses positive per-damage relief and a non-negative defeat bonus", function()
			expect(GameConfig.StressReliefPerDamage > 0).to.equal(true)
			expect(GameConfig.DefeatStressRelief >= 0).to.equal(true)
		end)
	end)
	describe("StressRules.moodFor", function()
		it("is Zen only at zero", function()
			expect(StressRules.moodFor(0)).to.equal("Zen")
			expect(StressRules.moodFor(0.01)).to.equal("Relaxed")
		end)

		it("moves through the bands at the configured thresholds", function()
			expect(StressRules.moodFor(GameConfig.MoodRelaxedMax)).to.equal("Relaxed")
			expect(StressRules.moodFor(GameConfig.MoodRelaxedMax + 1)).to.equal("Neutral")
			expect(StressRules.moodFor(GameConfig.MoodNeutralMax)).to.equal("Neutral")
			expect(StressRules.moodFor(GameConfig.MoodNeutralMax + 1)).to.equal("Stressed")
			expect(StressRules.moodFor(GameConfig.MoodStressedMax)).to.equal("Stressed")
			expect(StressRules.moodFor(GameConfig.MoodStressedMax + 1)).to.equal("Frazzled")
			expect(StressRules.moodFor(GameConfig.MaxStress)).to.equal("Frazzled")
		end)
	end)

	describe("StressRules idle regen", function()
		it("waits the full idle delay before stress rises", function()
			local delay = GameConfig.StressIdleDelay
			expect(StressRules.shouldRegen(delay - 1, math.huge)).to.equal(false)
			expect(StressRules.shouldRegen(delay, math.huge)).to.equal(true)
		end)

		it("then rises once per interval", function()
			local idle = GameConfig.StressIdleDelay + 60
			expect(StressRules.shouldRegen(idle, GameConfig.StressRegenInterval - 1)).to.equal(
				false
			)
			expect(StressRules.shouldRegen(idle, GameConfig.StressRegenInterval)).to.equal(true)
		end)

		it("adds one step and never exceeds MaxStress", function()
			expect(StressRules.applyRegen(10)).to.equal(10 + GameConfig.StressRegenStep)
			expect(StressRules.applyRegen(GameConfig.MaxStress - 1)).to.equal(GameConfig.MaxStress)
		end)
	end)

	describe("StressRules Zen", function()
		it("is a Zen moment when an armed player reaches zero", function()
			expect(StressRules.isZenMoment(3, 0, true)).to.equal(true)
		end)

		it("is not a Zen moment when not armed, or already at zero", function()
			expect(StressRules.isZenMoment(3, 0, false)).to.equal(false)
			expect(StressRules.isZenMoment(0, 0, true)).to.equal(false)
			expect(StressRules.isZenMoment(10, 2, true)).to.equal(false)
		end)

		it("re-arms only once stress climbs back to the threshold", function()
			expect(StressRules.shouldRearm(GameConfig.ZenRearmStress - 1)).to.equal(false)
			expect(StressRules.shouldRearm(GameConfig.ZenRearmStress)).to.equal(true)
		end)
	end)
end
