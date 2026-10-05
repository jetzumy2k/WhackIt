--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local MovementLimits = require(ServerScriptService.Config.MovementLimits)
local MovementRules = require(ServerScriptService.Lib.MovementRules)

local ORIGIN = Vector3.new(0, 0, 0)
local MAX = MovementLimits.MaxHorizontalSpeed

return function()
	describe("MovementRules", function()
		it("accepts normal walking (16 studs/s)", function()
			expect(MovementRules.isTooFast(ORIGIN, Vector3.new(8, 0, 0), 0.5, MAX)).to.equal(false)
		end)

		it("flags a teleport across the map", function()
			-- Lobby to an office in one half-second sample.
			expect(MovementRules.isTooFast(ORIGIN, Vector3.new(60, 0, -50), 0.5, MAX)).to.equal(
				true
			)
		end)

		it("ignores vertical movement such as falling", function()
			expect(MovementRules.isTooFast(ORIGIN, Vector3.new(0, -80, 0), 0.5, MAX)).to.equal(
				false
			)
		end)

		it("measures horizontal speed only", function()
			expect(MovementRules.horizontalSpeed(ORIGIN, Vector3.new(3, 99, 4), 1)).to.equal(5)
		end)

		it("treats a zero time step as not moving", function()
			expect(MovementRules.horizontalSpeed(ORIGIN, Vector3.new(100, 0, 0), 0)).to.equal(0)
		end)

		it("keeps a flagged player suspect only for SuspectSeconds", function()
			local seconds = MovementLimits.SuspectSeconds
			expect(MovementRules.isSuspect(nil, 100, seconds)).to.equal(false)
			expect(MovementRules.isSuspect(100, 100 + seconds - 0.1, seconds)).to.equal(true)
			expect(MovementRules.isSuspect(100, 100 + seconds, seconds)).to.equal(false)
		end)

		it("allows sprint-like speeds well above walking", function()
			-- Room for jumps, slopes and network catch-up bursts.
			expect(MAX >= 16 * 2.5).to.equal(true)
		end)
	end)
end
