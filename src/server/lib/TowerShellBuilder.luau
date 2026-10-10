--!strict
--[[
	The headquarters' outside and the podium rooms (visual overhaul V1a,
	docs/VISUAL_GAP_REVIEW.md, docs/TOWER.md). Built after the interior
	(Lib/OfficeBuilder) and only around it: nothing here stands where a
	player walks inside, so every interior position and spec stays as it was.

	  * Tower block (z -52..0, four storeys and a roof at y 60): a glass
	    curtain wall on the north, east and west faces and on the south face
	    above the podium, slim metal fins every bay, a concrete band at every
	    floor and a parapet with the lit "WHACK IT OUT! HQ" crown sign.
	  * Podium (z 0..34, the double-height lobby and its two wings): glass
	    walls close the wings, which become the Break Room (west) and the
	    Meeting Room (east), entered from the ground corridor
	    (OfficeBuilder leaves a doorway in each corridor wall).
	  * Entrance canopy with the HQ name over the lobby's open entrance.

	Glass is one sheet per face per storey; the bay rhythm comes from the
	fins, so the whole shell is a few hundred anchored parts and no lights
	outside the rooms. Materials come from the built-in set (Glass,
	Concrete, Metal, Wood, Fabric); art can later be swapped for meshes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)

local TowerShellBuilder = {}

local HALF = ArenaConfig.BuildingHalfWidth -- 86
local NORTH = ArenaConfig.BuildingNorthZ -- -52
local SOUTH = ArenaConfig.BuildingSouthZ -- 34
local TOWER_SOUTH = 0 -- the tower block's south face (over the podium)
local PODIUM_TOP = ArenaConfig.RoofY + 1 -- 30
local TOWER_TOP = ArenaConfig.Rooftop.FloorY -- 60, the roof deck
local PARAPET = 3
-- Storey floor levels, bottom first.
local STOREYS = {
	0,
	ArenaConfig.UpperFloorY,
	ArenaConfig.DepartmentFloor.FloorY,
	ArenaConfig.Executive.FloorY,
}
table.sort(STOREYS)
local LOBBY_HALF = 36
local OUT = 1 -- the curtain wall stands this far outside the walls
local BAY = 8.6
local BAND = 1.2

local GLASS_COLOR = Color3.fromRGB(105, 150, 185)
local BAND_COLOR = Color3.fromRGB(72, 76, 88)
local FIN_COLOR = Color3.fromRGB(92, 98, 110)
local CANOPY_COLOR = Color3.fromRGB(100, 103, 112) -- muted (OfficeBuilder eye-comfort spec)
local SIGN_TEXT_COLOR = Color3.fromRGB(255, 205, 110)
local WOOD = Color3.fromRGB(150, 105, 70)
local DARK = Color3.fromRGB(40, 42, 50)
local LIGHT_COLOR = Color3.fromRGB(255, 236, 214)

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

local function glassSheet(parent: Instance, size: Vector3, position: Vector3): Part
	local p = part(parent, "CurtainGlass", size, position, GLASS_COLOR, Enum.Material.Glass)
	p.Transparency = 0.35
	p.Reflectance = 0.12
	p.CastShadow = false
	return p
end

-- Decoration only: no collisions, raycasts or touches.
local function decor(p: Part): Part
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function signText(
	p: BasePart,
	face: Enum.NormalId,
	text: string,
	color: Color3,
	font: Enum.Font?
): ()
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Brightness = 1.5
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = font or Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
end

local function pendantLight(parent: Instance, position: Vector3): ()
	-- A flat round shade (the cylinder's axis turned upright: 1 tall, 2.4
	-- across) hanging on a thin cord.
	local shade = decor(
		part(parent, "PendantShade", Vector3.new(1, 2.4, 2.4), position, DARK, Enum.Material.Metal)
	)
	shade.Shape = Enum.PartType.Cylinder
	shade.Orientation = Vector3.new(0, 0, 90)
	decor(
		part(
			parent,
			"PendantCord",
			Vector3.new(0.1, 1.5, 0.1),
			position + Vector3.new(0, 1.25, 0),
			DARK,
			Enum.Material.Metal
		)
	)
	local light = Instance.new("PointLight")
	light.Color = LIGHT_COLOR
	light.Range = 18
	light.Brightness = 0.8
	light.Shadows = false
	light.Parent = shade
