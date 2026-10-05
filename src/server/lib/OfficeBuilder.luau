--!strict
--[[
	Builds the office floor (ArenaConfig) out of simple anchored parts: one
	office per boss along a corridor, plus the lobby. Placeholder art in the
	same cartoon style as the bosses; replace with modelled assets later.

	Every part is anchored. Furniture is tagged with the "Furniture" attribute so
	specs can check it never crowds the boss or blocks the doorway.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local BossVisualConfig = require(ReplicatedStorage.Config.BossVisualConfig)

local OfficeBuilder = {}

OfficeBuilder.FURNITURE_ATTRIBUTE = "Furniture"

local WALL_COLOR = Color3.fromRGB(236, 232, 224)
local WALL_THICKNESS = 1
local WOOD = Color3.fromRGB(150, 105, 70)
local METAL = Color3.fromRGB(120, 125, 135)
local DARK = Color3.fromRGB(40, 42, 50)
local LEAF = Color3.fromRGB(70, 160, 80)
local POT = Color3.fromRGB(190, 110, 70)
local PAPER = Color3.fromRGB(250, 248, 240)
local CORRIDOR_CARPET = Color3.fromRGB(80, 90, 110)
local CORRIDOR = { MinZ = -20, MaxZ = 0 }
local LOBBY = { HalfWidth = 36, MaxZ = 34 }

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.Position = position
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function furniture(p: Part): Part
	p:SetAttribute(OfficeBuilder.FURNITURE_ATTRIBUTE, true)
	return p
end

-- Readable text on one face of a part.
local function sign(p: Part, face: Enum.NormalId, text: string, textColor: Color3): ()
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = textColor
	label.Text = text
	label.Parent = gui
end

local function plant(parent: Instance, position: Vector3): ()
	furniture(part(parent, "PlantPot", Vector3.new(2, 2, 2), position + Vector3.new(0, 1, 0), POT))
	local leaves = furniture(
		part(parent, "PlantLeaves", Vector3.new(4, 4, 4), position + Vector3.new(0, 3.6, 0), LEAF)
	)
	leaves.Shape = Enum.PartType.Ball
end

local function desk(parent: Instance, at: Vector3, screenText: string): ()
	furniture(part(parent, "DeskTop", Vector3.new(8, 0.6, 4), at + Vector3.new(0, 3, 0), WOOD))
	for _, offset in
		{
			Vector3.new(-3.6, 1.35, -1.6),
			Vector3.new(3.6, 1.35, -1.6),
			Vector3.new(-3.6, 1.35, 1.6),
			Vector3.new(3.6, 1.35, 1.6),
		}
	do
		furniture(part(parent, "DeskLeg", Vector3.new(0.5, 2.7, 0.5), at + offset, WOOD))
	end
	-- Monitor faces into the room (+Z, the Back face).
	local monitor = furniture(
		part(parent, "Monitor", Vector3.new(3.6, 2.4, 0.3), at + Vector3.new(0, 4.6, -1), DARK)
	)
	sign(monitor, Enum.NormalId.Back, screenText, Color3.fromRGB(120, 255, 140))
	furniture(
		part(parent, "MonitorStand", Vector3.new(0.4, 1, 0.4), at + Vector3.new(0, 3.6, -1), DARK)
	)

	-- Office chair in front of the desk.
	local chairAt = at + Vector3.new(0, 0, 3.5)
	furniture(
		part(parent, "ChairSeat", Vector3.new(3, 0.5, 3), chairAt + Vector3.new(0, 1.8, 0), DARK)
	)
	furniture(
		part(parent, "ChairBack", Vector3.new(3, 3, 0.5), chairAt + Vector3.new(0, 3.5, 1.4), DARK)
	)
	local post = furniture(
		part(
			parent,
			"ChairPost",
			Vector3.new(1.5, 0.5, 0.5),
			chairAt + Vector3.new(0, 0.8, 0),
			METAL
		)
	)
	post.Shape = Enum.PartType.Cylinder
	post.Orientation = Vector3.new(0, 0, 90)
end

local function filingCabinet(parent: Instance, at: Vector3): ()
	furniture(
		part(parent, "FilingCabinet", Vector3.new(3, 5, 3), at + Vector3.new(0, 2.5, 0), METAL)
	)
	for drawer = 1, 3 do
		furniture(
			part(
				parent,
				"Drawer",
				Vector3.new(2.4, 0.2, 0.2),
				at + Vector3.new(0, drawer * 1.5 - 0.3, 1.55),
				DARK
			)
		)
	end
end

-- Walls with a doorway in the front (+Z) wall.
local function walls(parent: Instance, center: Vector3): ()
	local size = ArenaConfig.OfficeSize
	local halfW, halfD, height = size.X / 2, size.Z / 2, size.Y
	local y = height / 2

	part(
		parent,
		"BackWall",
		Vector3.new(size.X, height, WALL_THICKNESS),
		center + Vector3.new(0, y, -halfD),
		WALL_COLOR
	)
	part(
		parent,
		"LeftWall",
		Vector3.new(WALL_THICKNESS, height, size.Z),
		center + Vector3.new(-halfW, y, 0),
		WALL_COLOR
	)
	part(
		parent,
		"RightWall",
		Vector3.new(WALL_THICKNESS, height, size.Z),
		center + Vector3.new(halfW, y, 0),
		WALL_COLOR
	)

	local doorHalf = ArenaConfig.DoorWidth / 2
	local sideWidth = halfW - doorHalf
	for _, side in { -1, 1 } do
		part(
			parent,
			"FrontWall",
			Vector3.new(sideWidth, height, WALL_THICKNESS),
			center + Vector3.new(side * (doorHalf + sideWidth / 2), y, halfD),
			WALL_COLOR
		)
	end
	local lintelHeight = height - ArenaConfig.DoorHeight
	part(
		parent,
		"DoorLintel",
		Vector3.new(ArenaConfig.DoorWidth, lintelHeight, WALL_THICKNESS),
		center + Vector3.new(0, ArenaConfig.DoorHeight + lintelHeight / 2, halfD),
		WALL_COLOR
	)
end

local function buildOffice(parent: Instance, entry: ArenaConfig.Office): ()
	local definition = BossConfig.ById[entry.BossId]
	local look = BossVisualConfig[entry.BossId]
	local room = Instance.new("Model")
	room.Name = definition.DisplayName .. " Office"
	room.Parent = parent

	local center = entry.Center
	local size = ArenaConfig.OfficeSize
	local halfD = size.Z / 2

	part(
		room,
		"Carpet",
		Vector3.new(size.X, 0.1, size.Z),
		center + Vector3.new(0, 0.05, 0),
		entry.CarpetColor,
		Enum.Material.Fabric
	)
	walls(room, center)

	-- Name plate above the door, readable from the corridor.
	local plate = part(
		room,
		"NamePlate",
		Vector3.new(14, 2.6, 0.4),
		center + Vector3.new(0, 12, halfD + 0.7),
		look.BodyColor
	)
	sign(plate, Enum.NormalId.Back, definition.DisplayName .. "'s Office", Color3.new(1, 1, 1))

	-- Furniture hugs the back corners and front corners, leaving the middle
	-- (around the boss) and the path from the door clear.
	desk(room, center + Vector3.new(-9, 0, -11), entry.ScreenText)
	filingCabinet(room, center + Vector3.new(11, 0, -13))
	plant(room, center + Vector3.new(-13, 0, 12))
	plant(room, center + Vector3.new(13, 0, 12))

	local poster = furniture(
		part(
			room,
			"Poster",
			Vector3.new(8, 5, 0.2),
			center + Vector3.new(7, 7, -halfD + 0.7),
			PAPER
		)
	)
	sign(poster, Enum.NormalId.Back, entry.PosterText, Color3.fromRGB(60, 60, 80))
end

local function buildCommonAreas(parent: Instance): ()
	local area = Instance.new("Model")
	area.Name = "Lobby And Corridor"
	area.Parent = parent

	local officeSize = ArenaConfig.OfficeSize
	local lastOffice = ArenaConfig.Offices[#ArenaConfig.Offices].Center
	local corridorHalf = lastOffice.X + officeSize.X / 2 + 2
	local corridorDepth = CORRIDOR.MaxZ - CORRIDOR.MinZ
	local corridorZ = (CORRIDOR.MinZ + CORRIDOR.MaxZ) / 2

	part(
		area,
		"CorridorCarpet",
		Vector3.new(corridorHalf * 2, 0.1, corridorDepth),
		Vector3.new(0, 0.05, corridorZ),
		CORRIDOR_CARPET,
		Enum.Material.Fabric
	)
	for _, side in { -1, 1 } do
		part(
			area,
			"CorridorEndWall",
			Vector3.new(WALL_THICKNESS, officeSize.Y, corridorDepth),
			Vector3.new(side * corridorHalf, officeSize.Y / 2, corridorZ),
			WALL_COLOR
		)
		-- Lobby side walls.
		part(
			area,
			"LobbyWall",
			Vector3.new(WALL_THICKNESS, officeSize.Y, LOBBY.MaxZ),
			Vector3.new(side * LOBBY.HalfWidth, officeSize.Y / 2, LOBBY.MaxZ / 2),
			WALL_COLOR
		)
		-- Corridor walls from the lobby out to the corridor ends.
		local span = corridorHalf - LOBBY.HalfWidth
		part(
			area,
			"CorridorSouthWall",
			Vector3.new(span, officeSize.Y, WALL_THICKNESS),
			Vector3.new(side * (LOBBY.HalfWidth + span / 2), officeSize.Y / 2, CORRIDOR.MaxZ),
			WALL_COLOR
		)
		-- Plants along the corridor between offices.
		for _, x in { 17, 51 } do
			plant(area, Vector3.new(side * x, 0, CORRIDOR.MinZ + 2.5))
		end
	end
	part(
		area,
		"LobbyBackWall",
		Vector3.new(LOBBY.HalfWidth * 2, officeSize.Y, WALL_THICKNESS),
		Vector3.new(0, officeSize.Y / 2, LOBBY.MaxZ),
		WALL_COLOR
	)

	-- Welcome sign hanging over the corridor, facing the spawn.
	local welcome = part(
		area,
		"WelcomeSign",
		Vector3.new(30, 4, 0.5),
		Vector3.new(0, 11, 1),
		Color3.fromRGB(255, 120, 60)
	)
	sign(welcome, Enum.NormalId.Back, "WHACK IT OUT!  Stress Relief Dept.", Color3.new(1, 1, 1))

	-- Reception desk, couches, water cooler and plants.
	furniture(
		part(area, "ReceptionDesk", Vector3.new(12, 3.5, 3), Vector3.new(-22, 1.75, 12), WOOD)
	)
	furniture(
		part(area, "ReceptionTop", Vector3.new(12.4, 0.4, 3.4), Vector3.new(-22, 3.7, 12), PAPER)
	)
	-- Two couches against the east lobby wall, facing the room (-X).
	local couch = Color3.fromRGB(70, 110, 170)
	for _, z in { 10, 22 } do
		furniture(part(area, "CouchSeat", Vector3.new(3, 1.6, 8), Vector3.new(32, 0.8, z), couch))
		furniture(part(area, "CouchBack", Vector3.new(1, 2.4, 8), Vector3.new(34, 2.4, z), couch))
	end
	local cooler = furniture(
		part(
			area,
			"WaterCooler",
			Vector3.new(4, 1.6, 1.6),
			Vector3.new(-30, 2, 28),
			Color3.fromRGB(230, 235, 240)
		)
	)
	cooler.Shape = Enum.PartType.Cylinder
	cooler.Orientation = Vector3.new(0, 0, 90)
	furniture(
		part(
			area,
			"WaterBottle",
			Vector3.new(1.4, 1.6, 1.4),
			Vector3.new(-30, 4.8, 28),
			Color3.fromRGB(120, 190, 255),
			Enum.Material.Glass
		)
	).Transparency =
		0.3
	for _, x in { -32, 32 } do
		plant(area, Vector3.new(x, 0, 31))
	end
end

-- Builds the whole floor under `parent` and returns its folder.
function OfficeBuilder.build(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Office"
	for _, entry in ArenaConfig.Offices do
		buildOffice(folder, entry)
	end
	buildCommonAreas(folder)
	folder.Parent = parent
	return folder
end

return OfficeBuilder
