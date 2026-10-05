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
end