end

--[[
	One facade: a run of glass between `fromY` and `toY` along an axis, with
	a band at every storey line inside that height and fins every bay.
	`along` = "X" (faces north/south, fixed `at` = z) or "Z" (faces east/west,
	fixed `at` = x); `from`/`to` = the span along that axis; `outward` = +1/-1.
]]
local function facade(
	parent: Instance,
	along: string,
	at: number,
	from: number,
	to: number,
	fromY: number,
	toY: number,
	outward: number
): ()
	local length = to - from
	local mid = (from + to) / 2
	local function at3(u: number, y: number, depth: number): Vector3
		if along == "X" then
			return Vector3.new(u, y, at + outward * depth)
		end
		return Vector3.new(at + outward * depth, y, u)
	end
	local function size3(u: number, y: number, depth: number): Vector3
		return if along == "X" then Vector3.new(u, y, depth) else Vector3.new(depth, y, u)
	end
	-- Storey lines inside this height, plus the top.
	local lines: { number } = {}
	for _, y in STOREYS do
		if y >= fromY and y < toY then
			table.insert(lines, y)
		end
	end
	table.insert(lines, toY)
	for index = 1, #lines - 1 do
		local bottom, top = lines[index], lines[index + 1]
		glassSheet(parent, size3(length, top - bottom - BAND, 0.3), at3(mid, (bottom + top) / 2, 0))
	end
	for _, y in lines do
		part(
			parent,
			"FacadeBand",
			size3(length + 0.8, BAND, 1.2),
			at3(mid, y, 0.2),
			BAND_COLOR,
			Enum.Material.Concrete
		)
	end
	local bays = math.max(1, math.floor(length / BAY + 0.5))
	for index = 0, bays do
		local u = from + length * index / bays
		decor(
			part(
				parent,
				"Fin",
				size3(0.35, toY - fromY, 1.1),
				at3(u, (fromY + toY) / 2, 0.55),
				FIN_COLOR,
				Enum.Material.Metal
			)
		)
	end
end

