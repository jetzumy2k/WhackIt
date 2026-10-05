--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SwingPose = require(ReplicatedStorage.Shared.SwingPose)

local function samePose(a: SwingPose.Pose, b: SwingPose.Pose): boolean
	local epsilon = 1e-6
	return math.abs(a.Shoulder - b.Shoulder) < epsilon
		and math.abs(a.Elbow - b.Elbow) < epsilon
		and math.abs(a.Grip - b.Grip) < epsilon
		and math.abs(a.WaistPitch - b.WaistPitch) < epsilon
		and math.abs(a.WaistYaw - b.WaistYaw) < epsilon
end

return function()
	describe("SwingPose.at", function()
		it("starts and ends resting on the shoulder", function()
			expect(samePose(SwingPose.at(0), SwingPose.REST)).to.equal(true)
			expect(samePose(SwingPose.at(1), SwingPose.REST)).to.equal(true)
		end)

		it("clamps progress outside 0..1", function()
			expect(samePose(SwingPose.at(-1), SwingPose.REST)).to.equal(true)
			expect(samePose(SwingPose.at(2), SwingPose.REST)).to.equal(true)
		end)

		it("rests the hammer back over the shoulder", function()
			local angle = SwingPose.hammerAngle(SwingPose.REST)
			-- Past straight up (180) but not hanging down the back (270).
			expect(angle > 180).to.equal(true)
			expect(angle < 260).to.equal(true)
		end)

		it("has the hammer out in front at the impact moment", function()
			local angle = SwingPose.hammerAngle(SwingPose.at(SwingPose.IMPACT))
			-- Within 30 degrees of straight ahead (90).
			expect(math.abs(angle - 90) <= 30).to.equal(true)
		end)

		it("only has the hammer out in front around the impact", function()
			for step = 0, 20 do
				local progress = step / 20
				local outInFront = SwingPose.hammerAngle(SwingPose.at(progress)) < 135
				if progress < 0.35 or progress > 0.9 then
					expect(outInFront).to.equal(false)
				end
			end
		end)

		it("raises the arm before striking", function()
			local highest, highestAt = -math.huge, 0
			for step = 0, 100 do
				local progress = step / 100
				local shoulder = SwingPose.at(progress).Shoulder
				if shoulder > highest then
					highest, highestAt = shoulder, progress
				end
			end
			expect(highest > SwingPose.REST.Shoulder).to.equal(true)
			expect(highestAt < SwingPose.IMPACT).to.equal(true)
		end)

		it("moves smoothly, without jumps between frames", function()
			-- 1/200 of a 0.45 s swing is ~2 ms; no joint should move more than 10 degrees in that time.
			local previous = SwingPose.at(0)
			for step = 1, 200 do
				local current = SwingPose.at(step / 200)
				expect(math.abs(current.Shoulder - previous.Shoulder) < 10).to.equal(true)
				expect(math.abs(current.Elbow - previous.Elbow) < 10).to.equal(true)
				expect(math.abs(current.Grip - previous.Grip) < 10).to.equal(true)
				expect(math.abs(current.WaistPitch - previous.WaistPitch) < 10).to.equal(true)
				expect(math.abs(current.WaistYaw - previous.WaistYaw) < 10).to.equal(true)
				previous = current
			end
		end)
	end)
end
