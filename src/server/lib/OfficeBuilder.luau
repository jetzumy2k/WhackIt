--!strict
--[[
	Builds the two-storey office building (ArenaConfig) out of simple anchored
	parts: one office per boss on each floor along a corridor, a double-height
	lobby with stairs to the upper corridor, ceiling lights, windows and a roof.
	Placeholder art in the same cartoon style as the bosses; replace with
	modelled assets later. The outdoor surroundings are Lib/OutdoorBuilder.

	Every part is anchored. Furniture is tagged with the "Furniture" attribute so
	specs can check it never crowds a boss or blocks a doorway.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local BossVisualConfig = require(ReplicatedStorage.Config.BossVisualConfig)

local OfficeBuilder = {}

OfficeBuilder.FURNITURE_ATTRIBUTE = "Furniture"

local WALL_COLOR = Color3.fromRGB(236, 232, 224)
local WALL_THICKNESS = 1
local SLAB_COLOR = Color3.fromRGB(205, 200, 192)
local WOOD = Color3.fromRGB(150, 105, 70)
local METAL = Color3.fromRGB(120, 125, 135)
local DARK = Color3.fromRGB(40, 42, 50)
local LEAF = Color3.fromRGB(70, 160, 80)
local POT = Color3.fromRGB(190, 110, 70)
local PAPER = Color3.fromRGB(250, 248, 240)
local GLASS = Color3.fromRGB(170, 210, 235)
local LIGHT_COLOR = Color3.fromRGB(255, 244, 220)
local CORRIDOR_CARPET = Color3.fromRGB(80, 90, 110)
local CORRIDOR = { MinZ = -20, MaxZ = 0 }
local LOBBY = { HalfWidth = 36 }
local RAIL_HEIGHT = 3.5

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

local function glass(parent: Instance, name: string, size: Vector3, position: Vector3): Part
	local pane = part(parent, name, size, position, GLASS, Enum.Material.Glass)
	pane.Transparency = 0.45
	pane.CastShadow = false
	return pane
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

-- A glowing panel just under a ceiling, with a light that fills the room.
local function ceilingLight(parent: Instance, position: Vector3, range: number): ()
	local panel = part(
		parent,
		"CeilingLight",
		Vector3.new(6, 0.3, 6),
		position,
		LIGHT_COLOR,
		Enum.Material.Neon
	)
	panel.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = LIGHT_COLOR
	light.Range = range
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = panel
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

-- Walls with a doorway in the front (+Z) wall and a window in the back wall.
local function walls(parent: Instance, center: Vector3): ()
	local size = ArenaConfig.OfficeSize
	local halfW, halfD, height = size.X / 2, size.Z / 2, size.Y
	local y = height / 2

	-- Back wall: solid below and above a wide window, with solid sides.
	local windowHalf, windowBottom, windowTop = 10, 4, 10
	local backZ = -halfD
	part(
		parent,
		"BackWallLow",
		Vector3.new(size.X, windowBottom, WALL_THICKNESS),
		center + Vector3.new(0, windowBottom / 2, backZ),
		WALL_COLOR
	)
	part(
		parent,
		"BackWallHigh",
		Vector3.new(size.X, height - windowTop, WALL_THICKNESS),
		center + Vector3.new(0, (windowTop + height) / 2, backZ),
		WALL_COLOR
	)
	local sideWidth = halfW - windowHalf
	for _, side in { -1, 1 } do
		part(
			parent,
			"BackWallSide",
			Vector3.new(sideWidth, windowTop - windowBottom, WALL_THICKNESS),
			center
				+ Vector3.new(
					side * (windowHalf + sideWidth / 2),
					(windowBottom + windowTop) / 2,
					backZ
				),
			WALL_COLOR
		)
	end
	glass(
		parent,
		"Window",
		Vector3.new(windowHalf * 2, windowTop - windowBottom, 0.3),
		center + Vector3.new(0, (windowBottom + windowTop) / 2, backZ)
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
	local frontSide = halfW - doorHalf
	for _, side in { -1, 1 } do
		part(
			parent,
			"FrontWall",
			Vector3.new(frontSide, height, WALL_THICKNESS),
			center + Vector3.new(side * (doorHalf + frontSide / 2), y, halfD),
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
	ceilingLight(room, center + Vector3.new(0, size.Y - 0.3, 0), 28)

	-- Name plate above the door, readable from the corridor.
	local plate = part(
		room,
		"NamePlate",
		Vector3.new(14, 2.6, 0.4),
		center + Vector3.new(0, 12, halfD + 0.7),
		look.BodyColor
	)
	sign(plate, Enum.NormalId.Back, definition.DisplayName .. "'s Office", Color3.new(1, 1, 1))

	-- Furniture hugs the walls and corners, leaving the middle (around the
	-- boss) and the path from the door clear.
	desk(room, center + Vector3.new(-9, 0, -11), entry.ScreenText)
	filingCabinet(room, center + Vector3.new(11, 0, -13))
	plant(room, center + Vector3.new(-13, 0, 12))
	plant(room, center + Vector3.new(13, 0, 12))

	local poster = furniture(
		part(
			room,
			"Poster",
			Vector3.new(6, 3.4, 0.2),
			center + Vector3.new(11, 11.6, -halfD + 0.7),
			PAPER
		)
	)
	sign(poster, Enum.NormalId.Back, entry.PosterText, Color3.fromRGB(60, 60, 80))
	local whiteboard = furniture(
		part(room, "Whiteboard", Vector3.new(0.2, 4, 8), center + Vector3.new(-15.3, 7, 2), PAPER)
	)
	sign(whiteboard, Enum.NormalId.Right, "TODO: relax", Color3.fromRGB(40, 90, 200))
end

local function buildStairs(parent: Instance): ()
	local stairs = ArenaConfig.Stairs
	local steps = math.round(ArenaConfig.UpperFloorY / stairs.StepHeight)
	for index = 1, steps do
		local height = index * stairs.StepHeight
		local z = stairs.BottomZ - (index - 0.5) * stairs.StepDepth
		part(
			parent,
			"Step",
			Vector3.new(stairs.Width, height, stairs.StepDepth),
			Vector3.new(stairs.X, height / 2, z),
			Color3.fromRGB(185, 175, 160),
			Enum.Material.WoodPlanks
		)
	end
	-- Landing joining the top step to the upper corridor floor.
	local topZ = stairs.BottomZ - steps * stairs.StepDepth
	part(
		parent,
		"StairLanding",
		Vector3.new(stairs.Width, 1, topZ - CORRIDOR.MaxZ),
		Vector3.new(stairs.X, ArenaConfig.UpperFloorY - 0.5, (topZ + CORRIDOR.MaxZ) / 2),
		SLAB_COLOR
	)
	-- Handrail on the open (west) side.
	local railLength = stairs.BottomZ - topZ
	local rail = part(
		parent,
		"StairRail",
		Vector3.new(0.4, 0.4, math.sqrt(railLength ^ 2 + ArenaConfig.UpperFloorY ^ 2)),
		Vector3.new(
			stairs.X - stairs.Width / 2,
			ArenaConfig.UpperFloorY / 2 + RAIL_HEIGHT,
			(stairs.BottomZ + topZ) / 2
		),
		METAL,
		Enum.Material.Metal
	)
	rail.Orientation = Vector3.new(math.deg(math.atan2(ArenaConfig.UpperFloorY, railLength)), 0, 0)
end

local function buildCommonAreas(parent: Instance): ()
	local area = Instance.new("Model")
	area.Name = "Lobby And Corridors"
	area.Parent = parent

	local officeHeight = ArenaConfig.OfficeSize.Y
	local upperY = ArenaConfig.UpperFloorY
	local roofY = ArenaConfig.RoofY
	local half = ArenaConfig.BuildingHalfWidth
	local northZ, southZ = ArenaConfig.BuildingNorthZ, ArenaConfig.BuildingSouthZ
	local corridorDepth = CORRIDOR.MaxZ - CORRIDOR.MinZ
	local corridorZ = (CORRIDOR.MinZ + CORRIDOR.MaxZ) / 2
	local stairs = ArenaConfig.Stairs

	-- Floors, slab between storeys (also the ground floor's ceiling) and roof.
	part(
		area,
		"CorridorCarpet",
		Vector3.new(half * 2, 0.1, corridorDepth),
		Vector3.new(0, 0.05, corridorZ),
		CORRIDOR_CARPET,
		Enum.Material.Fabric
	)
	part(
		area,
		"UpperSlab",
		Vector3.new(half * 2, upperY - officeHeight, CORRIDOR.MaxZ - northZ),
		Vector3.new(0, (officeHeight + upperY) / 2, (CORRIDOR.MaxZ + northZ) / 2),
		SLAB_COLOR
	)
	part(
		area,
		"UpperCorridorCarpet",
		Vector3.new(half * 2, 0.1, corridorDepth),
		Vector3.new(0, upperY + 0.05, corridorZ),
		CORRIDOR_CARPET,
		Enum.Material.Fabric
	)
	part(
		area,
		"Roof",
		Vector3.new(half * 2, 1, southZ - northZ),
		Vector3.new(0, roofY + 0.5, (southZ + northZ) / 2),
		SLAB_COLOR
	)

	-- Full-height end walls (seal the building from the outside).
	for _, side in { -1, 1 } do
		part(
			area,
			"EndWall",
			Vector3.new(WALL_THICKNESS, roofY, CORRIDOR.MaxZ - northZ),
			Vector3.new(side * half, roofY / 2, (CORRIDOR.MaxZ + northZ) / 2),
			WALL_COLOR
		)

		-- Corridor walls between the lobby and the building ends, both storeys.
		local span = half - LOBBY.HalfWidth
		part(
			area,
			"CorridorSouthWall",
			Vector3.new(span, roofY, WALL_THICKNESS),
			Vector3.new(side * (LOBBY.HalfWidth + span / 2), roofY / 2, CORRIDOR.MaxZ),
			WALL_COLOR
		)

		-- Double-height lobby side walls.
		part(
			area,
			"LobbyWall",
			Vector3.new(WALL_THICKNESS, roofY, southZ - CORRIDOR.MaxZ),
			Vector3.new(side * LOBBY.HalfWidth, roofY / 2, (southZ + CORRIDOR.MaxZ) / 2),
			WALL_COLOR
		)

		-- Plants along both corridors between offices.
		for _, floorY in { 0, upperY } do
			for _, x in { 17, 51 } do
				plant(area, Vector3.new(side * x, floorY, CORRIDOR.MinZ + 2.5))
			end
		end
	end

	-- Railing along the upper corridor's edge over the atrium, open at the stairs.
	local stairWest = stairs.X - stairs.Width / 2
	local railSegments = {
		{ From = -LOBBY.HalfWidth, To = stairWest },
		{ From = stairs.X + stairs.Width / 2, To = LOBBY.HalfWidth },
	}
	for _, segment in railSegments do
		local length = segment.To - segment.From
		if length > 0 then
			glass(
				area,
				"AtriumRailing",
				Vector3.new(length, RAIL_HEIGHT, 0.3),
				Vector3.new(
					(segment.From + segment.To) / 2,
					upperY + RAIL_HEIGHT / 2,
					CORRIDOR.MaxZ + 0.3
				)
			)
		end
	end

	-- Lobby front: a glass wall between solid bands, facing the street.
	part(
		area,
		"LobbyFrontLow",
		Vector3.new(LOBBY.HalfWidth * 2, 2, WALL_THICKNESS),
		Vector3.new(0, 1, southZ),
		WALL_COLOR
	)
	part(
		area,
		"LobbyFrontHigh",
		Vector3.new(LOBBY.HalfWidth * 2, 4, WALL_THICKNESS),
		Vector3.new(0, roofY - 2, southZ),
		WALL_COLOR
	)
	glass(
		area,
		"LobbyFrontGlass",
		Vector3.new(LOBBY.HalfWidth * 2, roofY - 6, 0.4),
		Vector3.new(0, 2 + (roofY - 6) / 2, southZ)
	)

	buildStairs(area)

	-- Lights: corridors on both storeys, and the lobby atrium.
	for x = -68, 68, 34 do
		ceilingLight(area, Vector3.new(x, officeHeight - 0.3, corridorZ), 24)
		ceilingLight(area, Vector3.new(x, roofY - 0.3, corridorZ), 24)
	end
	for _, x in { -18, 18 } do
		ceilingLight(area, Vector3.new(x, roofY - 0.3, 18), 40)
	end

	-- Welcome sign over the corridor entrance, facing the spawn.
	local welcome = part(
		area,
		"WelcomeSign",
		Vector3.new(30, 4, 0.5),
		Vector3.new(0, 11, 1),
		Color3.fromRGB(255, 120, 60)
	)
	sign(welcome, Enum.NormalId.Back, "WHACK IT OUT!  Stress Relief Dept.", Color3.new(1, 1, 1))
	-- On the front wall above the foot of the stairs, facing into the lobby (-Z).
	local upstairs = part(
		area,
		"UpstairsSign",
		Vector3.new(6, 2.5, 0.4),
		Vector3.new(stairs.X, 7, ArenaConfig.BuildingSouthZ - 0.8),
		Color3.fromRGB(60, 70, 110)
	)
	sign(upstairs, Enum.NormalId.Front, "Senior Offices (Lv 10+)", Color3.fromRGB(255, 220, 120))

	-- Reception, couches, water cooler and plants.
	furniture(
		part(area, "ReceptionDesk", Vector3.new(12, 3.5, 3), Vector3.new(-22, 1.75, 12), WOOD)
	)
	furniture(
		part(area, "ReceptionTop", Vector3.new(12.4, 0.4, 3.4), Vector3.new(-22, 3.7, 12), PAPER)
	)
	local couch = Color3.fromRGB(70, 110, 170)
	for _, x in { -12, 12 } do
		-- Facing into the lobby (north) from the glass front.
		furniture(part(area, "CouchSeat", Vector3.new(8, 1.6, 3), Vector3.new(x, 0.8, 30), couch))
		furniture(part(area, "CouchBack", Vector3.new(8, 2.4, 1), Vector3.new(x, 2.4, 32), couch))
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
	local bottle = furniture(
		part(
			area,
			"WaterBottle",
			Vector3.new(1.4, 1.6, 1.4),
			Vector3.new(-30, 4.8, 28),
			Color3.fromRGB(120, 190, 255),
			Enum.Material.Glass
		)
	)
	bottle.Transparency = 0.3
	for _, x in { -32, 24 } do
		plant(area, Vector3.new(x, 0, 31))
	end
end

-- Builds the whole building under `parent` and returns its folder.
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