local function buildShell(parent: Instance): ()
	local shell = Instance.new("Model")
	shell.Name = "Curtain Wall"
	shell.Parent = parent

	-- Tower block: north, east, west faces full height; south face above the podium.
	facade(shell, "X", NORTH - OUT, -HALF - OUT, HALF + OUT, 0, TOWER_TOP, -1)
	for _, side in { -1, 1 } do
		facade(shell, "Z", side * (HALF + OUT), NORTH - OUT, TOWER_SOUTH, 0, TOWER_TOP, side)
		-- Podium sides (the wings' outer walls).
		facade(shell, "Z", side * (HALF + OUT), TOWER_SOUTH, SOUTH + OUT, 0, PODIUM_TOP, side)
	end
	facade(shell, "X", TOWER_SOUTH + OUT, -HALF - OUT, HALF + OUT, PODIUM_TOP, TOWER_TOP, 1)
	-- Podium front beside the lobby (the lobby keeps its own glass front).
	for _, side in { -1, 1 } do
		local inner, outer = side * LOBBY_HALF, side * (HALF + OUT)
		facade(
			shell,
			"X",
			SOUTH + OUT,
			math.min(inner, outer),
			math.max(inner, outer),
			0,
			PODIUM_TOP,
			1
		)
	end

	-- Parapets: a low solid rim round the tower roof and the podium roof.
	local towerDepth = TOWER_SOUTH - NORTH + 2 * OUT
	local towerMidZ = (TOWER_SOUTH + NORTH) / 2
	for _, z in { NORTH - OUT, TOWER_SOUTH + OUT } do
		part(
			shell,
			"ParapetWall",
			Vector3.new(2 * (HALF + OUT), PARAPET, 1),
			Vector3.new(0, TOWER_TOP + PARAPET / 2, z),
			BAND_COLOR,
			Enum.Material.Concrete
		)
	end
	for _, side in { -1, 1 } do
		part(
			shell,
			"ParapetWall",
			Vector3.new(1, PARAPET, towerDepth),
			Vector3.new(side * (HALF + OUT), TOWER_TOP + PARAPET / 2, towerMidZ),
			BAND_COLOR,
			Enum.Material.Concrete
		)
	end
	part(
		shell,
		"PodiumParapetWall",
		Vector3.new(2 * (HALF + OUT), 1.5, 1),
		Vector3.new(0, PODIUM_TOP + 0.75, SOUTH + OUT),
		BAND_COLOR,
		Enum.Material.Concrete
	)

	-- The crown sign: big letters on a frame over the tower's front, lit, facing the campus.
	local crown = part(
		shell,
		"CrownSign",
		Vector3.new(70, 8, 1),
		Vector3.new(0, TOWER_TOP + PARAPET + 4.5, TOWER_SOUTH + OUT - 0.5),
		Color3.fromRGB(35, 38, 48),
		Enum.Material.Metal
	)
	signText(crown, Enum.NormalId.Back, "WHACK IT OUT! HQ", SIGN_TEXT_COLOR)
	for _, x in { -30, 30 } do
		part(
			shell,
			"CrownPost",
			Vector3.new(1, PARAPET + 1, 1),
			Vector3.new(x, TOWER_TOP + PARAPET + 0.5 - 1, TOWER_SOUTH + OUT - 0.5),
			FIN_COLOR,
			Enum.Material.Metal
		)
	end
end

local function buildCanopy(parent: Instance): ()
	local canopy = Instance.new("Model")
	canopy.Name = "Entrance Canopy"
	canopy.Parent = parent
	local depth = 10
	local width = 26
	local z = SOUTH + OUT + depth / 2
	local slab = part(
		canopy,
		"CanopySlab",
		Vector3.new(width, 1, depth),
		Vector3.new(0, 12.5, z),
		CANOPY_COLOR,
		Enum.Material.Concrete
	)
	slab.CastShadow = true
	local fascia = part(
		canopy,
		"CanopyFascia",
		Vector3.new(width, 2, 0.4),
		Vector3.new(0, 12.5, z + depth / 2 + 0.2),
		Color3.fromRGB(35, 38, 48),
		Enum.Material.Metal
	)
	signText(fascia, Enum.NormalId.Back, "WHACK IT OUT!  HEADQUARTERS", SIGN_TEXT_COLOR)
	for _, x in { -width / 2 + 1, width / 2 - 1 } do
		part(
			canopy,
			"CanopyColumn",
			Vector3.new(0.8, 12, 0.8),
			Vector3.new(x, 6, z + depth / 2 - 1),
			FIN_COLOR,
			Enum.Material.Metal
		)
	end
	-- (The plaza's own planters stand either side of the steps.)
end

-- A podium room: a lowered ceiling at the ground storey's height, a floor
-- finish and a few lights. `minX`..`maxX` along x, the whole wing depth.
local function roomShell(
	parent: Instance,
	name: string,
	minX: number,
	maxX: number,
	floorColor: Color3,
	floorMaterial: Enum.Material
): Model
	local room = Instance.new("Model")
	room.Name = name
	room.Parent = parent
	local width, midX = maxX - minX, (minX + maxX) / 2
	local depth, midZ = SOUTH - TOWER_SOUTH, (SOUTH + TOWER_SOUTH) / 2
	part(
		room,
		"RoomFloorCarpet",
		Vector3.new(width, 0.1, depth),
		Vector3.new(midX, 0.05, midZ),
		floorColor,
		floorMaterial
	)
	part(
		room,
		"RoomCeilingSlab",
		Vector3.new(width, 1, depth),
		Vector3.new(midX, 14.5, midZ),
		BAND_COLOR,
		Enum.Material.Concrete
	)
	for _, offset in { -width / 4, width / 4 } do
		for _, dz in { -depth / 4, depth / 4 } do
			pendantLight(room, Vector3.new(midX + offset, 12.5, midZ + dz))
		end
	end
	local plate = part(
		room,
		"RoomSign",
		Vector3.new(10, 1.6, 0.3),
		Vector3.new(midX, 11.5, TOWER_SOUTH + 0.8),
		Color3.fromRGB(60, 50, 40)
	)
	signText(plate, Enum.NormalId.Back, name, SIGN_TEXT_COLOR)
	return room
end

local function chair(parent: Instance, at: Vector3, facing: number, color: Color3): ()
	local cf = CFrame.new(at) * CFrame.Angles(0, math.rad(facing), 0)
	local seat =
		part(parent, "ChairSeat", Vector3.new(2, 0.4, 2), Vector3.zero, color, Enum.Material.Fabric)
	seat.CFrame = cf * CFrame.new(0, 1.6, 0)
	local back =
		part(parent, "ChairBack", Vector3.new(2, 2, 0.3), Vector3.zero, color, Enum.Material.Fabric)
	back.CFrame = cf * CFrame.new(0, 2.8, 0.9)
	local leg = part(
		parent,
		"ChairLeg",
		Vector3.new(0.3, 1.4, 0.3),
		Vector3.zero,
		DARK,
		Enum.Material.Metal
	)
	leg.CFrame = cf * CFrame.new(0, 0.7, 0)
end

local function plant(parent: Instance, at: Vector3): ()
	part(
		parent,
		"PlantPot",
		Vector3.new(2, 2, 2),
		at + Vector3.new(0, 1, 0),
		Color3.fromRGB(80, 84, 96),
		Enum.Material.Concrete
	)
	local leaves = part(
		parent,
		"PlantLeaves",
		Vector3.new(4, 4, 4),
		at + Vector3.new(0, 3.6, 0),
		Color3.fromRGB(70, 150, 80),
		Enum.Material.Grass
	)
	leaves.Shape = Enum.PartType.Ball
end

-- West wing: a break room with a coffee bar, tables and a sofa corner.
local function buildBreakRoom(parent: Instance): ()
	local room = roomShell(
		parent,
		"Break Room",
		-HALF,
		-LOBBY_HALF,
		Color3.fromRGB(120, 95, 70),
		Enum.Material.WoodPlanks
	)
	-- Coffee bar along the outer (west) wall.
	part(
		room,
		"CoffeeCounter",
		Vector3.new(3, 3.6, 18),
		Vector3.new(-HALF + 2.5, 1.8, 17),
		WOOD,
		Enum.Material.Wood
	)
	part(
		room,
		"CoffeeCounterTop",
		Vector3.new(3.4, 0.3, 18.4),
		Vector3.new(-HALF + 2.5, 3.75, 17),
		Color3.fromRGB(60, 62, 70),
		Enum.Material.Marble
	)
	local machine = part(
		room,
		"CoffeeMachine",
		Vector3.new(2, 2.4, 2),
		Vector3.new(-HALF + 2.5, 5.1, 12),
		DARK,
		Enum.Material.Metal
	)
	signText(machine, Enum.NormalId.Right, "☕", SIGN_TEXT_COLOR)
	part(
		room,
		"Fridge",
		Vector3.new(3, 7, 3),
		Vector3.new(-HALF + 2.5, 3.5, 29),
		Color3.fromRGB(150, 155, 165),
		Enum.Material.Metal
	)
	-- Round tables with chairs.
	for _, at in
		{
			Vector3.new(-70, 0, 10),
			Vector3.new(-56, 0, 10),
			Vector3.new(-70, 0, 24),
			Vector3.new(-56, 0, 24),
		}
	do
		local top = part(
			room,
			"TableTop",
			Vector3.new(0.3, 5, 5),
			at + Vector3.new(0, 3, 0),
			WOOD,
			Enum.Material.Wood
		)
		top.Shape = Enum.PartType.Cylinder
		top.Orientation = Vector3.new(0, 0, 90)
		part(
			room,
			"TableLeg",
			Vector3.new(0.5, 3, 0.5),
			at + Vector3.new(0, 1.5, 0),
			DARK,
			Enum.Material.Metal
		)
		chair(room, at + Vector3.new(0, 0, -3.5), 180, Color3.fromRGB(200, 120, 70))
		chair(room, at + Vector3.new(0, 0, 3.5), 0, Color3.fromRGB(200, 120, 70))
	end
	-- Sofa corner by the corridor door side.
	local sofa = Color3.fromRGB(70, 110, 160)
	part(
		room,
		"SofaSeat",
		Vector3.new(10, 1.6, 3.4),
		Vector3.new(-45, 0.8, 30),
		sofa,
		Enum.Material.Fabric
	)
	part(
		room,
		"SofaBack",
		Vector3.new(10, 2.6, 1),
		Vector3.new(-45, 2.4, 32.2),
		sofa,
		Enum.Material.Fabric
	)
	part(
		room,
		"Rug",
		Vector3.new(12, 0.1, 8),
		Vector3.new(-45, 0.12, 25),
		Color3.fromRGB(150, 90, 70),
		Enum.Material.Carpet
	)
	plant(room, Vector3.new(-40, 0, 4))
	plant(room, Vector3.new(-82, 0, 4))
end

-- East wing: a meeting room with a long table, a screen and a whiteboard.
local function buildMeetingRoom(parent: Instance): ()
	local room = roomShell(
		parent,
		"Meeting Room",
		LOBBY_HALF,
		HALF,
		Color3.fromRGB(70, 80, 105),
		Enum.Material.Carpet
	)
	local center = Vector3.new(61, 0, 18)
	part(
		room,
		"MeetingTable",
		Vector3.new(26, 0.4, 7),
		center + Vector3.new(0, 3, 0),
		WOOD,
		Enum.Material.Wood
	)
	for _, x in { -11, 11 } do
		part(
			room,
			"MeetingTableLeg",
			Vector3.new(1, 3, 5),
			center + Vector3.new(x, 1.5, 0),
			DARK,
			Enum.Material.Metal
		)
	end
	for i = -2, 2 do
		chair(room, center + Vector3.new(i * 5, 0, -5.5), 180, Color3.fromRGB(60, 65, 80))
		chair(room, center + Vector3.new(i * 5, 0, 5.5), 0, Color3.fromRGB(60, 65, 80))
	end
	local screen = part(
		room,
		"MeetingScreen",
		Vector3.new(0.3, 7, 12),
		Vector3.new(HALF - 1.5, 7, 18),
		DARK,
		Enum.Material.Glass
	)
	signText(
		screen,
		Enum.NormalId.Left,
		"Q3 SYNERGY ALIGNMENT\n(this could have been an email)",
		Color3.fromRGB(150, 220, 255),
		Enum.Font.GothamBold
	)
	local board = part(
		room,
		"Whiteboard",
		Vector3.new(14, 6, 0.3),
		Vector3.new(61, 6, SOUTH - 1.2),
		Color3.fromRGB(220, 222, 228)
	)
	signText(
		board,
		Enum.NormalId.Front,
		"AGENDA: 1. Coffee  2. More coffee  3. Relax",
		Color3.fromRGB(40, 90, 200),
		Enum.Font.GothamBold
	)
	plant(room, Vector3.new(40, 0, 30))
	plant(room, Vector3.new(82, 0, 4))
end

function TowerShellBuilder.build(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Tower Shell"
	buildShell(folder)
	buildCanopy(folder)
	buildBreakRoom(folder)
	buildMeetingRoom(folder)
	folder.Parent = parent
	return folder
end

-- For specs: the doorway from the ground corridor into each podium room.
TowerShellBuilder.ROOM_DOOR_X = 61
TowerShellBuilder.ROOM_DOOR_WIDTH = 8

return TowerShellBuilder
