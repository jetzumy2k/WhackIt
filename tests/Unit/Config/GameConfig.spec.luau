--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)
local Checks = require(ServerScriptService.Tests.Helpers.Checks)

return function()
	describe("GameConfig", function()
		it("points DefaultHammerId at an existing hammer", function()
			expect(HammerConfig.ById[GameConfig.DefaultHammerId]).never.to.equal(nil)
		end)

		it("uses positive, finite combat timings and damage floor", function()
			expect(Checks.isPositiveFinite(GameConfig.HitCooldown)).to.equal(true)
			expect(Checks.isPositiveFinite(GameConfig.MinHitDamage)).to.equal(true)
			expect(Checks.isPositiveFinite(GameConfig.HitReach)).to.equal(true)
		end)

		it("keeps the jitter grace smaller than the cooldown itself", function()
			expect(GameConfig.HitCooldownGrace >= 0).to.equal(true)
			expect(GameConfig.HitCooldownGrace < GameConfig.HitCooldown).to.equal(true)
		end)

		it("keeps the reach lag grace small next to the reach itself", function()
			expect(GameConfig.HitReachGrace >= 0).to.equal(true)
			expect(GameConfig.HitReachGrace <= GameConfig.HitReach / 4).to.equal(true)
		end)

		it("uses a reward share between 0 and 1 and a positive respawn delay", function()
			expect(GameConfig.MinRewardDamageShare > 0).to.equal(true)
			expect(GameConfig.MinRewardDamageShare <= 1).to.equal(true)
			expect(Checks.isPositiveFinite(GameConfig.BossRespawnDelay)).to.equal(true)
		end)

		it("starts stress within its bounds", function()
			expect(Checks.isPositiveFinite(GameConfig.MaxStress)).to.equal(true)
			expect(GameConfig.StartingStress >= 0).to.equal(true)
			expect(GameConfig.StartingStress <= GameConfig.MaxStress).to.equal(true)
		end)

		it("uses positive idle-regen timings and step", function()
			expect(Checks.isPositiveFinite(GameConfig.StressIdleDelay)).to.equal(true)
			expect(Checks.isPositiveFinite(GameConfig.StressRegenInterval)).to.equal(true)
			expect(Checks.isPositiveFinite(GameConfig.StressRegenStep)).to.equal(true)
		end)

		it("orders the mood bands inside the stress range", function()
			expect(GameConfig.MoodRelaxedMax > 0).to.equal(true)
			expect(GameConfig.MoodRelaxedMax < GameConfig.MoodNeutralMax).to.equal(true)
			expect(GameConfig.MoodNeutralMax < GameConfig.MoodStressedMax).to.equal(true)
			expect(GameConfig.MoodStressedMax < GameConfig.MaxStress).to.equal(true)
		end)

		it("re-arms Zen somewhere inside the stress range", function()
			expect(GameConfig.ZenRearmStress > 0).to.equal(true)
			expect(GameConfig.ZenRearmStress <= GameConfig.MaxStress).to.equal(true)
			expect(Checks.isPositiveFinite(GameConfig.ZenBonusCoins)).to.equal(true)
		end)

		it("keeps the last-hit bonus a small extra", function()
			expect(GameConfig.LastHitBonusShare > 0).to.equal(true)
			expect(GameConfig.LastHitBonusShare <= 0.25).to.equal(true)
		end)

		it("sprints faster than walking but under the server's movement limit", function()
			local MovementLimits = require(ServerScriptService.Config.MovementLimits)
			expect(Checks.isPositiveFinite(GameConfig.WalkSpeed)).to.equal(true)
			expect(GameConfig.SprintSpeed > GameConfig.WalkSpeed).to.equal(true)
			-- Leave headroom for lag bursts so sprinting never trips the movement guard.
			expect(GameConfig.SprintSpeed * 1.5 <= MovementLimits.MaxHorizontalSpeed).to.equal(true)
		end)

		it("is read-only", function()
			expect(table.isfrozen(GameConfig)).to.equal(true)
		end)
	end)
	describe("GameConfig XP", function()
		it("gives at least 15% more XP than Score", function()
			expect(GameConfig.XpRewardMultiplier >= 1.15).to.equal(true)
		end)
	end)
end
