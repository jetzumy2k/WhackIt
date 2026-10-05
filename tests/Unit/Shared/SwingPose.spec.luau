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
	describe("SwingPose effects", function()
		it("keeps the hammer head its normal size at rest", function()
			for _, progress in { 0, 0.2, 0.7, 1 } do
				local scale = SwingPose.headScale(progress)
				expect(scale.Length).to.equal(1)
				expect(scale.Width).to.equal(1)
			end
		end)

		it("stretches the head on the downswing and squashes it just after impact", function()
			local downswing = SwingPose.headScale(SwingPose.IMPACT - 0.01)
			expect(downswing.Length > 1).to.equal(true)
			expect(downswing.Width < 1).to.equal(true)
			local squash = SwingPose.headScale(SwingPose.IMPACT + 0.03)
			expect(squash.Length < 1).to.equal(true)
			expect(squash.Width > 1).to.equal(true)
		end)

		it("changes the head size smoothly", function()
			local previous = SwingPose.headScale(0)
			for step = 1, 400 do
				local current = SwingPose.headScale(step / 400)
				expect(math.abs(current.Length - previous.Length) < 0.1).to.equal(true)
				expect(math.abs(current.Width - previous.Width) < 0.1).to.equal(true)
				previous = current
			end
		end)

		it("draws the trail only through the fast part of the swing, including impact", function()
			expect(SwingPose.trailActive(0)).to.equal(false)
			expect(SwingPose.trailActive(SwingPose.IMPACT)).to.equal(true)
			expect(SwingPose.trailActive(1)).to.equal(false)
		end)

		it("pauses briefly at the top (anticipation) before the strike", function()
			-- Between wind-up and the start of the strike the arm barely moves...
			local topMove = math.abs(SwingPose.at(0.34).Shoulder - SwingPose.at(0.3).Shoulder)
			-- ...compared with the strike itself.
			local strikeMove = math.abs(
				SwingPose.at(SwingPose.IMPACT).Shoulder
					- SwingPose.at(SwingPose.IMPACT - 0.04).Shoulder
			)
			expect(topMove < strikeMove).to.equal(true)
		end)
	end)
end
