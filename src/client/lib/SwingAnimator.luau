--!strict
--[[
	Plays the procedural hammer swing (Shared/SwingPose) on any character.

	It rotates each joint's base offset (Motor6D.C0, or the Attachment0 of an
	AnimationConstraint joint on upgraded avatars) by the swing's difference from
	the holding pose. The Animator never writes those properties, so the swing
	layers on top of the playing animations regardless of which runs first, and
	restoring the stored base offset afterwards returns the arm to normal.

	These changes are local to this client. Your own swings are seen by others
	because their clients replay the strike when your hit is confirmed
	(FeedbackController).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local SwingPose = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SwingPose"))

local SwingAnimator = {}

-- One rotatable joint, whatever the rig uses under the hood.
type Joint = {
	Base: CFrame, -- the joint's offset before any swing touched it
	Set: (offset: CFrame) -> (),
	IsAlive: () -> boolean,
}

type Joints = {
	Shoulder: Joint,
	Elbow: Joint?,
	Waist: Joint?,
	IsR6: boolean,
}

type ActiveSwing = {
	StartedAt: number,
	StartProgress: number,
	Joints: Joints,
}

local IS_STUDIO = RunService:IsStudio()

local active: { [Model]: ActiveSwing } = {}
local jointCache: { [Instance]: Joint } = {}
local warnedCharacters: { [Model]: boolean } = {}
local connection: RBXScriptConnection? = nil

-- Base offsets are captured the first time a joint is seen, so overlapping or
-- restarted swings can never "bake in" a mid-swing offset.
local function wrap(instance: Instance): Joint?
	local cached = jointCache[instance]
	if cached then
		return cached
	end

	local joint: Joint? = nil
	if instance:IsA("Motor6D") then
		local motor = instance
		joint = {
			Base = motor.C0,
			Set = function(offset: CFrame)
				motor.C0 = offset
			end,
			IsAlive = function(): boolean
				return motor.Parent ~= nil
			end,
		}
	elseif instance:IsA("AnimationConstraint") then
		local attachment = instance.Attachment0
		if attachment then
			joint = {
				Base = attachment.CFrame,
				Set = function(offset: CFrame)
					attachment.CFrame = offset
				end,
				IsAlive = function(): boolean
					return instance.Parent ~= nil and attachment.Parent ~= nil
				end,
			}
		end
	end

	if joint then
		jointCache[instance] = joint
		instance.Destroying:Connect(function()
			jointCache[instance] = nil
		end)
	end
	return joint
end

local function findJoint(character: Model, partName: string, jointName: string): Joint?
	local part = character:FindFirstChild(partName)
	local instance = if part then part:FindFirstChild(jointName) else nil
	if instance == nil then
		-- Some rigs keep joints elsewhere in the character.
		instance = character:FindFirstChild(jointName, true)
	end
	return if instance then wrap(instance) else nil
end

local function describeJoints(character: Model): string
	local names: { string } = {}
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("JointInstance") or descendant:IsA("AnimationConstraint") then
			table.insert(names, descendant.Name .. " (" .. descendant.ClassName .. ")")
		end
	end
	return if #names > 0 then table.concat(names, ", ") else "none"
end

local function findJoints(character: Model): Joints?
	local shoulder = findJoint(character, "RightUpperArm", "RightShoulder")
	if shoulder then
		return {
			Shoulder = shoulder,
			Elbow = findJoint(character, "RightLowerArm", "RightElbow"),
			Waist = findJoint(character, "UpperTorso", "Waist"),
			IsR6 = false,
		}
	end
	local r6Shoulder = findJoint(character, "Torso", "Right Shoulder")
	if r6Shoulder then
		return { Shoulder = r6Shoulder, Elbow = nil, Waist = nil, IsR6 = true }
	end

	if IS_STUDIO and not warnedCharacters[character] then
		warnedCharacters[character] = true
		warn(
			string.format(
				"[SwingAnimator] no right-shoulder joint on %s; joints found: %s",
				character.Name,
				describeJoints(character)
			)
		)
	end
	return nil
end

local function restoreJoint(joint: Joint?): ()
	if joint and joint.IsAlive() then
		joint.Set(joint.Base)
	end
end

local function restore(joints: Joints): ()
	restoreJoint(joints.Shoulder)
	restoreJoint(joints.Elbow)
	restoreJoint(joints.Waist)
end

-- Rotations are the swing's difference from the holding pose, scaled by the
-- blend weight, so the playing hold animation stays in charge at the ends.
local function apply(swing: ActiveSwing, progress: number): ()
	local pose = SwingPose.at(progress)
	local hold = SwingPose.HOLD
	local weight = SwingPose.blend(progress)
	local joints = swing.Joints

	local shoulderDelta = math.rad(pose.Shoulder - hold.Shoulder) * weight
	-- R6 shoulders hinge about their Z axis; R15 joints about X (and Y for the waist).
	local shoulderRotation = if joints.IsR6
		then CFrame.Angles(0, 0, shoulderDelta)
		else CFrame.Angles(shoulderDelta, 0, 0)
	joints.Shoulder.Set(joints.Shoulder.Base * shoulderRotation)

	local elbow = joints.Elbow
	if elbow then
		elbow.Set(elbow.Base * CFrame.Angles(math.rad(pose.Elbow - hold.Elbow) * weight, 0, 0))
	end
	local waist = joints.Waist
	if waist then
		local pitch = math.rad(pose.WaistPitch - hold.WaistPitch) * weight
		local yaw = math.rad(pose.WaistYaw - hold.WaistYaw) * weight
		waist.Set(waist.Base * CFrame.Angles(pitch, yaw, 0))
	end
end

local function step(): ()
	local now = os.clock()
	local duration = GameConfig.HitCooldown
	for character, swing in active do
		local progress = swing.StartProgress + (now - swing.StartedAt) / duration
		if progress >= 1 or character.Parent == nil or not swing.Joints.Shoulder.IsAlive() then
			restore(swing.Joints)
			active[character] = nil
			continue
		end
		apply(swing, progress)
	end

	if next(active) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

-- Starts (or restarts) a swing on `character`. `startProgress` lets other
-- players' swings begin late, e.g. just before impact.
function SwingAnimator.play(character: Model, startProgress: number?): ()
	local joints = findJoints(character)
	if joints == nil then
		return
	end
	active[character] = {
		StartedAt = os.clock(),
		StartProgress = math.clamp(startProgress or 0, 0, 1),
		Joints = joints,
	}
	if connection == nil then
		-- Before rendering each frame, so the pose shown matches the swing timing.
		connection = RunService.PreRender:Connect(step)
	end
end

-- Seconds from the start of a swing until it reaches `progress` (0..1), e.g.
-- SwingPose.IMPACT for the moment the hammer lands.
function SwingAnimator.secondsUntil(progress: number): number
	return GameConfig.HitCooldown * math.clamp(progress, 0, 1)
end

return SwingAnimator
