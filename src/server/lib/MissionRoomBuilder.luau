--!strict
--[[
	Builds the team mission rooms (docs/MISSIONS.md): MissionConfig.Rooms.Count
	square rooms in a row far from the campus (MissionRules.roomCenter), each
	a floor, four walls and a board over the far wall that MissionService
	writes the mission's name on. Anchored and static: nothing moves, so the
	rooms cost nothing per frame. Bosses are spawned by BossService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MissionConfig = require(ReplicatedStorage.Config.MissionConfig)
local MissionRules = require(ReplicatedStorage.Shared.MissionRules)

export type Room = {
	Index: number,
	Center: Vector3, -- middle of the floor's top
	Model: Model,
	Board: TextLabel,
}

local MissionRoomBuilder = {}

local WALL_HEIGHT = 18
local WALL_THICKNESS = 2
local FLOOR_COLOR = Color3.fromRGB(205, 196, 178)
local WALL_COLOR = Color3.fromRGB(150, 190, 215)
local TRIM_COLOR = Color3.fromRGB(70, 80, 100)

local function part(
	model: Model,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3
): Part
	local block = Instance.new("Part")
	block.Name = name
	block.Anchored = true
	block.Size = size
	block.Position = position
	block.Color = color
	block.Material = Enum.Material.SmoothPlastic
	block.TopSurface = Enum.SurfaceType.Smooth
	block.BottomSurface = Enum.SurfaceType.Smooth
	block.Parent = model
	return block
end

-- Where players arrive: near the room's front wall, facing the bosses.
function MissionRoomBuilder.arrival(center: Vector3, slot: number): CFrame
	local position = center + Vector3.new((slot - 2.5) * 5, 3, MissionConfig.Rooms.Size / 2 - 12)
	return CFrame.lookAt(position, position + Vector3.new(0, 0, -1))
end

function MissionRoomBuilder.buildRoom(index: number, parent: Instance): Room
	local size = MissionConfig.Rooms.Size
	local center = MissionRules.roomCenter(index)
	local model = Instance.new("Model")
	model.Name = "MissionRoom" .. index
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	part(model, "Floor", Vector3.new(size, 1, size), center - Vector3.new(0, 0.5, 0), FLOOR_COLOR)
	local half = size / 2
	local wallY = center.Y + WALL_HEIGHT / 2
	for _, wall in
		{
			{
				Name = "WallNorth",
				Size = Vector3.new(size, WALL_HEIGHT, WALL_THICKNESS),
				Offset = Vector3.new(0, 0, -half),
			},
			{
				Name = "WallSouth",
				Size = Vector3.new(size, WALL_HEIGHT, WALL_THICKNESS),
				Offset = Vector3.new(0, 0, half),
			},
			{
				Name = "WallWest",
				Size = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, size),
				Offset = Vector3.new(-half, 0, 0),
			},
			{
				Name = "WallEast",
				Size = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, size),
				Offset = Vector3.new(half, 0, 0),
			},
		}
	do
		part(
			model,
			wall.Name,
			wall.Size,
			Vector3.new(center.X, wallY, center.Z) + wall.Offset,
			WALL_COLOR
		)
	end
	-- A trim along the top of the walls, and the board on the far (north) wall.
	part(
		model,
		"Trim",
		Vector3.new(size, 1, WALL_THICKNESS + 0.4),
		Vector3.new(center.X, center.Y + WALL_HEIGHT, center.Z - half),
		TRIM_COLOR
	)
	local board = part(
		model,
		"Board",
		Vector3.new(40, 7, 0.4),
		Vector3.new(
			center.X,
			center.Y + WALL_HEIGHT - 5,
			center.Z - half + WALL_THICKNESS / 2 + 0.3
		),
		TRIM_COLOR
	)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
	gui.LightInfluence = 0.2
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = "TEAM MISSION"
	label.Parent = gui

	model.Parent = parent
	return { Index = index, Center = center, Model = model, Board = label }
end

function MissionRoomBuilder.build(parent: Instance): { Room }
	local folder = Instance.new("Folder")
	folder.Name = "MissionRooms"
	folder.Parent = parent
	local rooms: { Room } = {}
	for index = 1, MissionConfig.Rooms.Count do
		table.insert(rooms, MissionRoomBuilder.buildRoom(index, folder))
	end
	return rooms
end

return MissionRoomBuilder
