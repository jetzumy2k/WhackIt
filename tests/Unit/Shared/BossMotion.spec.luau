--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossMotion = require(ReplicatedStorage.Shared.BossMotion)
local BossPersonalityConfig = require(ReplicatedStorage.Config.BossPersonalityConfig)

local FIDGETS = { "Hurry", "Glance", "Jitter", "Tilt", "Yawn", "Puff" }

return function()
	-- Inside the spec: TestEZ only provides `expect` here.
	-- Small enough that the drawn monster always stays on its hitbox.
	local function expectSmall(offsets: BossMotion.Offsets): ()
		expect(math.abs(offsets.Lift) <= 1).to.equal(true)
		expect(math.abs(offsets.Shuffle) <= BossPersonalityConfig.MaxShuffleStuds).to.equal(true)
		expect(math.abs(offsets.Yaw) <= math.rad(35)).to.equal(true)
		expect(math.abs(offsets.Lean) <= math.rad(15)).to.equal(true)
		expect(math.abs(offsets.Roll) <= math.rad(15)).to.equal(true)
		expect(offsets.Scale >= 0.95 and offsets.Scale <= 1.1).to.equal(true)
	end

	describe("BossMotion", function()
		it("keeps idle motion small for every personality", function()
			for _, personality in BossPersonalityConfig.Types do
				for step = 0, 200 do
					expectSmall(BossMotion.idle(personality, step * 0.05, 1.3))
				end
			end
		end)

		it("keeps every fidget small and back to rest at its end", function()
			for _, kind in FIDGETS do
				for step = 0, 50 do
					expectSmall(BossMotion.fidget(kind, step / 50))
				end
				local rest = BossMotion.fidget(kind, 1)
				expect(math.abs(rest.Lift) < 1e-6).to.equal(true)
				expect(math.abs(rest.Yaw) < 1e-6).to.equal(true)
				expect(math.abs(rest.Scale - 1) < 1e-6).to.equal(true)
			end
		end)

		it("hops up when surprised and settles back", function()
			expect(BossMotion.surprise(0.5).Lift > 0.5).to.equal(true)
			expect(math.abs(BossMotion.surprise(0).Lift) < 1e-6).to.equal(true)
			expect(math.abs(BossMotion.surprise(1).Lift) < 1e-6).to.equal(true)
			for step = 0, 20 do
				expectSmall(BossMotion.surprise(step / 20))
			end
		end)

		it("wobbles a little after a hit and stops", function()
			for step = 0, 40 do
				expect(math.abs(BossMotion.wobble(step / 40)) <= math.rad(15)).to.equal(true)
			end
			expect(math.abs(BossMotion.wobble(1)) < 1e-6).to.equal(true)
		end)

		it("looks around its home direction within its personality's range", function()
			for _, personality in BossPersonalityConfig.Types do
				for step = 0, 100 do
					local yaw = BossMotion.lookAround(personality, math.pi, step * 0.1, 0)
					expect(math.abs(yaw - math.pi) <= math.rad(personality.LookDegrees) + 1e-6).to.equal(
						true
					)
				end
			end
		end)
	end)
	describe("BossMotion.pace", function()
		it("strolls within the pace distance, smoothly, pausing at the ends", function()
			local studs = BossMotion.PACE_STUDS
			local last = BossMotion.pace(0, 0, studs)
			local paused = false
			for step = 1, 1200 do
				local now = step * 0.01
				local offset, walking, direction = BossMotion.pace(now, 0, studs)
				expect(math.abs(offset) <= studs + 1e-6).to.equal(true)
				expect(math.abs(offset - last) < 0.1).to.equal(true) -- no jumps
				expect(walking >= 0 and walking <= 1).to.equal(true)
				if direction == 0 then
					paused = true
					expect(walking).to.equal(0)
				end
				last = offset
			end
			expect(paused).to.equal(true)
		end)

		it("starts and ends the cycle at home", function()
			expect(math.abs((BossMotion.pace(0, 0, 3)))).to.be.near(0, 1e-6)
			expect(math.abs((BossMotion.pace(BossMotion.PACE_CYCLE - 1e-4, 0, 3)))).to.be.near(
				0,
				1e-3
			)
		end)

		it("keeps the walking bob and waddle small", function()
			for step = 0, 100 do
				local lift, roll = BossMotion.walkCycle(step * 0.1, 1)
				expect(lift >= 0 and lift <= 0.3).to.equal(true)
				expect(math.abs(roll) <= math.rad(8)).to.equal(true)
			end
			local lift, roll = BossMotion.walkCycle(1.3, 0)
			expect(lift).to.equal(0)
			expect(roll).to.equal(0)
		end)
	end)
end
