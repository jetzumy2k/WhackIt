--!strict
--[[
	Keyframed hammer swing as pure math: given progress 0..1 through a swing,
	returns joint angles. Shared so specs can check it; applied to characters by
	the client's SwingAnimator.

	Angles are degrees in joint space (R15):
	  Shoulder   0 = arm hanging, 90 = arm straight forward, 180 = straight up
	  Elbow      positive bends the forearm forward
	  WaistPitch positive leans the upper body back
	  WaistYaw   negative turns the right shoulder back (wind-up)
]]

export type Pose = {
	Shoulder: number,
	Elbow: number,
	WaistPitch: number,
	WaistYaw: number,
}

type Easing = (alpha: number) -> number

type Keyframe = {
	At: number, -- progress 0..1
	Pose: Pose,
	Ease: Easing, -- easing used while moving INTO this keyframe
}

local SwingPose = {}

-- The hammer meets the boss here; the hit request is sent at this moment.
SwingPose.IMPACT = 0.55

local function easeOutQuad(alpha: number): number
	return 1 - (1 - alpha) * (1 - alpha)
end

local function easeInQuad(alpha: number): number
	return alpha * alpha
end

local function easeInOutSine(alpha: number): number
	return -(math.cos(math.pi * alpha) - 1) / 2
end

-- Holding pose: matches the arm-forward pose of Roblox's tool-hold animation.
SwingPose.HOLD = table.freeze({ Shoulder = 90, Elbow = 15, WaistPitch = 0, WaistYaw = 0 }) :: Pose

local KEYFRAMES: { Keyframe } = {
	{ At = 0, Pose = SwingPose.HOLD, Ease = easeOutQuad },
	-- Wind-up: hammer raised up and back over the shoulder, body coiled.
	{
		At = 0.4,
		Pose = { Shoulder = 205, Elbow = 70, WaistPitch = 10, WaistYaw = -20 },
		Ease = easeOutQuad,
	},
	-- Strike: accelerates down into the target in front.
	{
		At = SwingPose.IMPACT,
		Pose = { Shoulder = 70, Elbow = 5, WaistPitch = -15, WaistYaw = 10 },
		Ease = easeInQuad,
	},
	-- Follow-through: a little past the target.
	{
		At = 0.7,
		Pose = { Shoulder = 55, Elbow = 10, WaistPitch = -18, WaistYaw = 12 },
		Ease = easeOutQuad,
	},
	-- Recover back to holding.
	{ At = 1, Pose = SwingPose.HOLD, Ease = easeInOutSine },
}

local function lerp(a: number, b: number, alpha: number): number
	return a + (b - a) * alpha
end

function SwingPose.at(progress: number): Pose
	local t = math.clamp(progress, 0, 1)
	for index = 2, #KEYFRAMES do
		local previous, nextFrame = KEYFRAMES[index - 1], KEYFRAMES[index]
		if t <= nextFrame.At then
			local alpha = nextFrame.Ease((t - previous.At) / (nextFrame.At - previous.At))
			local from, to = previous.Pose, nextFrame.Pose
			return {
				Shoulder = lerp(from.Shoulder, to.Shoulder, alpha),
				Elbow = lerp(from.Elbow, to.Elbow, alpha),
				WaistPitch = lerp(from.WaistPitch, to.WaistPitch, alpha),
				WaistYaw = lerp(from.WaistYaw, to.WaistYaw, alpha),
			}
		end
	end
	return SwingPose.HOLD
end

-- How strongly the swing overrides the normal animation: eases in at the start
-- and out at the end so the arm never snaps between poses.
function SwingPose.blend(progress: number): number
	local blendIn = math.clamp(progress / 0.1, 0, 1)
	local blendOut = math.clamp((1 - progress) / 0.15, 0, 1)
	return easeInOutSine(math.min(blendIn, blendOut))
end

return SwingPose
