--!strict
--[[
	The Rooftop Lounge (5th floor, visual overhaul V1, docs/TOWER.md): an
	open-air deck on the Executive Floor's roof, inside the tower's parapet
	(Lib/TowerShellBuilder). Open to everyone by the tower elevator.

	  * An elevator house at the west end with the floor-5 door
	    (ElevatorRooftopDoor; TowerService adds its prompt).
	  * A wooden deck; a sofa corner with coffee tables and bean bags; a
	    coffee cart under a parasol; loungers with umbrellas; trees in
	    planters along the north edge; string lights; a telescope.
	  * Two boards with prompts: the Mission Board (MissionBoardPrompt, opens
	    Team Missions) and the Event Board (EventBoardPrompt, opens 🌟 Today).
	    The client opens the panels; nothing here changes game state.

	Everything is anchored; decoration that players don't stand on doesn't
	collide. Seats are plain parts (players walk round them).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)

local RooftopBuilder = {}

RooftopBuilder.MISSION_PROMPT = "MissionBoardPrompt"
RooftopBuilder.EVENT_PROMPT = "EventBoardPrompt"

local FLOOR = ArenaConfig.Rooftop.FloorY -- 60
local NORTH = ArenaConfig.Rooftop.NorthZ -- -52
local SOUTH = ArenaConfig.Rooftop.SouthZ -- 0
local HALF = ArenaConfig.BuildingHalfWidth -- 86
local TOWER = ArenaConfig.Tower

local DECK_COLOR = Color3.fromRGB(118, 88, 62)
local STONE = Color3.fromRGB(72, 76, 88)
local METAL = Color3.fromRGB(92, 98, 110)
local DARK = Color3.fromRGB(40, 42, 50)
local LEAF = Color3.fromRGB(70, 150, 80)
local TRUNK = Color3.fromRGB(110, 80, 55)
local SOFA = Color3.fromRGB(70, 110, 160)
local CUSHION = Color3.fromRGB(235, 200, 120)
local BULB = Color3.fromRGB(255, 220, 150)
local SIGN_TEXT = Color3.fromRGB(255, 205, 110)

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

local function decor(p: Part): Part
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function signText(p: BasePart, face: Enum.NormalId, text: string): ()
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = SIGN_TEXT
	label.Text = text
	label.Parent = gui
end

local function ball(
	parent: Instance,
	name: string,
	diameter: number,
	position: Vector3,
	color: Color3,
	material: Enum.Material?
): Part
	local p = part(parent, name, Vector3.one * diameter, position, color, material)
	p.Shape = Enum.PartType.Ball
	return p
end

local function tree(parent: Instance, x: number, z: number): ()
	part(
		parent,
		"TreePlanter",
		Vector3.new(5, 2, 5),
		Vector3.new(x, FLOOR + 1, z),
		STONE,
		Enum.Material.Concrete
	)
	decor(
		part(
			parent,
			"TreeTrunk",
			Vector3.new(0.8, 6, 0.8),
			Vector3.new(x, FLOOR + 5, z),
			TRUNK,
			Enum.Material.Wood
		)
	)
	decor(ball(parent, "TreeLeaves", 6, Vector3.new(x, FLOOR + 9, z), LEAF, Enum.Material.Grass))
end

local function sofa(parent: Instance, center: Vector3, length: number, facingNorth: boolean): ()
	local back = if facingNorth then 1.6 else -1.6
	part(
		parent,
		"SofaSeat",
		Vector3.new(length, 1.6, 3.2),
		center + Vector3.new(0, 0.8, 0),
		SOFA,
		Enum.Material.Fabric
	)
	part(
		parent,
		"SofaBack",
		Vector3.new(length, 2.6, 0.9),
		center + Vector3.new(0, 2.4, back),
		SOFA,
		Enum.Material.Fabric
	)
	for i = -1, 1, 2 do
		decor(
			part(
				parent,
				"SofaCushion",
				Vector3.new(1.6, 1.6, 0.5),
				center + Vector3.new(i * (length / 2 - 1.5), 2.3, back * 0.6),
				CUSHION,
				Enum.Material.Fabric
			)
		)
	end
end

local function umbrella(parent: Instance, x: number, z: number, color: Color3): ()
	decor(
		part(
			parent,
			"UmbrellaPole",
			Vector3.new(0.3, 8, 0.3),
			Vector3.new(x, FLOOR + 4, z),
			METAL,
			Enum.Material.Metal
		)
	)
	local canopy = decor(
		part(
			parent,
			"UmbrellaCanopy",
			Vector3.new(0.6, 9, 9),
			Vector3.new(x, FLOOR + 8, z),
			color,
			Enum.Material.Fabric
		)
	)
	canopy.Shape = Enum.PartType.Cylinder
	canopy.Orientation = Vector3.new(0, 0, 90)
end

local function addPrompt(target: BasePart, name: string, objectText: string, actionText: string): ()
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ObjectText = objectText
	prompt.ActionText = actionText
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = target
end

-- The elevator house at the west end: three walls, a roof, the door and a sign.
local function buildElevatorHouse(parent: Instance): ()
	local minX, maxX = -HALF, -72
	local minZ, maxZ = TOWER.DoorZ - 7, TOWER.DoorZ + 7
	local height = 10
	local midX = (minX + maxX) / 2
	part(
		parent,
		"HeadhouseWall",
		Vector3.new(1, height, maxZ - minZ),
		Vector3.new(minX, FLOOR + height / 2, (minZ + maxZ) / 2),
		STONE,
		Enum.Material.Concrete
	)
	for _, z in { minZ, maxZ } do
		part(
			parent,
			"HeadhouseWall",
			Vector3.new(maxX - minX, height, 1),
			Vector3.new(midX, FLOOR + height / 2, z),
			STONE,
			Enum.Material.Concrete
		)
	end
	part(
		parent,
		"HeadhouseSlab",
		Vector3.new(maxX - minX + 2, 1, maxZ - minZ + 2),
		Vector3.new(midX, FLOOR + height + 0.5, (minZ + maxZ) / 2),
		STONE,
		Enum.Material.Concrete
	)
	local door = part(
		parent,
		"ElevatorRooftopDoor",
		Vector3.new(0.4, 8, 6),
		Vector3.new(TOWER.DoorX, FLOOR + 4, TOWER.DoorZ),
		METAL,
		Enum.Material.Metal
	)
	door.CanCollide = true
	local plate = part(
		parent,
		"HeadhouseSign",
		Vector3.new(0.4, 2.2, 12),
		Vector3.new(maxX + 0.3, FLOOR + height - 1.6, TOWER.DoorZ),
		Color3.fromRGB(35, 38, 48),
		Enum.Material.Metal
	)
	signText(plate, Enum.NormalId.Right, "FLOOR 5 · ROOFTOP LOUNGE")
end

local function buildLounge(parent: Instance): ()
	-- Sofa corner west of the middle, round two low tables on a rug.
	local center = Vector3.new(-40, FLOOR, -26)
	decor(
		part(
			parent,
			"LoungeRug",
			Vector3.new(20, 0.1, 14),
			center + Vector3.new(0, 0.12, 0),
			Color3.fromRGB(150, 95, 70),
			Enum.Material.Carpet
		)
	)
	sofa(parent, center + Vector3.new(0, 0, -7), 14, false)
	sofa(parent, center + Vector3.new(0, 0, 7), 14, true)
	for _, dx in { -3.5, 3.5 } do
		part(
			parent,
			"CoffeeTable",
			Vector3.new(5, 1.4, 3),
			center + Vector3.new(dx, 0.7, 0),
			Color3.fromRGB(95, 65, 45),
			Enum.Material.Wood
		)
	end
	for i, at in
		{ Vector3.new(-56, FLOOR, -30), Vector3.new(-56, FLOOR, -22), Vector3.new(-24, FLOOR, -30) }
	do
		local colors = {
			Color3.fromRGB(230, 110, 90),
			Color3.fromRGB(90, 170, 200),
			Color3.fromRGB(240, 200, 90),
		}
		ball(parent, "BeanBag", 3.2, at + Vector3.new(0, 1.4, 0), colors[i], Enum.Material.Fabric)
	end

	-- Coffee cart in the middle under a parasol.
	local cart = Vector3.new(0, FLOOR, -40)
	part(
		parent,
		"CoffeeCart",
		Vector3.new(8, 3.6, 3),
		cart + Vector3.new(0, 1.8, 0),
		Color3.fromRGB(150, 105, 70),
		Enum.Material.Wood
	)
	part(
		parent,
		"CoffeeCartTop",
		Vector3.new(8.4, 0.3, 3.4),
		cart + Vector3.new(0, 3.75, 0),
		Color3.fromRGB(60, 62, 70),
		Enum.Material.Marble
	)
	local cartSign = part(
		parent,
		"CoffeeCartSign",
		Vector3.new(8, 1.4, 0.3),
		cart + Vector3.new(0, 2.2, 1.65),
		Color3.fromRGB(35, 38, 48)
	)
	signText(cartSign, Enum.NormalId.Back, "☕ ROOFTOP COFFEE")
	umbrella(parent, 0, -40, Color3.fromRGB(200, 90, 70))
	for _, dx in { -9, 9 } do
		local stool = part(
			parent,
			"BarStool",
			Vector3.new(1.6, 2.6, 1.6),
			cart + Vector3.new(dx, 1.3, 3.5),
			DARK,
			Enum.Material.Metal
		)
		stool.Shape = Enum.PartType.Cylinder
		stool.Orientation = Vector3.new(0, 0, 90)
	end

	-- Loungers with umbrellas on the east side.
	for i, x in { 30, 42, 54, 66 } do
		local at = Vector3.new(x, FLOOR, -36)
		part(
			parent,
			"LoungerBed",
			Vector3.new(3, 0.8, 8),
			at + Vector3.new(0, 1, 0),
			Color3.fromRGB(235, 235, 230),
			Enum.Material.Fabric
		)
		local rest = part(
			parent,
			"LoungerBack",
			Vector3.new(3, 0.6, 3.4),
			Vector3.zero,
			Color3.fromRGB(235, 235, 230),
			Enum.Material.Fabric
		)
		rest.CFrame = CFrame.new(at + Vector3.new(0, 2, -4.6)) * CFrame.Angles(math.rad(50), 0, 0)
		if i % 2 == 1 then
			umbrella(parent, x + 6, -36, Color3.fromRGB(80, 140, 200))
		end
	end

	-- Trees along the north edge, and a telescope looking north (the Recreation Center).
	for x = -60, 72, 22 do
		tree(parent, x, NORTH + 4)
	end
	local scope = part(
		parent,
		"Telescope",
		Vector3.new(0.8, 0.8, 4),
		Vector3.zero,
		METAL,
		Enum.Material.Metal
	)
	scope.CFrame = CFrame.new(Vector3.new(76, FLOOR + 4.5, -44)) * CFrame.Angles(math.rad(20), 0, 0)
	decor(
		part(
			parent,
			"TelescopeStand",
			Vector3.new(0.4, 4, 0.4),
			Vector3.new(76, FLOOR + 2, -44),
			DARK,
			Enum.Material.Metal
		)
	)
end

-- String lights: two lines of bulbs between posts over the deck.
local function buildStringLights(parent: Instance): ()
	for _, z in { -14, -32 } do
		local fromX, toX = -66, 74
		for _, x in { fromX, toX } do
			decor(
				part(
					parent,
					"LightPost",
					Vector3.new(0.5, 11, 0.5),
					Vector3.new(x, FLOOR + 5.5, z),
					DARK,
					Enum.Material.Metal
				)
			)
		end
		decor(
			part(
				parent,
				"LightCable",
				Vector3.new(toX - fromX, 0.1, 0.1),
				Vector3.new((fromX + toX) / 2, FLOOR + 10.5, z),
				DARK
			)
		)
		for x = fromX + 4, toX - 4, 5 do
			local bulb = decor(
				ball(
					parent,
					"LightBulb",
					0.3,
					Vector3.new(x, FLOOR + 10.2, z),
					BULB,
					Enum.Material.Neon
				)
			)
			bulb.Transparency = 0.3
		end
	end
	-- A few real lights so the deck isn't dark at dusk.
	for _, x in { -30, 10, 50 } do
		local holder = decor(
			part(
				parent,
				"DeckLightHolder",
				Vector3.new(0.3, 0.3, 0.3),
				Vector3.new(x, FLOOR + 10, -23),
				DARK
			)
		)
		local light = Instance.new("PointLight")
		light.Color = BULB
		light.Range = 24
		light.Brightness = 0.6
		light.Shadows = false
		light.Parent = holder
	end
end

-- The Mission Board and the Event Board, side by side near the south parapet, facing the deck.
local function buildBoards(parent: Instance): ()
	for _, board in
		{
			{
				X = -18,
				Name = "MissionBoard",
				Text = "🤝 MISSION BOARD\nTeam up and clear a mission",
				Prompt = RooftopBuilder.MISSION_PROMPT,
				Object = "Mission Board",
				Action = "See missions",
			},
			{
				X = 18,
				Name = "EventBoard",
				Text = "🌟 EVENT BOARD\nToday's event and your goals",
				Prompt = RooftopBuilder.EVENT_PROMPT,
				Object = "Event Board",
				Action = "See today's event",
			},
		}
	do
		local panel = part(
			parent,
			board.Name,
			Vector3.new(14, 7, 0.6),
			Vector3.new(board.X, FLOOR + 5.5, SOUTH - 5),
			Color3.fromRGB(35, 38, 48),
			Enum.Material.Metal
		)
		signText(panel, Enum.NormalId.Front, board.Text)
		for _, dx in { -6, 6 } do
			part(
				parent,
				board.Name .. "Leg",
				Vector3.new(0.5, 2, 0.5),
				Vector3.new(board.X + dx, FLOOR + 1, SOUTH - 5),
				METAL,
				Enum.Material.Metal
			)
		end
		addPrompt(panel, board.Prompt, board.Object, board.Action)
	end
end

function RooftopBuilder.build(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Rooftop Lounge"
	-- The deck finish over the Executive Floor's roof slab.
	part(
		model,
		"SkyDeck",
		Vector3.new(HALF * 2 - 1, 0.1, SOUTH - NORTH - 1),
		Vector3.new(0, FLOOR + 0.05, (NORTH + SOUTH) / 2),
		DECK_COLOR,
		Enum.Material.WoodPlanks
	)
	buildElevatorHouse(model)
	buildLounge(model)
	buildStringLights(model)
	buildBoards(model)
	model.Parent = parent
	return model
end

return RooftopBuilder
