--!strict
--[[
	The outdoor campus around the office (ArenaConfig.Campus): a funny
	corporate stress-relief facility, not an arena.

	  Front Plaza        paved, benches, planters, lamp posts, signpost
	  Walkways           entrance to the zone, garden to coffee corner, and a
	                     loop around the building (terrain paint, no parts)
	  Relaxation Garden  west: soft grass, a shallow pond, benches, flower beds
	  Coffee Corner      east: patio, coffee kiosk, picnic tables, vending machine
	  Stress-Relief Zone south: sand garden, bean bags, a giant stress ball

	Grounds and paths are Terrain materials (paint()), so they cost no parts.
	Props are small Models built once as templates and cloned into place
	(build()), every part anchored and grouped in one folder per area. Props are
	tagged DECOR_ATTRIBUTE and kept off every walkway (specs). Invisible walls
	and a low hedge mark the boundary, so nobody walks off the grounds.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)

local CampusBuilder = {}

CampusBuilder.DECOR_ATTRIBUTE = "Decor"
CampusBuilder.BOUNDARY_NAME = "BoundaryWall"

local CAMPUS = ArenaConfig.Campus
local GROUND = CAMPUS.GroundY

local WOOD = Color3.fromRGB(150, 105, 70)
local DARK_WOOD = Color3.fromRGB(110, 75, 45)
local METAL = Color3.fromRGB(110, 115, 125)
local LEAF = Color3.fromRGB(70, 150, 70)
local HEDGE = Color3.fromRGB(60, 130, 65)
local POT = Color3.fromRGB(190, 110, 70)
local STONE = Color3.fromRGB(150, 150, 145)
local LAMP = Color3.fromRGB(255, 220, 160)
local SIGN = Color3.fromRGB(60, 70, 110)
local SIGN_TEXT = Color3.fromRGB(255, 230, 150)

-- Helpers ------------------------------------------------------------------

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
	p.Parent = parent
	return p
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

-- A cylinder standing upright (its length runs along X, so turn it).
local function upright(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(90))
end

local function label(p: BasePart, face: Enum.NormalId, text: string): ()
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.6
	gui.Parent = p
	local text_ = Instance.new("TextLabel")
	text_.BackgroundTransparency = 1
	text_.Size = UDim2.fromScale(1, 1)
	text_.Font = Enum.Font.FredokaOne
	text_.TextScaled = true
	text_.TextWrapped = true
	text_.TextColor3 = SIGN_TEXT
	text_.Text = text
	text_.Parent = gui
end

-- A prop template: a Model whose pivot is the centre of its footprint on the
-- ground (Y = 0), so clones are placed with pivotTo(ground point).
local function template(name: string, build: (model: Model) -> ()): Model
	local model = Instance.new("Model")
	model.Name = name
	build(model)
	model.WorldPivot = CFrame.identity
	model:SetAttribute(CampusBuilder.DECOR_ATTRIBUTE, true)
	return model
end

local function place(
	source: Model,
	parent: Instance,
	x: number,
	z: number,
	yaw: number?,
	scale: number?
): Model
	local clone = source:Clone()
	if scale and scale ~= 1 then
		clone:ScaleTo(scale)
	end
	clone:PivotTo(CFrame.new(x, GROUND, z) * CFrame.Angles(0, math.rad(yaw or 0), 0))
	clone.Parent = parent
	return clone
end

-- Turned to face the point (x, z) from (fromX, fromZ): a prop's front is -Z.
local function yawToward(fromX: number, fromZ: number, x: number, z: number): number
	return math.deg(math.atan2(-(x - fromX), -(z - fromZ)))
end

-- Templates ----------------------------------------------------------------

local function buildTemplates(): { [string]: Model }
	local templates: { [string]: Model } = {}

	-- Bench: seat, backrest (behind, +Z) and two legs. Sitters face -Z.
	templates.Bench = template("Bench", function(model)
		part(model, "Seat", Vector3.new(6, 0.4, 2), at(0, 1.6, 0), WOOD, Enum.Material.Wood)
		part(model, "Back", Vector3.new(6, 1.6, 0.3), at(0, 2.6, 0.9), WOOD, Enum.Material.Wood)
		for _, x in { -2.5, 2.5 } do
			part(
				model,
				"Leg",
				Vector3.new(0.4, 1.4, 1.8),
				at(x, 0.7, 0),
				METAL,
				Enum.Material.Metal
			)
		end
	end)

	-- Picnic table with a sun umbrella.
	templates.PicnicTable = template("PicnicTable", function(model)
		part(model, "Top", Vector3.new(6, 0.4, 3), at(0, 2.6, 0), WOOD, Enum.Material.Wood)
		part(
			model,
			"Pedestal",
			Vector3.new(0.8, 2.4, 0.8),
			at(0, 1.2, 0),
			DARK_WOOD,
			Enum.Material.Wood
		)
		for _, z in { -2.3, 2.3 } do
			part(
				model,
				"BenchSeat",
				Vector3.new(6, 0.3, 1),
				at(0, 1.5, z),
				WOOD,
				Enum.Material.Wood
			)
			part(model, "BenchLeg", Vector3.new(0.6, 1.35, 0.6), at(0, 0.68, z), DARK_WOOD)
		end
		part(model, "UmbrellaPole", Vector3.new(4.2, 0.25, 0.25), upright(0, 4.9, 0), METAL)
		local canopy = part(
			model,
			"Umbrella",
			Vector3.new(0.3, 7, 7),
			upright(0, 7, 0),
			Color3.fromRGB(255, 140, 90),
			Enum.Material.Fabric
		)
		canopy.Shape = Enum.PartType.Cylinder
		canopy.CastShadow = true
	end)

	templates.Tree = template("Tree", function(model)
		local trunk = part(
			model,
			"Trunk",
			Vector3.new(10, 1.6, 1.6),
			upright(0, 5, 0),
			DARK_WOOD,
			Enum.Material.Wood
		)
		trunk.Shape = Enum.PartType.Cylinder
		local crown =
			part(model, "Crown", Vector3.new(8, 8, 8), at(0, 12, 0), LEAF, Enum.Material.Grass)
		crown.Shape = Enum.PartType.Ball
	end)

	templates.Bush = template("Bush", function(model)
		local bush =
			part(model, "Bush", Vector3.new(3, 3, 3), at(0, 1.2, 0), HEDGE, Enum.Material.Grass)
		bush.Shape = Enum.PartType.Ball
	end)

	templates.Planter = template("Planter", function(model)
		part(model, "Pot", Vector3.new(2.6, 2, 2.6), at(0, 1, 0), POT)
		local leaves = part(
			model,
			"Leaves",
			Vector3.new(3.4, 3.4, 3.4),
			at(0, 3.4, 0),
			LEAF,
			Enum.Material.Grass
		)
		leaves.Shape = Enum.PartType.Ball
	end)

	-- Flower bed: soil with a row of colourful blooms.
	templates.FlowerBed = template("FlowerBed", function(model)
		part(
			model,
			"Soil",
			Vector3.new(6, 0.6, 3),
			at(0, 0.3, 0),
			Color3.fromRGB(100, 70, 50),
			Enum.Material.Ground
		)
		local colors = {
			Color3.fromRGB(255, 120, 160),
			Color3.fromRGB(255, 220, 90),
			Color3.fromRGB(170, 130, 255),
		}
		for index, color in colors do
			local bloom = part(
				model,
				"Bloom",
				Vector3.new(1.4, 1.4, 1.4),
				at((index - 2) * 1.8, 1.1, 0),
				color
			)
			bloom.Shape = Enum.PartType.Ball
			bloom.CanCollide = false
		end
	end)

	-- Lamp post: a soft glowing globe, no light object (cheap, never too bright).
	templates.LampPost = template("LampPost", function(model)
		local pole = part(
			model,
			"Pole",
			Vector3.new(8, 0.4, 0.4),
			upright(0, 4, 0),
			METAL,
			Enum.Material.Metal
		)
		pole.Shape = Enum.PartType.Cylinder
		local globe = part(
			model,
			"Globe",
			Vector3.new(1.3, 1.3, 1.3),
			at(0, 8.4, 0),
			LAMP,
			Enum.Material.Neon
		)
		globe.Shape = Enum.PartType.Ball
		globe.Transparency = 0.25
		globe.CastShadow = false
	end)

	templates.TrashBin = template("TrashBin", function(model)
		local bin = part(
			model,
			"Bin",
			Vector3.new(2.4, 1.6, 1.6),
			upright(0, 1.2, 0),
			Color3.fromRGB(70, 120, 90)
		)
		bin.Shape = Enum.PartType.Cylinder
	end)

	-- Bean bag: a squashed blob (Sphere mesh on a low box).
	templates.BeanBag = template("BeanBag", function(model)
		local bag = part(
			model,
			"BeanBag",
			Vector3.new(3.4, 1.8, 3.4),
			at(0, 0.9, 0),
			Color3.fromRGB(120, 170, 255),
			Enum.Material.Fabric
		)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = bag
	end)

	templates.Rock = template("Rock", function(model)
		local rock =
			part(model, "Rock", Vector3.new(3, 1.6, 2.4), at(0, 0.6, 0), STONE, Enum.Material.Slate)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = rock
	end)

	templates.VendingMachine = template("VendingMachine", function(model)
		local body =
			part(model, "Machine", Vector3.new(4, 7, 3), at(0, 3.5, 0), Color3.fromRGB(200, 60, 70))
		label(body, Enum.NormalId.Front, "SNACKS\nfor feelings")
		part(
			model,
			"Window",
			Vector3.new(3, 3.5, 0.2),
			at(0, 4.4, -1.55),
			Color3.fromRGB(170, 210, 235),
			Enum.Material.Glass
		).Transparency =
			0.4
	end)

	-- The Calm Brew Cafe (2026-10-10, was a bare kiosk): a small building open
	-- at the front (-Z) with a counter, an espresso machine, a pastry case,
	-- a back counter with jars, a menu board, glass side windows, a striped
	-- awning and a lit sign on the roof. Footprint 14 x 10, front at z -3.
	templates.CoffeeKiosk = template("CoffeeKiosk", function(model)
		local cream = Color3.fromRGB(232, 218, 195)
		local charcoal = Color3.fromRGB(45, 48, 58)
		local marble = Color3.fromRGB(225, 222, 215)
		part(
			model,
			"CafeDeck",
			Vector3.new(14, 0.3, 10),
			at(0, 0.15, 2),
			WOOD,
			Enum.Material.WoodPlanks
		)
		part(
			model,
			"CafeBackWall",
			Vector3.new(14, 10, 0.6),
			at(0, 5, 6.7),
			cream,
			Enum.Material.Plaster
		)
		for _, x in { -6.7, 6.7 } do
			part(
				model,
				"CafeSideWall",
				Vector3.new(0.6, 4, 10),
				at(x, 2, 2),
				cream,
				Enum.Material.Plaster
			)
			local window = part(
				model,
				"CafeWindow",
				Vector3.new(0.3, 6, 10),
				at(x, 7, 2),
				Color3.fromRGB(160, 200, 225),
				Enum.Material.Glass
			)
			window.Transparency = 0.4
		end
		part(
			model,
			"CafeRoof",
			Vector3.new(15, 0.8, 11),
			at(0, 10.4, 2),
			charcoal,
			Enum.Material.Metal
		)
		-- Striped awning over the front, sloping down and out.
		for i = 0, 3 do
			local stripe = part(
				model,
				"CafeAwning",
				Vector3.new(3.5, 0.25, 4),
				CFrame.new(-5.25 + i * 3.5, 8.6, -4.6) * CFrame.Angles(math.rad(-18), 0, 0),
				if i % 2 == 0 then Color3.fromRGB(215, 85, 70) else Color3.fromRGB(245, 240, 230),
				Enum.Material.Fabric
			)
			stripe.CanCollide = false
		end
		local sign = part(
			model,
			"SignBoard",
			Vector3.new(12, 2.4, 0.4),
			at(0, 12.2, -3.2),
			charcoal,
			Enum.Material.Metal
		)
		label(sign, Enum.NormalId.Front, "☕ CALM BREW CAFÉ")
		local signGui = sign:FindFirstChildOfClass("SurfaceGui") :: SurfaceGui
		signGui.LightInfluence = 0
		signGui.Brightness = 1.5
		-- A warm glow strip along the roof's front edge.
		local glow = part(
			model,
			"CafeGlow",
			Vector3.new(14, 0.2, 0.2),
			at(0, 9.9, -3.3),
			LAMP,
			Enum.Material.Neon
		)
		glow.Transparency = 0.4
		glow.CanCollide = false
		-- Front counter with the machine, cups and a pastry case.
		part(
			model,
			"Counter",
			Vector3.new(12, 3.6, 1.6),
			at(0, 1.8, -2),
			DARK_WOOD,
			Enum.Material.Wood
		)
		part(
			model,
			"CounterTop",
			Vector3.new(12.4, 0.3, 2),
			at(0, 3.75, -2),
			marble,
			Enum.Material.Marble
		)
		part(
			model,
			"EspressoMachine",
			Vector3.new(2, 1.8, 1.4),
			at(-3.8, 4.8, -1.8),
			METAL,
			Enum.Material.Metal
		)
		for i, x in { -1.6, -0.6 } do
			local cup = part(
				model,
				"Cup",
				Vector3.new(0.7, 0.6, 0.6),
				upright(x, 4.25, -2.2 + i * 0.1),
				Color3.new(1, 1, 1)
			)
			cup.Shape = Enum.PartType.Cylinder
		end
		local case = part(
			model,
			"PastryCase",
			Vector3.new(3.4, 1.6, 1.4),
			at(3.4, 4.7, -2),
			Color3.fromRGB(200, 225, 235),
			Enum.Material.Glass
		)
		case.Transparency = 0.45
		for _, x in { 2.6, 3.6 } do
			local pastry = part(
				model,
				"Pastry",
				Vector3.new(0.8, 0.8, 0.8),
				at(x, 4.3, -2),
				Color3.fromRGB(215, 150, 80)
			)
			pastry.Shape = Enum.PartType.Ball
		end
		-- Back counter, a shelf of jars and the menu board.
		part(
			model,
			"BackCounter",
			Vector3.new(12, 3.4, 1.4),
			at(0, 1.7, 5.8),
			DARK_WOOD,
			Enum.Material.Wood
		)
		part(
			model,
			"Shelf",
			Vector3.new(12, 0.3, 1),
			at(0, 6.4, 6.1),
			DARK_WOOD,
			Enum.Material.Wood
		)
		for _, x in { -4, -2.5, 2.5, 4 } do
			local jar = part(
				model,
				"Jar",
				Vector3.new(1.2, 0.9, 0.9),
				upright(x, 7.15, 6.1),
				Color3.fromRGB(150, 95, 55),
				Enum.Material.Glass
			)
			jar.Shape = Enum.PartType.Cylinder
		end
		local menu = part(model, "MenuBoard", Vector3.new(5, 2.6, 0.2), at(0, 8.4, 6.3), charcoal)
		label(menu, Enum.NormalId.Front, "Latte of Calm · Espresso Break · Decaf for Mondays")
		-- Potted plants at the front corners.
		for _, x in { -6.2, 6.2 } do
			part(
				model,
				"CafePot",
				Vector3.new(1.6, 1.6, 1.6),
				at(x, 0.8, -3.6),
				POT,
				Enum.Material.SmoothPlastic
			)
			local leaves = part(
				model,
				"CafeLeaves",
				Vector3.new(2.8, 2.8, 2.8),
				at(x, 2.8, -3.6),
				LEAF,
				Enum.Material.Grass
			)
			leaves.Shape = Enum.PartType.Ball
			leaves.CanCollide = false
		end
	end)

	-- A patio parasol (pole and a round canopy), for the cafe's tables.
	templates.Parasol = template("Parasol", function(model)
		local pole = part(
			model,
			"ParasolPole",
			Vector3.new(0.3, 8, 0.3),
			at(0, 4, 0),
			METAL,
			Enum.Material.Metal
		)
		pole.CanCollide = false
		local canopy = part(
			model,
			"ParasolCanopy",
			Vector3.new(0.5, 9, 9),
			upright(0, 8, 0),
			Color3.fromRGB(215, 85, 70),
			Enum.Material.Fabric
		)
		canopy.Shape = Enum.PartType.Cylinder
		canopy.CanCollide = false
	end)

	-- Signpost: a pole with a board facing -Z (towards the entrance by default).
	templates.Sign = template("Sign", function(model)
		part(
			model,
			"SignPole",
			Vector3.new(0.4, 5, 0.4),
			at(0, 2.5, 0),
			DARK_WOOD,
			Enum.Material.Wood
		)
		part(model, "SignBoard", Vector3.new(7, 2.6, 0.3), at(0, 5.4, 0), SIGN)
	end)

	templates.StressBall = template("StressBall", function(model)
		local ball = part(
			model,
			"StressBall",
			Vector3.new(6, 6, 6),
			at(0, 3, 0),
			Color3.fromRGB(255, 130, 180)
		)
		ball.Shape = Enum.PartType.Ball
	end)

	return templates
end

-- A signpost with `text`, facing the point (lookX, lookZ).
local function signAt(
	templates: { [string]: Model },
	parent: Instance,
	x: number,
	z: number,
	lookX: number,
	lookZ: number,
	text: string
): ()
	local sign = place(templates.Sign, parent, x, z, yawToward(x, z, lookX, lookZ))
	local board = sign:FindFirstChild("SignBoard")
	if board and board:IsA("BasePart") then
		label(board, Enum.NormalId.Front, text)
	end
end

-- Points on a circle around `center` at the given angles (degrees; 0 = +X,
-- 90 = +Z, i.e. south).
local function around(center: Vector3, radius: number, angles: { number }): { Vector2 }
	local points: { Vector2 } = {}
	for _, degrees in angles do
		local radians = math.rad(degrees)
		table.insert(
			points,
			Vector2.new(
				center.X + math.cos(radians) * radius,
				center.Z + math.sin(radians) * radius
			)
		)
	end
	return points
end

-- Areas --------------------------------------------------------------------

local function plaza(templates: { [string]: Model }, parent: Instance): ()
	local area = Instance.new("Folder")
	area.Name = "FrontPlaza"
	area.Parent = parent
	-- Benches along the plaza's south edge, facing the building (-Z).
	for _, x in { -30, -18, 18, 30 } do
		place(templates.Bench, area, x, 49)
	end
	for _, x in { -36, -12, 12, 36 } do
		place(templates.Planter, area, x, 38)
	end
	for _, x in { -8, 8 } do
		place(templates.LampPost, area, x, 50)
	end
	place(templates.TrashBin, area, -24, 50)
	place(templates.TrashBin, area, 24, 50)
	signAt(
		templates,
		area,
		9,
		56,
		0,
		34,
		"<- Relaxation Garden   Coffee Corner ->   v Recreation Center (Pickleball)"
	)
end

local function walkwayDecor(templates: { [string]: Model }, parent: Instance): ()
	local area = Instance.new("Folder")
	area.Name = "Walkways"
	area.Parent = parent
	-- Lamp posts and trees beside the main walkway (it runs x -5..5).
	for _, z in { 62, 76, 100 } do
		for _, x in { -8, 8 } do
			place(templates.LampPost, area, x, z)
		end
	end
	for index, z in { 60, 72, 104 } do
		for _, x in { -15, 15 } do
			place(templates.Tree, area, x, z, index * 40, 0.9 + (index % 2) * 0.15)
		end
	end
	-- Along the cross walk (z 84..92).
	for _, x in { -36, -22, 22, 36 } do
		place(templates.Bush, area, x, 80)
		place(templates.Bush, area, x, 96)
	end
	-- Behind the building, along the loop's north leg (z -66..-60).
	for x = -80, 80, 32 do
		place(templates.Tree, area, x, -76, x, 1 + (x % 3) * 0.1)
		-- Benches between the trees, clear of the loop's side legs (x +-94).
		if x < 80 then
			place(templates.Bench, area, x + 16, -56)
		end
	end
	-- Beside the building, outside the loop's side legs (x +-94..100).
	for z = -40, 20, 30 do
		for _, x in { -112, 112 } do
			place(templates.Tree, area, x, z, z, 1.1)
		end
	end
end

local function garden(templates: { [string]: Model }, parent: Instance): ()
	local area = Instance.new("Folder")
	area.Name = "RelaxationGarden"
	area.Parent = parent
	local center = CAMPUS.Garden.Center
	-- A shallow pond: a thin water surface you can walk across (no terrain
	-- water, so nobody can sink or get stuck), ringed by stones.
	local pond = part(
		area,
		"PondWater",
		Vector3.new(0.2, 12, 12),
		upright(center.X, GROUND + 0.1, center.Z),
		Color3.fromRGB(90, 170, 220),
		Enum.Material.Glass
	)
	pond.Shape = Enum.PartType.Cylinder
	pond.Transparency = 0.25
	pond.CanCollide = false
	pond.CastShadow = false
	pond:SetAttribute(CampusBuilder.DECOR_ATTRIBUTE, true)
	for _, point in around(center, 7.5, { 0, 45, 90, 135, 180, 225, 270, 315 }) do
		place(templates.Rock, area, point.X, point.Y, point.X * 7, 0.6)
	end
	-- Benches facing the pond, between the paths coming in east and west.
	for _, point in around(center, 13, { 45, 135, 225, 315 }) do
		place(
			templates.Bench,
			area,
			point.X,
			point.Y,
			yawToward(point.X, point.Y, center.X, center.Z)
		)
	end
	for _, point in around(center, 18, { 70, 110, 250, 290 }) do
		place(
			templates.FlowerBed,
			area,
			point.X,
			point.Y,
			yawToward(point.X, point.Y, center.X, center.Z)
		)
	end
	for index, point in around(center, 28, { 30, 70, 110, 150, 230, 270, 310 }) do
		place(templates.Tree, area, point.X, point.Y, index * 50, 0.9 + (index % 3) * 0.12)
	end
	signAt(templates, area, -44, 97, 0, 97, "RELAXATION GARDEN\nNo meetings beyond this point")
end

local function coffeeCorner(templates: { [string]: Model }, parent: Instance): ()
	local area = Instance.new("Folder")
	area.Name = "CoffeeCorner"
	area.Parent = parent
	local center = CAMPUS.CoffeeCorner.Center
	-- Kiosk at the back (east), serving towards the patio (west).
	place(templates.CoffeeKiosk, area, center.X + 13, center.Z, 90)
	for _, offset in
		{ Vector2.new(-8, -10), Vector2.new(-8, 10), Vector2.new(4, -12), Vector2.new(4, 12) }
	do
		place(templates.PicnicTable, area, center.X + offset.X, center.Z + offset.Y, 90)
	end
	place(
		templates.VendingMachine,
		area,
		center.X + 10,
		center.Z - 16,
		yawToward(center.X + 10, center.Z - 16, center.X, center.Z)
	)
	place(templates.TrashBin, area, center.X + 14, center.Z - 12)
	-- Parasols over the patio tables.
	for _, offset in { Vector2.new(-8, -10), Vector2.new(-8, 10) } do
		place(templates.Parasol, area, center.X + offset.X, center.Z + offset.Y)
	end
	for _, point in around(center, 21, { 300, 330, 30, 60 }) do
		place(templates.Planter, area, point.X, point.Y)
	end
	signAt(
		templates,
		area,
		46,
		97,
		0,
		97,
		"CALM BREW CAFÉ\nCoffee Corner · Fuel for the next whack"
	)
end

local function stressReliefZone(templates: { [string]: Model }, parent: Instance): ()
	local area = Instance.new("Folder")
	area.Name = "StressReliefZone"
	area.Parent = parent
	local center = CAMPUS.StressReliefZone.Center
	place(templates.StressBall, area, center.X, center.Z + 3)
	-- Bean bags around the ball, open to the walkway coming in from the north.
	for _, point in around(center, 10, { 0, 50, 90, 130, 180 }) do
		place(templates.BeanBag, area, point.X, point.Y)
	end
	for _, offset in { Vector2.new(-9, -7), Vector2.new(10, -6), Vector2.new(-12, 6) } do
		place(templates.Rock, area, center.X + offset.X, center.Z + offset.Y, offset.X * 10, 1)
	end
	-- Beside the walkway coming in from the building (south of the zone).
	signAt(
		templates,
		area,
		center.X + 9,
		center.Z + 18,
		center.X,
		center.Z + 40,
		"STRESS-RELIEF ZONE\nBreathe in. Breathe out. Reply later."
	)
end

-- Invisible walls on the boundary, with a low hedge just inside them.
local function boundary(parent: Instance): ()
	local area = Instance.new("Folder")
	area.Name = "Boundary"
	area.Parent = parent
	local box = CAMPUS.Boundary
	local height = CAMPUS.BoundaryHeight
	local width = box.MaxX - box.MinX
	local depth = box.MaxZ - box.MinZ
	local midX = (box.MinX + box.MaxX) / 2
	local midZ = (box.MinZ + box.MaxZ) / 2
	local sides = {
		{ Size = Vector3.new(width, height, 2), At = Vector3.new(midX, 0, box.MinZ) },
		{ Size = Vector3.new(width, height, 2), At = Vector3.new(midX, 0, box.MaxZ) },
		{ Size = Vector3.new(2, height, depth), At = Vector3.new(box.MinX, 0, midZ) },
		{ Size = Vector3.new(2, height, depth), At = Vector3.new(box.MaxX, 0, midZ) },
	}
	for _, side in sides do
		local wall = part(
			area,
			CampusBuilder.BOUNDARY_NAME,
			side.Size,
			CFrame.new(side.At + Vector3.new(0, GROUND + height / 2, 0)),
			Color3.new(1, 1, 1)
		)
		wall.Transparency = 1
		wall.CastShadow = false
		wall.CanQuery = false
		wall.CanTouch = false
		-- The hedge, 3 studs tall, on the inside of the wall.
		local inward =
			Vector3.new(-math.sign(side.At.X - midX) * 2, 0, -math.sign(side.At.Z - midZ) * 2)
		local hedgeSize = Vector3.new(
			if side.Size.X > 2 then side.Size.X else 2.5,
			3,
			if side.Size.Z > 2 then side.Size.Z else 2.5
		)
		part(
			area,
			"Hedge",
			hedgeSize,
			CFrame.new(side.At + inward + Vector3.new(0, GROUND + 1.5, 0)),
			HEDGE,
			Enum.Material.Grass
		)
	end
end

-- Builds every campus prop and the boundary into a "Campus" folder.
function CampusBuilder.build(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Campus"
	local templates = buildTemplates()
	plaza(templates, folder)
	walkwayDecor(templates, folder)
	garden(templates, folder)
	coffeeCorner(templates, folder)
	stressReliefZone(templates, folder)
	boundary(folder)
	for _, source in templates do
		source:Destroy()
	end
	folder.Parent = parent
	return folder
end

-- Paints the grounds into Terrain: plaza, walkways and the three areas.
-- Call after the grass is filled (Lib/OutdoorBuilder). Like the street, each
-- fill is 4 studs deep (one terrain cell) with its top a hair above the grass.
function CampusBuilder.paint(terrain: Terrain): ()
	local fillY = GROUND - 2 + 0.05
	local function rect(
		box: { MinX: number, MaxX: number, MinZ: number, MaxZ: number },
		material: Enum.Material
	): ()
		terrain:FillBlock(
			CFrame.new((box.MinX + box.MaxX) / 2, fillY, (box.MinZ + box.MaxZ) / 2),
			Vector3.new(box.MaxX - box.MinX, 4, box.MaxZ - box.MinZ),
			material
		)
	end
	local function disc(center: Vector3, radius: number, material: Enum.Material): ()
		terrain:FillCylinder(CFrame.new(center.X, fillY, center.Z), 4, radius, material)
	end

	disc(CAMPUS.Garden.Center, CAMPUS.Garden.Radius, Enum.Material.LeafyGrass)
	disc(CAMPUS.CoffeeCorner.Center, CAMPUS.CoffeeCorner.Radius, Enum.Material.Brick)
	disc(CAMPUS.StressReliefZone.Center, CAMPUS.StressReliefZone.Radius, Enum.Material.Sand)
	-- Paths last, so they run cleanly into the areas.
	rect(CAMPUS.Plaza, Enum.Material.Pavement)
	for _, walkway in CAMPUS.Walkways do
		rect(walkway, Enum.Material.Concrete)
	end
end

return CampusBuilder
