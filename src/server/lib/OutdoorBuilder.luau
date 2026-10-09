--!strict
--[[
	Outdoor surroundings of the office building: grass Terrain, the walkable
	campus (Lib/CampusBuilder, ArenaConfig.Campus), a street just outside the
	campus boundary, a ring of trees beyond it and a city skyline in the
	distance (seen through the office windows and the lobby glass).

	Deterministic (fixed random seed) so every server looks the same. Distant
	skyline blocks don't collide or cast shadows; players never reach them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServerScriptService = game:GetService("ServerScriptService")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local CampusBuilder = require(ServerScriptService.Lib.CampusBuilder)

local OutdoorBuilder = {}

local GROUND_SIZE = 720 -- studs across the grass area
-- The road runs east-west just south of the campus boundary.
local STREET =
	{ NorthZ = ArenaConfig.Campus.StreetNorthZ, SouthZ = ArenaConfig.Campus.StreetSouthZ }
local SKYLINE = { InnerRadius = 190, OuterRadius = 300, Count = 46, Seed = 4242 }
local TREE_SEED = 777

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function fillGround(terrain: Terrain): ()
	-- Grass top sits 1 stud below the building floor, so the floor's edge reads as a step.
	terrain:FillBlock(
		CFrame.new(0, -3, 0),
		Vector3.new(GROUND_SIZE, 4, GROUND_SIZE),
		Enum.Material.Grass
	)
	local streetDepth = STREET.SouthZ - STREET.NorthZ
	terrain:FillBlock(
		CFrame.new(0, -2.9, (STREET.NorthZ + STREET.SouthZ) / 2),
		Vector3.new(GROUND_SIZE, 4, streetDepth),
		Enum.Material.Asphalt
	)
	-- Sidewalk along the street's north side (outside the boundary hedge).
	terrain:FillBlock(
		CFrame.new(0, -2.8, STREET.NorthZ - 3),
		Vector3.new(GROUND_SIZE, 4, 6),
		Enum.Material.Concrete
	)
end

local function streetMarkings(parent: Instance): ()
	local centerZ = (STREET.NorthZ + STREET.SouthZ) / 2
	for x = -GROUND_SIZE / 2 + 10, GROUND_SIZE / 2 - 10, 20 do
		local dash = part(
			parent,
			"LaneDash",
			Vector3.new(8, 0.1, 0.6),
			CFrame.new(x, -0.85, centerZ),
			Color3.fromRGB(245, 235, 160),
			Enum.Material.SmoothPlastic
		)
		dash.CanCollide = false
	end
end

local function tree(parent: Instance, position: Vector3, height: number): ()
	local trunk = part(
		parent,
		"TreeTrunk",
		Vector3.new(height, 1.6, 1.6),
		CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(110, 75, 45),
		Enum.Material.Wood
	)
	trunk.Shape = Enum.PartType.Cylinder
	local crownSize = height * 0.7
	local crown = part(
		parent,
		"TreeCrown",
		Vector3.new(crownSize, crownSize, crownSize),
		CFrame.new(position + Vector3.new(0, height + crownSize * 0.3, 0)),
		Color3.fromRGB(70, 150, 70),
		Enum.Material.Grass
	)
	crown.Shape = Enum.PartType.Ball
end

local function insideCampus(position: Vector3, margin: number): boolean
	local box = ArenaConfig.Campus.Boundary
	return position.X > box.MinX - margin
		and position.X < box.MaxX + margin
		and position.Z > box.MinZ - margin
		and position.Z < box.MaxZ + margin
end

local function trees(parent: Instance): ()
	local random = Random.new(TREE_SEED)
	local half = ArenaConfig.BuildingHalfWidth
	-- Along the plaza's south edge, outside the plaza and the loop walkway.
	for x = -half + 6, half - 6, 18 do
		if math.abs(x) > 50 then
			tree(
				parent,
				Vector3.new(x, -1, ArenaConfig.Campus.Plaza.MaxZ - 2),
				random:NextNumber(9, 12)
			)
		end
	end
	-- A loose ring of trees beyond the campus boundary (it plants its own inside).
	for _ = 1, 48 do
		local angle = random:NextNumber(0, math.pi * 2)
		local radius = random:NextNumber(150, 220)
		local position = Vector3.new(math.cos(angle) * radius, -1, math.sin(angle) * radius - 10)
		-- Keep the campus and the street clear.
		local onStreet = position.Z > STREET.NorthZ - 8 and position.Z < STREET.SouthZ + 4
		if not insideCampus(position, 6) and not onStreet then
			tree(parent, position, random:NextNumber(10, 16))
		end
	end
end

local function skyline(parent: Instance): ()
	local random = Random.new(SKYLINE.Seed)
	local palette = {
		Color3.fromRGB(150, 165, 185),
		Color3.fromRGB(120, 135, 160),
		Color3.fromRGB(180, 185, 195),
		Color3.fromRGB(95, 110, 140),
	}
	for _ = 1, SKYLINE.Count do
		local angle = random:NextNumber(0, math.pi * 2)
		local radius = random:NextNumber(SKYLINE.InnerRadius, SKYLINE.OuterRadius)
		local width = random:NextNumber(18, 40)
		local height = random:NextNumber(40, 150)
		local paletteIndex = random:NextInteger(1, #palette)
		local position = Vector3.new(math.cos(angle) * radius, -1, math.sin(angle) * radius)
		-- Since the campus grew north (Recreation Center), a few blocks would
		-- stand on the grounds: skip those. Every number is still drawn, so
		-- the other blocks stay exactly where they were.
		if insideCampus(position, width / 2 + 10) then
			continue
		end
		local building = part(
			parent,
			"SkylineBuilding",
			Vector3.new(width, height, width),
			CFrame.new(position.X, height / 2 - 1, position.Z),
			palette[paletteIndex],
			Enum.Material.Glass
		)
		building.CanCollide = false
		building.CanQuery = false
		building.CanTouch = false
		building.CastShadow = false
	end
end

function OutdoorBuilder.build(parent: Instance, terrain: Terrain): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Outdoors"
	fillGround(terrain)
	CampusBuilder.paint(terrain)
	streetMarkings(folder)
	trees(folder)
	skyline(folder)
	CampusBuilder.build(folder)
	folder.Parent = parent
	return folder
end

return OutdoorBuilder
