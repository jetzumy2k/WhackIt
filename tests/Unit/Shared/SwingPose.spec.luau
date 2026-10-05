--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SwingPose = require(ReplicatedStorage.Shared.SwingPose)

local function samePose(a: SwingPose.Pose, b: SwingPose.Pose): boolean
	local epsilon = 1e-6
	return math.abs(a.Shoulder - b.Shoulder) < epsilon
		and math.abs(a.Elbow - b.Elbow) < epsilon
		and math.abs(a.WaistPitch - b.WaistPitch) < epsilon
		and math.abs(a.WaistYaw - b.WaistYaw) < epsilon
end

return function()
	describe("SwingPose.at", function()
		it("starts and ends in the holding pose", function()
			expect(samePose(SwingPose.at(0), SwingPose.HOLD)).to.equal(true)
			expect(samePose(SwingPose.at(1), SwingPose.HOLD)).to.equal(true)
		end)

		it("clamps progress outside 0..1", function()
			expect(samePose(SwingPose.at(-1), SwingPose.HOLD)).to.equal(true)
			expect(samePose(SwingPose.at(2), SwingPose.HOLD)).to.equal(true)
		end)

		it("winds up over the head before the impact", function()
			local highest, highestAt = -math.huge, 0
			for step = 0, 100 do
				local progress = step / 100
				local shoulder = SwingPose.at(progress).Shoulder
				if shoulder > highest then
					highest, highestAt = shoulder, progress
				end
			end
			expect(highest > 180).to.equal(true) -- past straight up
			expect(highestAt < SwingPose.IMPACT).to.equal(true)
		end)

		it("strikes forward-and-down at the impact moment", function()
			local impact = SwingPose.at(SwingPose.IMPACT)
			expect(impact.Shoulder < SwingPose.HOLD.Shoulder).to.equal(true)
			expect(impact.WaistPitch < 0).to.equal(true) -- leaning into the blow
		end)

		it("moves smoothly, without jumps between frames", function()
			-- 1/200 of a 0.45 s swing is ~2 ms; no joint should move more than 10 degrees in that time.
			local previous = SwingPose.at(0)
			for step = 1, 200 do
				local current = SwingPose.at(step / 200)
				expect(math.abs(current.Shoulder - previous.Shoulder) < 10).to.equal(true)
				expect(math.abs(current.Elbow - previous.Elbow) < 10).to.equal(true)
				expect(math.abs(current.WaistPitch - previous.WaistPitch) < 10).to.equal(true)
				expect(math.abs(current.WaistYaw - previous.WaistYaw) < 10).to.equal(true)
				previous = current
			end
		end)
	end)

	describe("SwingPose.blend", function()
		it("fades in from and out to the normal animation", function()
			expect(SwingPose.blend(0)).to.equal(0)
			expect(SwingPose.blend(1)).to.equal(0)
		end)

		it("fully drives the pose through wind-up and impact", function()
			expect(SwingPose.blend(0.4)).to.equal(1)
			expect(SwingPose.blend(SwingPose.IMPACT)).to.equal(1)
		end)
	end)
end
