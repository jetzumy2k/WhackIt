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
		end)

		it("starts stress within its bounds", function()
			expect(Checks.isPositiveFinite(GameConfig.MaxStress)).to.equal(true)
			expect(GameConfig.StartingStress >= 0).to.equal(true)
			expect(GameConfig.StartingStress <= GameConfig.MaxStress).to.equal(true)
		end)

		it("is read-only", function()
			expect(table.isfrozen(GameConfig)).to.equal(true)
		end)
	end)
end
