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
local TowerShellBuilder = require(script.Parent.TowerShellBuilder)

local OfficeBuilder = {}

OfficeBuilder.FURNITURE_ATTRIBUTE = "Furniture"

-- Comfortable, darker "gamer room" palette: muted slate surfaces, warm dim
-- lights, thin coloured LED accents. Specs cap brightness (no glare).
local WALL_COLOR = Color3.fromRGB(78, 84, 104)
local WALL_THICKNESS = 1
local SLAB_COLOR = Color3.fromRGB(52, 56, 70)
local WOOD = Color3.fromRGB(150, 105, 70)
local METAL = Color3.fromRGB(120, 125, 135)
local DARK = Color3.fromRGB(40, 42, 50)
local LEAF = Color3.fromRGB(70, 160, 80)
local POT = Color3.fromRGB(190, 110, 70)
local PAPER = Color3.fromRGB(196, 192, 182)
local GLASS = Color3.fromRGB(170, 210, 235)
local LIGHT_COLOR = Color3.fromRGB(255, 236, 214) -- warm white (amber read olive under Future lighting)
local LIGHT_PANEL_COLOR = Color3.fromRGB(196, 196, 192) -- a pale diffuser, not an orange slab
local LIGHT_BRIGHTNESS = 0.7
local LED_GROUND = Color3.fromRGB(60, 190, 210) -- cool cyan accent strip
local LED_UPPER = Color3.fromRGB(150, 90, 220) -- purple accent strip
local LED_DEPARTMENT = Color3.fromRGB(230, 170, 60) -- amber accent strip (4th floor)
-- How much darker office carpets are than their configured tint.
local CARPET_DEEPEN = 0.4
local CORRIDOR_CARPET = Color3.fromRGB(46, 52, 68)
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

-- A soft (non-glowing) ceiling panel with a dim warm light under it.
local function ceilingLight(parent: Instance, position: Vector3, range: number): ()
	local panel = part(parent, "CeilingLight", Vector3.new(6, 0.3, 6), position, LIGHT_PANEL_COLOR)
	panel.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = LIGHT_COLOR
	light.Range = range
	light.Brightness = LIGHT_BRIGHTNESS
	light.Shadows = false
	light.Parent = panel
end

