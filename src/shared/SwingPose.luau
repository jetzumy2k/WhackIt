--!strict
--[[
	Hammer carry and swing as pure math: given progress 0..1 through a swing,
	returns joint angles. Shared so specs can check it; applied to characters by
	the client's SwingAnimator.

	Angles are degrees in the body's front-to-back plane:
	  Shoulder   0 = arm hanging, 90 = arm straight forward, 180 = straight up
	  Elbow      bends the forearm further forward/up
	  Grip       tilts the hammer in the fist (wrist); 0 = handle continues the forearm
	  WaistPitch positive leans the upper body back
	  WaistYaw   negative turns the right shoulder back (wind-up)

	Where the hammer points = Shoulder + Elbow + Grip (see hammerAngle):
	~90 is straight out in front, ~180 straight up, >180 tipped back over the shoulder.

	The swing starts and ends at REST (hammer carried on the shoulder); the
	hammer is out in front only around IMPACT. Beats, as fractions of one
	swing (GameConfig.HitCooldown, 0.45 s):
	  0    -> 0.24  wind-up        arm lifts, hammer cocked back
	  0.24 -> 0.34  anticipation   a slow extra coil at the top
	  0.34 -> 0.5   strike         fast snap forward to IMPACT
	  0.5  -> 0.66  impact         small bounce off the boss, then settle
	  0.66 -> 1     return         smooth swing back onto the shoulder
]]

export type Pose = {
	Shoulder: number,
	Elbow: number,
	Grip: number,
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
SwingPose.IMPACT = 0.5
-- Top of the small bounce off the boss just after impact.
SwingPose.BOUNCE = 0.56

local function easeOutQuad(alpha: number): number
	return 1 - (1 - alpha) * (1 - alpha)
end

local function easeInQuad(alpha: number): number
	return alpha * alpha
end

local function easeInOutSine(alpha: number): number
	return -(math.cos(math.pi * alpha) - 1) / 2
end

-- What Roblox's tool-hold animation already does (arm forward). Offsets are
-- applied relative to it, because that animation keeps playing underneath.
SwingPose.ANIMATOR_HOLD = table.freeze({
	Shoulder = 90,
	Elbow = 15,
	Grip = 0,
	WaistPitch = 0,
	WaistYaw = 0,
}) :: Pose

-- Carried on the shoulder: fist up near the shoulder, hammer tipped back over it.
SwingPose.REST = table.freeze({
	Shoulder = 40,
	Elbow = 110,
	Grip = 70,
	WaistPitch = 0,
	WaistYaw = 0,
}) :: Pose

local KEYFRAMES: { Keyframe } = {
	{ At = 0, Pose = SwingPose.REST, Ease = easeOutQuad },
	-- Wind-up: arm lifted high, hammer still cocked back over the head.
	{
		At = 0.24,
		Pose = { Shoulder = 165, Elbow = 45, Grip = 12, WaistPitch = 6, WaistYaw = -12 },
		Ease = easeOutQuad,
	},
	-- Anticipation: a slow extra coil at the top before the strike.
	{
		At = 0.34,
		Pose = { Shoulder = 178, Elbow = 38, Grip = 8, WaistPitch = 10, WaistYaw = -18 },
		Ease = easeInOutSine,
	},
	-- Strike: arm and wrist snap forward; the hammer is out in front at the boss.
	{
		At = SwingPose.IMPACT,
		Pose = { Shoulder = 75, Elbow = 5, Grip = 0, WaistPitch = -12, WaistYaw = 10 },
		Ease = easeInQuad,
	},
	-- Impact: the hammer bounces back up a little off the boss (cartoon "boing")...
	{
		At = SwingPose.BOUNCE,
		Pose = { Shoulder = 86, Elbow = 8, Grip = 6, WaistPitch = -10, WaistYaw = 9 },
		Ease = easeOutQuad,
	},
	-- ...and settles, still out in front, for a beat before the return.
	{
		At = 0.66,
		Pose = { Shoulder = 78, Elbow = 10, Grip = 0, WaistPitch = -8, WaistYaw = 8 },
		Ease = easeInOutSine,
	},
	-- Return: the hammer swings smoothly back up onto the shoulder.
	{ At = 1, Pose = SwingPose.REST, Ease = easeInOutSine },
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
				Grip = lerp(from.Grip, to.Grip, alpha),
				WaistPitch = lerp(from.WaistPitch, to.WaistPitch, alpha),
				WaistYaw = lerp(from.WaistYaw, to.WaistYaw, alpha),
			}
		end
	end
	return SwingPose.REST
end

export type HeadScale = {
	Length: number, -- along the mallet head's axis
	Width: number, -- across it
}

local STRETCH_START = 0.36
local SQUASH_PEAK = 0.53
local SQUASH_END = 0.6
local STRETCH: HeadScale = { Length = 1.25, Width = 0.9 }
local SQUASH: HeadScale = { Length = 0.8, Width = 1.2 }
local NORMAL: HeadScale = { Length = 1, Width = 1 }

local function lerpScale(from: HeadScale, to: HeadScale, alpha: number): HeadScale
	return {
		Length = lerp(from.Length, to.Length, alpha),
		Width = lerp(from.Width, to.Width, alpha),
	}
end

-- Cartoon squash and stretch for the hammer head: it stretches on the
-- downswing, squashes on impact and settles back.
function SwingPose.headScale(progress: number): HeadScale
	local t = math.clamp(progress, 0, 1)
	if t < STRETCH_START or t >= SQUASH_END then
		return NORMAL
	elseif t < SwingPose.IMPACT then
		return lerpScale(NORMAL, STRETCH, (t - STRETCH_START) / (SwingPose.IMPACT - STRETCH_START))
	elseif t < SQUASH_PEAK then
		return lerpScale(STRETCH, SQUASH, (t - SwingPose.IMPACT) / (SQUASH_PEAK - SwingPose.IMPACT))
	end
	return lerpScale(SQUASH, NORMAL, (t - SQUASH_PEAK) / (SQUASH_END - SQUASH_PEAK))
end

-- Whether the swing trail should be drawn (the fast part of the swing).
function SwingPose.trailActive(progress: number): boolean
	return progress > 0.34 and progress < 0.62
end

-- Direction the hammer points in the front-to-back plane (see header).
function SwingPose.hammerAngle(pose: Pose): number
	return pose.Shoulder + pose.Elbow + pose.Grip
end

return SwingPose
