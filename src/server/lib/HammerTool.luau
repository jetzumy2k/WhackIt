--!strict
--[[
	Builds the Tool a player holds. Purely a prop plus the client's swing trigger:
	damage always comes from the server's session (EquippedHammerId), never from
	this Tool, so tampering with it changes nothing.

	Orientation: the hand's grip attachment has its +Z axis pointing up the arm
	(toward the elbow). Tool.Grip places the hand at GRIP's position in Handle
	space, so the hand sits near the Handle's +Z end and the Handle extends from
	the fist along -Z, continuing the arm. The mallet head sits across that far
	-Z end, so the arm swing sweeps it forward into the boss. (Putting the grip
	at -Z instead points the hammer back along the forearm at the shoulder.)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require(ReplicatedStorage.Shared.Attributes)
local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)

local HammerTool = {}

local HANDLE_SIZE = Vector3.new(0.35, 0.35, 3.2)
local HEAD_SIZE = Vector3.new(1.9, 1.35, 1.35) -- cylinder: length along its X axis
local GRIP = CFrame.new(0, 0, 1.2)

-- Name of the Tool attribute marking it as a hammer (checked by CombatService).
HammerTool.HAMMER_ID_ATTRIBUTE = Attributes.HammerId

local function prop(name: string, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	return part
end

function HammerTool.build(hammer: HammerConfig.HammerDefinition): Tool
	local tool = Instance.new("Tool")
	tool.Name = hammer.DisplayName
	tool.ToolTip = hammer.Description
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.Grip = GRIP
	tool:SetAttribute(HammerTool.HAMMER_ID_ATTRIBUTE, hammer.Id)

	local handle = prop("Handle", HANDLE_SIZE, hammer.HandleColor)
	handle.Parent = tool

	local head = prop("Head", HEAD_SIZE, hammer.HeadColor)
	head.Shape = Enum.PartType.Cylinder
	-- Across the far (-Z) end of the handle, standing upright so the swing lands face-first.
	head.CFrame = handle.CFrame
		* CFrame.new(0, 0, -HANDLE_SIZE.Z / 2)
		* CFrame.Angles(0, 0, math.rad(90))
	head.Parent = tool

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = head
	weld.Parent = handle

	return tool
end

return HammerTool