-- A thin, dim coloured LED strip along a ceiling edge (decoration only).
local function ledStrip(parent: Instance, length: number, position: Vector3, color: Color3): ()
	local strip =
		part(parent, "LedStrip", Vector3.new(length, 0.2, 0.2), position, color, Enum.Material.Neon)
	-- Future lighting makes Neon far brighter: keep strips faint.
	strip.Transparency = 0.7
	strip.CastShadow = false
	strip.CanCollide = false
	strip.CanQuery = false
	strip.CanTouch = false
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
		entry.CarpetColor:Lerp(Color3.new(0, 0, 0), CARPET_DEEPEN),
		Enum.Material.Carpet
	)
	walls(room, center)
	ceilingLight(room, center + Vector3.new(0, size.Y - 0.3, 0), 24)

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
		Enum.Material.Carpet
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
		Enum.Material.Carpet
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

		-- Corridor walls between the lobby and the building ends, both storeys,
		-- with a doorway on the ground floor into the podium room behind
		-- (Lib/TowerShellBuilder: the Break Room west, the Meeting Room east).
		local doorX = TowerShellBuilder.ROOM_DOOR_X
		local doorHalf = TowerShellBuilder.ROOM_DOOR_WIDTH / 2
		local doorHeight = ArenaConfig.DoorHeight
		for _, segment in
			{
				{ From = LOBBY.HalfWidth, To = doorX - doorHalf },
				{ From = doorX + doorHalf, To = half },
			}
		do
			local span = segment.To - segment.From
			part(
				area,
				"CorridorSouthWall",
				Vector3.new(span, roofY, WALL_THICKNESS),
				Vector3.new(side * (segment.From + span / 2), roofY / 2, CORRIDOR.MaxZ),
				WALL_COLOR
			)
		end
		part(
			area,
			"CorridorSouthWallLintel",
			Vector3.new(doorHalf * 2, roofY - doorHeight, WALL_THICKNESS),
			Vector3.new(side * doorX, doorHeight + (roofY - doorHeight) / 2, CORRIDOR.MaxZ),
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

	-- Lobby front: a glass wall between solid bands, facing the campus, with
	-- an open entrance in the middle (ArenaConfig.Campus) straight ahead of the
	-- spawn. Glass on both sides, a glass transom above the opening.
	local entrance = ArenaConfig.Campus.EntranceWidth
	local entranceHeight = ArenaConfig.Campus.EntranceHeight
	local sideWidth = LOBBY.HalfWidth - entrance / 2
	for _, side in { -1, 1 } do
		local sideX = side * (entrance / 2 + sideWidth / 2)
		part(
			area,
			"LobbyFrontLow",
			Vector3.new(sideWidth, 2, WALL_THICKNESS),
			Vector3.new(sideX, 1, southZ),
			WALL_COLOR
		)
		glass(
			area,
			"LobbyFrontGlass",
			Vector3.new(sideWidth, roofY - 6, 0.4),
			Vector3.new(sideX, 2 + (roofY - 6) / 2, southZ)
		)
		part(
			area,
			"EntranceFrame",
			Vector3.new(0.8, entranceHeight, WALL_THICKNESS + 0.2),
			Vector3.new(side * (entrance / 2 + 0.4), entranceHeight / 2, southZ),
			METAL,
			Enum.Material.Metal
		)
	end
	part(
		area,
		"LobbyFrontHigh",
		Vector3.new(LOBBY.HalfWidth * 2, 4, WALL_THICKNESS),
		Vector3.new(0, roofY - 2, southZ),
		WALL_COLOR
	)
	local transomHeight = roofY - 4 - entranceHeight
	glass(
		area,
		"EntranceTransom",
		Vector3.new(entrance, transomHeight, 0.4),
		Vector3.new(0, entranceHeight + transomHeight / 2, southZ)
	)
	-- Inside, over the opening, facing the lobby (-Z).
	local outside = part(
		area,
		"EntranceSign",
		Vector3.new(entrance, 2, 0.4),
		Vector3.new(0, entranceHeight + 1.2, southZ - 0.6),
		Color3.fromRGB(60, 70, 110)
	)
	sign(
		outside,
		Enum.NormalId.Front,
		"OUTSIDE: Garden - Coffee - Stress-Relief Zone",
		Color3.fromRGB(255, 220, 120)
	)

	buildStairs(area)

	-- Lights: corridors on both storeys, and the lobby atrium.
	for x = -68, 68, 34 do
		ceilingLight(area, Vector3.new(x, officeHeight - 0.3, corridorZ), 22)
		ceilingLight(area, Vector3.new(x, roofY - 0.3, corridorZ), 22)
	end
	for _, x in { -18, 18 } do
		ceilingLight(area, Vector3.new(x, roofY - 0.3, 18), 34)
	end
	-- Accent LED strips along both corridors' office-side ceiling edges.
	local stripZ = CORRIDOR.MinZ + 0.8
	ledStrip(area, half * 2 - 2, Vector3.new(0, officeHeight - 0.4, stripZ), LED_GROUND)
	ledStrip(area, half * 2 - 2, Vector3.new(0, roofY - 0.4, stripZ), LED_UPPER)

	-- Welcome sign over the corridor entrance, facing the spawn.
	local welcome = part(
		area,
		"WelcomeSign",
		Vector3.new(30, 4, 0.5),
		Vector3.new(0, 11, 1),
		Color3.fromRGB(35, 38, 48)
	)
	sign(
		welcome,
		Enum.NormalId.Back,
		"WHACK IT OUT!  Stress Relief Dept.",
		Color3.fromRGB(255, 170, 80)
	)
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

-- An elevator door on the west end wall's inner face, with a sign above it.
-- ExecutiveService adds the "Ride up" / "Ride down" prompts.
local function elevatorDoor(parent: Instance, name: string, center: Vector3, label: string): ()
	local door = part(parent, name, Vector3.new(0.4, 8, 6), center, METAL, Enum.Material.Metal)
	door.CanCollide = true
	local signPart = part(
		parent,
		name .. "Sign",
		Vector3.new(0.3, 1.6, 8),
		center + Vector3.new(0, 5, 0),
		Color3.fromRGB(60, 50, 40)
	)
	sign(signPart, Enum.NormalId.Right, label, Color3.fromRGB(255, 210, 120))
end

-- The CEO's suite: the whole 3rd floor over the offices and corridor.
local function buildExecutiveFloor(parent: Instance): ()
	local executive = ArenaConfig.Executive
	local floor = executive.FloorY
	local height = executive.CeilingY - floor
	local half = ArenaConfig.BuildingHalfWidth
	local northZ, southZ = executive.NorthZ, executive.SouthZ
	local depth = southZ - northZ
	local midZ = (southZ + northZ) / 2

	local suite = Instance.new("Model")
	suite.Name = "The CEO Office"
	suite.Parent = parent

	part(
		suite,
		"ExecutiveCarpet",
		Vector3.new(half * 2, 0.1, depth),
		Vector3.new(0, floor + 0.05, midZ),
		Color3.fromRGB(80, 40, 50),
		Enum.Material.Carpet
	)
	part(
		suite,
		"ExecutiveRoof",
		Vector3.new(half * 2, 1, depth),
		Vector3.new(0, executive.CeilingY + 0.5, midZ),
		SLAB_COLOR
	)

	-- North wall: a long window strip with the skyline view.
	local windowBottom, windowTop = 4, 10
	part(
		suite,
		"ExecutiveWallLow",
		Vector3.new(half * 2, windowBottom, WALL_THICKNESS),
		Vector3.new(0, floor + windowBottom / 2, northZ),
		WALL_COLOR
	)
	part(
		suite,
		"ExecutiveWallHigh",
		Vector3.new(half * 2, height - windowTop, WALL_THICKNESS),
		Vector3.new(0, floor + (windowTop + height) / 2, northZ),
		WALL_COLOR
	)
	glass(
		suite,
		"ExecutiveWindow",
		Vector3.new(half * 2, windowTop - windowBottom, 0.3),
		Vector3.new(0, floor + (windowBottom + windowTop) / 2, northZ)
	)
	part(
		suite,
		"ExecutiveWallSouth",
		Vector3.new(half * 2, height, WALL_THICKNESS),
		Vector3.new(0, floor + height / 2, southZ),
		WALL_COLOR
	)
	for _, side in { -1, 1 } do
		part(
			suite,
			"ExecutiveEndWall",
			Vector3.new(WALL_THICKNESS, height, depth),
			Vector3.new(side * half, floor + height / 2, midZ),
			WALL_COLOR
		)
	end

	for x = -60, 60, 30 do
		for _, z in { -40, -14 } do
			ceilingLight(suite, Vector3.new(x, executive.CeilingY - 0.3, z), 30)
		end
	end

	-- The CEO's desk faces into the room from the north wall.
	local deskAt = Vector3.new(0, floor, -46)
	local darkWood = Color3.fromRGB(95, 60, 40)
	furniture(
		part(suite, "CeoDesk", Vector3.new(16, 0.8, 5), deskAt + Vector3.new(0, 3.4, 0), darkWood)
	)
	furniture(
		part(
			suite,
			"CeoDeskFront",
			Vector3.new(16, 3, 0.5),
			deskAt + Vector3.new(0, 1.5, 2.2),
			darkWood
		)
	)
	local monitor = furniture(
		part(suite, "CeoMonitor", Vector3.new(5, 3, 0.3), deskAt + Vector3.new(0, 5.4, -1.5), DARK)
	)
	sign(monitor, Enum.NormalId.Back, "Q4: PANIC", Color3.fromRGB(255, 110, 110))
	furniture(
		part(
			suite,
			"CeoChairSeat",
			Vector3.new(4, 0.6, 4),
			deskAt + Vector3.new(0, 2, -4),
			Color3.fromRGB(70, 30, 30)
		)
	)
	furniture(
		part(
			suite,
			"CeoChairBack",
			Vector3.new(4, 6, 0.6),
			deskAt + Vector3.new(0, 5, -5.6),
			Color3.fromRGB(70, 30, 30)
		)
	)

	for _, x in { -30, 30 } do
		furniture(
			part(
				suite,
				"Bookshelf",
				Vector3.new(14, 9, 2),
				Vector3.new(x, floor + 4.5, northZ + 1.6),
				darkWood
			)
		)
	end
	local painting = furniture(
		part(
			suite,
			"Painting",
			Vector3.new(12, 6, 0.2),
			Vector3.new(40, floor + 7, southZ - 0.7),
			Color3.fromRGB(200, 170, 110)
		)
	)
	sign(painting, Enum.NormalId.Front, "EMPLOYEE OF THE MONTH: ME", Color3.fromRGB(70, 40, 20))
	local couch = Color3.fromRGB(90, 45, 55)
	furniture(
		part(suite, "CouchSeat", Vector3.new(3, 1.6, 10), Vector3.new(70, floor + 0.8, -26), couch)
	)
	furniture(
		part(suite, "CouchBack", Vector3.new(1, 2.4, 10), Vector3.new(72, floor + 2.4, -26), couch)
	)
	for _, at in
		{ Vector3.new(-80, floor, -48), Vector3.new(80, floor, -48), Vector3.new(80, floor, -4) }
	do
		plant(suite, at)
	end

	-- Elevator doors on the west end wall (the tower shaft): the 2nd and 3rd
	-- floors keep their door names; TowerService adds the floor-panel prompt.
	elevatorDoor(parent, "ElevatorUpDoor", executive.ElevatorUpDoor, "ELEVATOR · FLOOR 2")
	elevatorDoor(suite, "ElevatorDownDoor", executive.ElevatorDownDoor, "ELEVATOR · FLOOR 3")
end

-- The 4th floor (Department Heads, Phase 3a): corridor, walls, windows and
-- roof over the Executive Floor's footprint. The Principal offices are
-- built like every other office (ArenaConfig.Offices).
local function buildDepartmentFloor(parent: Instance): ()
	local department = ArenaConfig.DepartmentFloor
	local floor = department.FloorY
	local height = department.CeilingY - floor
	local half = ArenaConfig.BuildingHalfWidth
	local northZ, southZ = department.NorthZ, department.SouthZ
	local depth = southZ - northZ
	local midZ = (southZ + northZ) / 2
	local corridorDepth = CORRIDOR.MaxZ - CORRIDOR.MinZ
	local corridorZ = (CORRIDOR.MinZ + CORRIDOR.MaxZ) / 2

	local area = Instance.new("Model")
	area.Name = "Department Heads Floor"
	area.Parent = parent

	part(
		area,
		"DepartmentCorridorCarpet",
		Vector3.new(half * 2, 0.1, corridorDepth),
		Vector3.new(0, floor + 0.05, corridorZ),
		CORRIDOR_CARPET,
		Enum.Material.Carpet
	)
	part(
		area,
		"DepartmentRoof",
		Vector3.new(half * 2, 1, depth),
		Vector3.new(0, department.CeilingY + 0.5, midZ),
		SLAB_COLOR
	)
	-- South wall: a window strip over the campus, like the CEO's north view.
	local windowBottom, windowTop = 4, 10
	part(
		area,
		"DepartmentWallLow",
		Vector3.new(half * 2, windowBottom, WALL_THICKNESS),
		Vector3.new(0, floor + windowBottom / 2, southZ),
		WALL_COLOR
	)
	part(
		area,
		"DepartmentWallHigh",
		Vector3.new(half * 2, height - windowTop, WALL_THICKNESS),
		Vector3.new(0, floor + (windowTop + height) / 2, southZ),
		WALL_COLOR
	)
	glass(
		area,
		"DepartmentWindow",
		Vector3.new(half * 2, windowTop - windowBottom, 0.3),
		Vector3.new(0, floor + (windowBottom + windowTop) / 2, southZ)
	)
	for _, side in { -1, 1 } do
		part(
			area,
			"DepartmentEndWall",
			Vector3.new(WALL_THICKNESS, height, depth),
			Vector3.new(side * half, floor + height / 2, midZ),
			WALL_COLOR
		)
	end
	for x = -60, 60, 30 do
		ceilingLight(area, Vector3.new(x, department.CeilingY - 0.3, corridorZ), 22)
	end
	ledStrip(
		area,
		half * 2 - 2,
		Vector3.new(0, department.CeilingY - 0.4, CORRIDOR.MinZ + 0.6),
		LED_DEPARTMENT
	)
	for _, x in { -50, 50 } do
		plant(area, Vector3.new(x, floor, CORRIDOR.MaxZ - 2.5))
	end

	-- The floor's name, on the window wall above the glass, facing the corridor.
	local plate = part(
		area,
		"DepartmentSign",
		Vector3.new(30, 2.6, 0.4),
		Vector3.new(0, floor + 11.8, southZ - 0.8),
		Color3.fromRGB(60, 50, 40)
	)
	sign(plate, Enum.NormalId.Front, "FLOOR 4 · DEPARTMENT HEADS", Color3.fromRGB(255, 210, 120))

	local tower = ArenaConfig.Tower
	elevatorDoor(
		area,
		"ElevatorDepartmentDoor",
		Vector3.new(tower.DoorX, floor + 4, tower.DoorZ),
		"ELEVATOR · FLOOR 4"
	)
end

-- The tower elevator's ground-floor door (west end of the corridor) and a
-- sign in the lobby pointing to it.
local function buildGroundElevator(parent: Instance): ()
	local tower = ArenaConfig.Tower
	elevatorDoor(
		parent,
		"ElevatorGroundDoor",
		Vector3.new(tower.DoorX, 4, tower.DoorZ),
		"ELEVATOR · ALL FLOORS"
	)
	-- Hanging over the corridor just west of the lobby, readable from the lobby (+X face).
	local pointer = part(
		parent,
		"ElevatorPointer",
		Vector3.new(0.4, 2.2, 12),
		Vector3.new(-LOBBY.HalfWidth - 2, 11, (CORRIDOR.MinZ + CORRIDOR.MaxZ) / 2),
		Color3.fromRGB(60, 50, 40)
	)
	pointer.CanCollide = false
	sign(pointer, Enum.NormalId.Right, "← ELEVATOR · ALL FLOORS", Color3.fromRGB(255, 210, 120))
end

-- Builds the whole building under `parent` and returns its folder.
function OfficeBuilder.build(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Office"
	for _, entry in ArenaConfig.Offices do
		buildOffice(folder, entry)
	end
	buildCommonAreas(folder)
	buildExecutiveFloor(folder)
	buildDepartmentFloor(folder)
	buildGroundElevator(folder)
	TowerShellBuilder.build(folder)
	folder.Parent = parent
	return folder
end

return OfficeBuilder
