--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local StressRules = require(ReplicatedStorage.Shared.StressRules)

return function()
	describe("StressRules.reliefForHit", function()
		it("grows a little with the hammer's own damage", function()
			expect(StressRules.reliefForHit(10)).to.equal(10 * GameConfig.StressReliefPerDamage)
			expect(StressRules.reliefForHit(20) > StressRules.reliefForHit(10)).to.equal(true)
		end)

		it(
			"is capped per hit, so huge damage (crits, level, boosts) can't drain stress fast",
			function()
				expect(StressRules.reliefForHit(35)).to.equal(GameConfig.StressReliefMaxPerHit)
				expect(StressRules.reliefForHit(5000)).to.equal(GameConfig.StressReliefMaxPerHit)
				-- From full to Zen takes at least 40 hits.
				expect(GameConfig.MaxStress / GameConfig.StressReliefMaxPerHit >= 40).to.equal(true)
			end
		)

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
		it("waits the grace period, then one interval, before the first rise", function()
			local grace, interval = GameConfig.StressIdleDelay, GameConfig.StressRegenInterval
			expect(grace).to.equal(15)
			expect(interval).to.equal(5)
			-- Hit at 0 s -> first rise at 20 s; hit at 23 s -> first rise at 43 s.
			expect(StressRules.firstRiseAt(0)).to.equal(20)
			expect(StressRules.firstRiseAt(23)).to.equal(43)
		end)

		it("then rises every interval, without bursts after a hitch", function()
			local interval = GameConfig.StressRegenInterval
			expect(StressRules.nextRiseAfter(20, 20)).to.equal(20 + interval)
			expect(StressRules.nextRiseAfter(20, 20.2)).to.equal(20 + interval)
			-- The server fell 30 s behind: one rise now, the next one interval later.
			expect(StressRules.nextRiseAfter(20, 50)).to.equal(50 + interval)
		end)

		it("follows the example timeline: 20, 25, 30 s, then a hit at 33 s restarts it", function()
			local rises: { number } = {}
			local riseAt = StressRules.firstRiseAt(0)
			for tick = 0, 33 * 4 do
				local now = tick / 4
				if now >= riseAt then
					table.insert(rises, now)
					riseAt = StressRules.nextRiseAfter(riseAt, now)
				end
			end
			expect(#rises).to.equal(3)
			expect(rises[1]).to.equal(20)
			expect(rises[2]).to.equal(25)
			expect(rises[3]).to.equal(30)
			-- A hit at 33 s: nothing until 53 s.
			expect(StressRules.firstRiseAt(33)).to.equal(53)
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

	describe("StressRules Zen bonus labels", function()
		local max = GameConfig.ZenCoinBonusMaxLevel

		it("shows the coin bonus, capped like the reward", function()
			expect(StressRules.zenBonusPercent(0)).to.equal(0)
			expect(StressRules.zenBonusPercent(3)).to.equal(
				math.floor(3 * GameConfig.ZenCoinBonusPerLevel * 100 + 0.5)
			)
			expect(StressRules.zenBonusPercent(max + 7)).to.equal(StressRules.zenBonusPercent(max))
			expect(StressRules.zenBonusPercent(-2)).to.equal(0)
		end)

		it("marks the cap and never says level", function()
			expect(StressRules.zenBonusText(0)).to.equal("Zen +0%")
			expect(StressRules.zenBonusText(3)).to.equal("Zen +15%")
			expect(StressRules.zenBonusText(max)).to.equal(
				string.format("Zen +%d%% (max)", StressRules.zenBonusPercent(max))
			)
			expect((string.find(string.lower(StressRules.zenBonusText(max + 1)), "lv"))).to.equal(
				nil
			)
		end)
	end)
end
