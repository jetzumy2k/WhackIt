--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossFace = require(ReplicatedStorage.Shared.BossFace)

local function state(overrides: { [string]: any }): BossFace.State
	local base: BossFace.State =
		{ Defeated = false, HitProgress = nil, DizzyProgress = nil, Surprised = false }
	for key, value in overrides do
		(base :: any)[key] = value
	end
	return base
end

return function()
	describe("BossFace expressions", function()
		it("smiles at rest and is never angry", function()
			local idle = BossFace.expressionFor(state({}))
			expect(idle.Name).to.equal("Idle")
			expect(idle.Mouth).to.equal("Smile")
			for _, expression in BossFace.Expressions do
				-- Positive tilt = inner ends up (worried); angry would be negative.
				expect(expression.BrowTilt >= 0).to.equal(true)
			end
		end)

		it("picks defeat over a hit, a hit over dizziness, dizziness over surprise", function()
			expect(BossFace.expressionFor(state({ Defeated = true, HitProgress = 0.1 })).Name).to.equal(
				"Defeated"
			)
			expect(BossFace.expressionFor(state({ HitProgress = 0.1, DizzyProgress = 0.05 })).Name).to.equal(
				"Hit"
			)
			expect(BossFace.expressionFor(state({ HitProgress = 0.8, DizzyProgress = 0.3 })).Name).to.equal(
				"Surprised"
			)
			expect(
				BossFace.expressionFor(
					state({ HitProgress = 1.2, DizzyProgress = 0.6, Surprised = true })
				).Name
			).to.equal("Dizzy")
			expect(BossFace.expressionFor(state({ Surprised = true })).Name).to.equal("Surprised")
		end)

		it("squeezes the eyes shut on a hit and closes them happily on defeat", function()
			expect(BossFace.Expressions.Hit.EyesClosed).to.equal(true)
			expect(BossFace.Expressions.Defeated.EyesClosed).to.equal(true)
			expect(BossFace.Expressions.Defeated.Mouth).to.equal("Smile")
		end)
	end)

	describe("BossFace blinking", function()
		it("blinks briefly and now and then, not all the time", function()
			local closed, total = 0, 0
			for step = 0, 2000 do
				total += 1
				if BossFace.blinking(step * 0.01, 1.7) then
					closed += 1
				end
			end
			local share = closed / total
			expect(share > 0 and share < 0.1).to.equal(true)
		end)

		it("gives each boss its own rhythm", function()
			local differs = false
			for step = 0, 600 do
				local t = step * 0.01
				if BossFace.blinking(t, 0.3) ~= BossFace.blinking(t, 2.9) then
					differs = true
				end
			end
			expect(differs).to.equal(true)
		end)
	end)

	describe("BossFace pupils and arms", function()
		it("looks toward a target in front, within the eye", function()
			local right = BossFace.pupilOffset(Vector3.new(5, 0, -5), nil, 0)
			expect(right.X > 0).to.equal(true)
			local far = BossFace.pupilOffset(Vector3.new(100, 100, -1), nil, 0)
			expect(far.Magnitude <= BossFace.PUPIL_RANGE + 1e-6).to.equal(true)
			expect(BossFace.pupilOffset(Vector3.new(0, 0, 5), nil, 0)).to.equal(Vector2.zero) -- behind
			expect(BossFace.pupilOffset(nil, nil, 0)).to.equal(Vector2.zero)
		end)

		it("rolls the pupils while dizzy, staying inside the eye", function()
			local a = BossFace.pupilOffset(nil, 0.5, 0)
			local b = BossFace.pupilOffset(nil, 0.5, 0.1)
			expect(a ~= b).to.equal(true)
			expect(math.abs(a.Magnitude - BossFace.PUPIL_RANGE) < 1e-6).to.equal(true)
		end)

		it("swings the arms gently at rest and raises them when defeated", function()
			for t = 0, 5, 0.25 do
				local idle = BossFace.armAngle(BossFace.Expressions.Idle, t, 0, 1)
				expect(math.abs(idle) <= BossFace.IDLE_ARM_SWING + 1e-6).to.equal(true)
			end
			expect(BossFace.armAngle(BossFace.Expressions.Defeated, 0, 0, 1) > math.rad(45)).to.equal(
				true
			)
		end)
	end)
end
