--!strict
--[[
	Builds the rooms of the Office Wing (docs/OFFICES.md): one open-plan room
	per slot, in a row far above the map (Config/OfficeConfig,
	Shared/FurnitureRules.slotOrigin). Each room is about 15 anchored parts:
	a carpeted floor, walls with a long window on the back wall, a ceiling
	with one soft light, a closed door with a "Back to lobby" prompt, and a
	nameplate above the door. Furniture goes in the room's Furniture folder
	(OfficeService).

	The door is closed on purpose: outside the room there is only sky.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FurnitureRules = require(ReplicatedStorage.Shared.FurnitureRules)
local OfficeConfig = require(ReplicatedStorage.Config.OfficeConfig)

export type Room = {
	Index: number,
	Model: Model,
	Floor: CFrame, -- centre of the floor's top surface
	Furniture: Folder,
	Nameplate: TextLabel,
	Door: BasePart,
}

local OfficeWingBuilder = {}

OfficeWingBuilder.SLOT_ATTRIBUTE = "OfficeSlot"

local CARPET = Color3.fromRGB(78, 86, 112)
local WALL = Color3.fromRGB(96, 104, 126)
OfficeWingBuilder.DEFAULT_WALL = WALL
OfficeWingBuilder.DEFAULT_FLOOR = CARPET
local CEILING = Color3.fromRGB(70, 76, 94)
local DOOR = Color3.fromRGB(120, 85, 60)
local SIGN = Color3.fromRGB(45, 52, 78)
local SIGN_TEXT = Color3.fromRGB(255, 225, 150)
local GLASS = Color3.fromRGB(170, 210, 240)
local LAMP = Color3.fromRGB(255, 236, 200)

local SIZE = OfficeConfig.RoomSize
local HALF = SIZE / 2
local HEIGHT = OfficeConfig.WallHeight
local THICK = OfficeConfig.WallThickness
local DOOR_HEIGHT = 10
-- Back-wall window band (heights above the floor).
local WINDOW_BOTTOM = 3
local WINDOW_TOP = 10

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	p.Parent = parent
	return p
end

local function sign(parent: Instance, floor: CFrame): TextLabel
	-- Above the door, on the inside of the +Z wall, readable from the room.
	local board = part(
		parent,
		"Nameplate",
		Vector3.new(14, 2, 0.2),
		floor * CFrame.new(0, DOOR_HEIGHT + 1.6, HALF - 0.1),
		SIGN
	)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.4
	gui.Parent = board
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = SIGN_TEXT
	text.Text = "Vacant Office"
	text.Parent = gui
	return text
end

-- Colours a room's walls and carpet (an office theme, LevelRewardConfig).
function OfficeWingBuilder.paint(room: Room, wall: Color3, floor: Color3): ()
	for _, child in room.Model:GetChildren() do
		if child:IsA("BasePart") then
			if child.Name == "Wall" then
				child.Color = wall
			elseif child.Name == "Floor" then
				child.Color = floor
			end
		end
	end
end

function OfficeWingBuilder.buildRoom(index: number, parent: Instance): Room
	local origin = FurnitureRules.slotOrigin(index)
	local floor = CFrame.new(origin)
	local model = Instance.new("Model")
	model.Name = "Office" .. index
	model:SetAttribute(OfficeWingBuilder.SLOT_ATTRIBUTE, index)

	local outer = SIZE + 2 * THICK
	part(
		model,
		"Floor",
		Vector3.new(outer, 1, outer),
		floor * CFrame.new(0, -0.5, 0),
		CARPET,
		Enum.Material.Carpet
	)
	part(
		model,
		"Ceiling",
		Vector3.new(outer, 1, outer),
		floor * CFrame.new(0, HEIGHT + 0.5, 0),
		CEILING
	)

	-- Side walls (X) are solid.
	for _, side in { -1, 1 } do
		part(
			model,
			"Wall",
			Vector3.new(THICK, HEIGHT, outer),
			floor * CFrame.new(side * (HALF + THICK / 2), HEIGHT / 2, 0),
			WALL
		)
	end

	-- Back wall (-Z): solid below and above a long window.
	local backZ = -(HALF + THICK / 2)
	part(
		model,
		"Wall",
		Vector3.new(SIZE, WINDOW_BOTTOM, THICK),
		floor * CFrame.new(0, WINDOW_BOTTOM / 2, backZ),
		WALL
	)
	part(
		model,
		"Wall",
		Vector3.new(SIZE, HEIGHT - WINDOW_TOP, THICK),
		floor * CFrame.new(0, (WINDOW_TOP + HEIGHT) / 2, backZ),
		WALL
	)
	local window = part(
		model,
		"Window",
		Vector3.new(SIZE, WINDOW_TOP - WINDOW_BOTTOM, 0.3),
		floor * CFrame.new(0, (WINDOW_BOTTOM + WINDOW_TOP) / 2, backZ),
		GLASS,
		Enum.Material.Glass
	)
	window.Transparency = 0.6
	window.CastShadow = false

	-- Front wall (+Z): two solid pieces, a lintel, and the closed door.
	local frontZ = HALF + THICK / 2
	local pieceWidth = (SIZE - OfficeConfig.DoorWidth) / 2
	for _, side in { -1, 1 } do
		part(
			model,
			"Wall",
			Vector3.new(pieceWidth, HEIGHT, THICK),
			floor * CFrame.new(side * (OfficeConfig.DoorWidth + pieceWidth) / 2, HEIGHT / 2, frontZ),
			WALL
		)
	end
	part(
		model,
		"Wall",
		Vector3.new(OfficeConfig.DoorWidth, HEIGHT - DOOR_HEIGHT, THICK),
		floor * CFrame.new(0, (DOOR_HEIGHT + HEIGHT) / 2, frontZ),
		WALL
	)
	local door = part(
		model,
		"Door",
		Vector3.new(OfficeConfig.DoorWidth, DOOR_HEIGHT, THICK),
		floor * CFrame.new(0, DOOR_HEIGHT / 2, frontZ),
		DOOR,
		Enum.Material.Wood
	)

	-- One soft light (eye-friendly like the office: brightness under 1, no shadows).
	local lamp = part(
		model,
		"Lamp",
		Vector3.new(8, 0.2, 8),
		floor * CFrame.new(0, HEIGHT - 0.1, 0),
		LAMP,
		Enum.Material.SmoothPlastic
	)
	local light = Instance.new("PointLight")
	light.Brightness = 0.8
	light.Range = 40
	light.Shadows = false
	light.Color = LAMP
	light.Parent = lamp

	local nameplate = sign(model, floor)
	local furniture = Instance.new("Folder")
	furniture.Name = "Furniture"
	furniture.Parent = model

	model.Parent = parent
	return {
		Index = index,
		Model = model,
		Floor = floor,
		Furniture = furniture,
		Nameplate = nameplate,
		Door = door,
	}
end

return OfficeWingBuilder
