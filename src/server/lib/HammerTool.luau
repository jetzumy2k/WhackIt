--!strict
--[[
	Builds the Tool a player holds. Purely a prop plus the client's swing trigger:
	damage always comes from the player's saved EquippedHammerId, never from
	this Tool, so tampering with it changes nothing. Its parts come from
	Shared/HammerModel and the hammer's look (Config/HammerStyleConfig).

	Orientation: the hand's grip attachment has its +Z axis pointing up the arm
	(toward the elbow). Tool.Grip (HammerModel.gripFor) places the hand at its position in Handle
	space, so the hand sits near the Handle's +Z end and the Handle extends from
	the fist along -Z, continuing the arm. The mallet head sits across that far
	-Z end, so the arm swing sweeps it forward into the boss. (Putting the grip
	at -Z instead points the hammer back along the forearm at the shoulder.)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require(ReplicatedStorage.Shared.Attributes)
local HammerModel = require(ReplicatedStorage.Shared.HammerModel)

local HammerTool = {}

-- Name of the Tool attribute marking it as a hammer (checked by CombatService).
HammerTool.HAMMER_ID_ATTRIBUTE = Attributes.HammerId

-- The look of a hammer; regular HammerDefinitions and resolved Mystery Hammers
-- both fit. Style names a Config/HammerStyleConfig look; without a known one
-- the hammer is drawn plainly in HeadColor / HandleColor.
export type HammerLook = {
	Id: string,
	DisplayName: string,
	Description: string,
	HeadColor: Color3,
	HandleColor: Color3,
	Style: string?,
}

function HammerTool.build(hammer: HammerLook): Tool
	local style = HammerModel.styleFor(hammer.Style, hammer.HeadColor, hammer.HandleColor)

	local tool = Instance.new("Tool")
	tool.Name = hammer.DisplayName
	tool.ToolTip = hammer.Description
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.Grip = HammerModel.gripFor(style)
	tool:SetAttribute(HammerTool.HAMMER_ID_ATTRIBUTE, hammer.Id)

	HammerModel.build(style, tool, CFrame.identity, true)
	return tool
end

return HammerTool
