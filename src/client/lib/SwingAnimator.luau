--!strict
--[[
	Plays the procedural hammer swing (Shared/SwingPose) on any character by
	overriding joint Motor6D.Transform values each frame. Runs in Stepped, which
	fires after the Animator has posed the character, so it layers on top of the
	normal animations and blends back into them.

	Transform changes are local to this client. Your own swings are seen by
	others because their clients replay the strike when your hit is confirmed
	(FeedbackController).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local SwingPose = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SwingPose"))

local SwingAnimator = {}

type Joints = {
	Shoulder: Motor6D,
	Elbow: Motor6D?,
	Waist: Motor6D?,
	IsR6: boolean,
}

type ActiveSwing = {
	StartedAt: number,
	StartProgress: number,
	Joints: Joints,
}

local active: { [Model]: ActiveSwing } = {}
local connection: RBXScriptConnection? = nil

local function findMotor(character: Model, partName: string, motorName: string): Motor6D?
	local part = character:FindFirstChild(partName)
	local motor = if part then part:FindFirstChild(motorName) else nil
	return if motor and motor:IsA("Motor6D") then motor else nil
end

local function findJoints(character: Model): Joints?
	local shoulder = findMotor(character, "RightUpperArm", "RightShoulder")
	if shoulder then
		return {
			Shoulder = shoulder,
			Elbow = findMotor(character, "RightLowerArm", "RightElbow"),
			Waist = findMotor(character, "UpperTorso", "Waist"),
			IsR6 = false,
		}
	end
	local r6Shoulder = findMotor(character, "Torso", "Right Shoulder")
	if r6Shoulder then
		return { Shoulder = r6Shoulder, Elbow = nil, Waist = nil, IsR6 = true }
	end
	return nil
end

local function apply(swing: ActiveSwing, progress: number): ()
	local pose = SwingPose.at(progress)
	local weight = SwingPose.blend(progress)
	local joints = swing.Joints

	-- R6 shoulders rotate about their Z axis; R15 joints about X (and Y for the waist).
	local shoulderRotation = if joints.IsR6
		then CFrame.Angles(0, 0, math.rad(pose.Shoulder))
		else CFrame.Angles(math.rad(pose.Shoulder), 0, 0)
	joints.Shoulder.Transform = joints.Shoulder.Transform:Lerp(shoulderRotation, weight)

	if joints.Elbow then
		joints.Elbow.Transform =
			joints.Elbow.Transform:Lerp(CFrame.Angles(math.rad(pose.Elbow), 0, 0), weight)
	end
	if joints.Waist then
		local waistRotation = CFrame.Angles(math.rad(pose.WaistPitch), math.rad(pose.WaistYaw), 0)
		joints.Waist.Transform = joints.Waist.Transform:Lerp(waistRotation, weight)
	end
end

local function step(): ()
	local now = os.clock()
	local duration = GameConfig.HitCooldown
	for character, swing in active do
		local progress = swing.StartProgress + (now - swing.StartedAt) / duration
		if progress >= 1 or character.Parent == nil or swing.Joints.Shoulder.Parent == nil then
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
		connection = RunService.Stepped:Connect(step)
	end
end

-- Seconds from the start of a swing until it reaches `progress` (0..1), e.g.
-- SwingPose.IMPACT for the moment the hammer lands.
function SwingAnimator.secondsUntil(progress: number): number
	return GameConfig.HitCooldown * math.clamp(progress, 0, 1)
end

return SwingAnimator
