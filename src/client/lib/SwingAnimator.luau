--!strict
--[[
	Poses characters that hold a hammer (Shared/SwingPose): carried on the
	shoulder at rest, and the full swing when play() is called.

	It rotates each joint's base offset (Motor6D.C0, the hand's RightGrip weld
	C0 for the wrist, or the Attachment0 of an AnimationConstraint joint on
	upgraded avatars) by the pose's difference from the tool-hold animation that
	Roblox keeps playing. The Animator never writes those properties, so the
	pose layers on top regardless of update order. Base offsets are captured
	once and restored when the hammer is put away.

	These changes are local to this client: every client poses every hammer
	holder itself (HammerPoseController), and replays other players' swings when
	their hits are confirmed (FeedbackController).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local SwingPose = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SwingPose"))

local SwingAnimator = {}

-- One rotatable joint, whatever the rig uses under the hood.
type Joint = {
	Base: CFrame, -- the joint's offset before any posing touched it
	Set: (offset: CFrame) -> (),
	IsAlive: () -> boolean,
}

type Holder = {
	IsR6: boolean,
	Shoulder: Joint?,
	Elbow: Joint?,
	Waist: Joint?,
	Grip: Joint?,
	SwingStartedAt: number?,
	SwingStartProgress: number,
}

local IS_STUDIO = RunService:IsStudio()

local holders: { [Model]: Holder } = {}
local jointCache: { [Instance]: Joint } = {}
local warnedCharacters: { [Model]: boolean } = {}
local connection: RBXScriptConnection? = nil

-- Base offsets are captured the first time a joint is seen, so restarted or
-- overlapping poses can never "bake in" a modified offset.
local function wrap(instance: Instance): Joint?
	local cached = jointCache[instance]
	if cached then
		return cached
	end

	local joint: Joint? = nil
	if instance:IsA("Motor6D") or instance:IsA("Weld") then
		local weld = instance :: JointInstance
		joint = {
			Base = weld.C0,
			Set = function(offset: CFrame)
				weld.C0 = offset
			end,
			IsAlive = function(): boolean
				return weld.Parent ~= nil
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

local function alive(joint: Joint?): Joint?
	return if joint and joint.IsAlive() then joint else nil
end

-- Re-resolves joints that are missing or gone. The RightGrip weld in particular
-- only exists once the hammer is equipped and replicated.
local function refreshJoints(character: Model, holder: Holder): ()
	if alive(holder.Shoulder) == nil then
		holder.Shoulder = findJoint(character, "RightUpperArm", "RightShoulder")
		holder.IsR6 = false
		if holder.Shoulder == nil then
			holder.Shoulder = findJoint(character, "Torso", "Right Shoulder")
			holder.IsR6 = holder.Shoulder ~= nil
		end
	end
	if not holder.IsR6 then
		holder.Elbow = alive(holder.Elbow) or findJoint(character, "RightLowerArm", "RightElbow")
		holder.Waist = alive(holder.Waist) or findJoint(character, "UpperTorso", "Waist")
	end
	if alive(holder.Grip) == nil then
		holder.Grip =
			findJoint(character, if holder.IsR6 then "Right Arm" else "RightHand", "RightGrip")
	end
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

local function restoreJoint(joint: Joint?): ()
	if joint and joint.IsAlive() then
		joint.Set(joint.Base)
	end
end

local function restore(holder: Holder): ()
	restoreJoint(holder.Shoulder)
	restoreJoint(holder.Elbow)
	restoreJoint(holder.Waist)
	restoreJoint(holder.Grip)
end

-- Every joint here hinges about its local X axis in the front-to-back plane,
-- except the R6 shoulder, which hinges about Z.
local function hinge(joint: Joint?, degrees: number, aboutZ: boolean?): ()
	if joint == nil then
		return
	end
	local radians = math.rad(degrees)
	local rotation = if aboutZ then CFrame.Angles(0, 0, radians) else CFrame.Angles(radians, 0, 0)
	joint.Set(joint.Base * rotation)
end

local function apply(holder: Holder, pose: SwingPose.Pose): ()
	local base = SwingPose.ANIMATOR_HOLD
	local elbowDelta = pose.Elbow - base.Elbow
	local gripDelta = pose.Grip - base.Grip

	if holder.IsR6 then
		-- No elbow on R6: the wrist takes the elbow's share so the hammer still
		-- points the same way.
		hinge(holder.Shoulder, pose.Shoulder - base.Shoulder, true)
		hinge(holder.Grip, gripDelta + elbowDelta)
		return
	end

	hinge(holder.Shoulder, pose.Shoulder - base.Shoulder)
	hinge(holder.Elbow, elbowDelta)
	hinge(holder.Grip, gripDelta)
	local waist = holder.Waist
	if waist then
		local pitch = math.rad(pose.WaistPitch - base.WaistPitch)
		local yaw = math.rad(pose.WaistYaw - base.WaistYaw)
		waist.Set(waist.Base * CFrame.Angles(pitch, yaw, 0))
	end
end

local function step(): ()
	local now = os.clock()
	for character, holder in holders do
		if character.Parent == nil then
			holders[character] = nil
			continue
		end
		refreshJoints(character, holder)
		if holder.Shoulder == nil then
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
			continue
		end

		local progress = 1
		if holder.SwingStartedAt then
			progress = holder.SwingStartProgress
				+ (now - holder.SwingStartedAt) / GameConfig.HitCooldown
			if progress >= 1 then
				holder.SwingStartedAt = nil
				progress = 1
			end
		end
		apply(holder, SwingPose.at(progress))
	end

	if next(holders) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

-- Start or stop posing `character` as a hammer holder (rest on the shoulder).
function SwingAnimator.setHolding(character: Model, holding: boolean): ()
	local holder = holders[character]
	if holding then
		if holder == nil then
			holders[character] = {
				IsR6 = false,
				Shoulder = nil,
				Elbow = nil,
				Waist = nil,
				Grip = nil,
				SwingStartedAt = nil,
				SwingStartProgress = 0,
			}
		end
		if connection == nil then
			-- Before rendering each frame, so the pose shown matches the swing timing.
			connection = RunService.PreRender:Connect(step)
		end
	elseif holder then
		restore(holder)
		holders[character] = nil
	end
end

-- Plays one swing on a hammer holder. `startProgress` lets other players'
-- swings begin late, e.g. just before impact.
function SwingAnimator.play(character: Model, startProgress: number?): ()
	local holder = holders[character]
	if holder == nil then
		return
	end
	holder.SwingStartedAt = os.clock()
	holder.SwingStartProgress = math.clamp(startProgress or 0, 0, 1)
end

-- Seconds from the start of a swing until it reaches `progress` (0..1), e.g.
-- SwingPose.IMPACT for the moment the hammer lands.
function SwingAnimator.secondsUntil(progress: number): number
	return GameConfig.HitCooldown * math.clamp(progress, 0, 1)
end

return SwingAnimator
