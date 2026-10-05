--!strict
--[[
	Builds the Tool a player holds. Purely a prop plus the client's swing trigger:
	damage always comes from the server's session (EquippedHammerId), never from
	this Tool, so tampering with it changes nothing.

	The Handle runs along Z with the grip near its -Z end (same convention as the
	classic sword), and the mallet head sits across the +Z end.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)

local HammerTool = {}

local HANDLE_SIZE = Vector3.new(0.35, 0.35, 3.2)
local HEAD_SIZE = Vector3.new(1.6, 1.1, 1.1) -- cylinder: length along its X axis
local GRIP = CFrame.new(0, 0, -1.2)

-- Name of the Tool attribute marking it as a hammer (checked by CombatService).
HammerTool.HAMMER_ID_ATTRIBUTE = "HammerId"

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
	-- Across the far end of the handle, standing upright so the swing lands face-first.
	head.CFrame = handle.CFrame
		* CFrame.new(0, 0, HANDLE_SIZE.Z / 2)
		* CFrame.Angles(0, 0, math.rad(90))
	head.Parent = tool

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = head
	weld.Parent = handle

	return tool
end

return HammerTool
