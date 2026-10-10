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
local PickleballConfig = require(ReplicatedStorage.Config.PickleballConfig)
local CampusBuilder = require(ServerScriptService.Lib.CampusBuilder)

local OutdoorBuilder = {}

local GROUND_SIZE = 720 -- studs across the grass area
-- The road runs east-west just south of the campus boundary.
local STREET =
	{ NorthZ = ArenaConfig.Campus.StreetNorthZ, SouthZ = ArenaConfig.Campus.StreetSouthZ }
local SKYLINE = { InnerRadius = 250, OuterRadius = 340, Count = 40, Seed = 4242 }
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

-- Paving (no grass) under the headquarters and the Recreation Center, with
-- a narrow paved apron round them. Terrain grass grows animated blades that
-- poke up through thin floors laid on it (they showed through the lobby and
-- podium room floors); a raw concrete band looked like a building site.
local function underBuildings(terrain: Terrain): ()
	local margin = 4
	local half = ArenaConfig.BuildingHalfWidth + margin
	local minZ = ArenaConfig.BuildingNorthZ - margin
	local maxZ = ArenaConfig.BuildingSouthZ + margin
	terrain:FillBlock(
		CFrame.new(0, -3, (minZ + maxZ) / 2),
		Vector3.new(half * 2, 4, maxZ - minZ),
		Enum.Material.Pavement
	)
	local rec = PickleballConfig.Center.Area
	terrain:FillBlock(
		CFrame.new((rec.MinX + rec.MaxX) / 2, -3, (rec.MinZ + rec.MaxZ) / 2),
		Vector3.new(rec.MaxX - rec.MinX + margin * 2, 4, rec.MaxZ - rec.MinZ + margin * 2),
		Enum.Material.Pavement
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

-- The city around the campus (visual overhaul, 2026-10-10): office blocks
-- with a glass body, a concrete band at every floor, a parapet and a plant
-- room on the roof, so they read as buildings rather than plain boxes. Lower
-- than before and further out, so the HQ stands out; none on the campus or
-- the street. Scenery only: no collisions, queries, touches or shadows.
local function skyline(parent: Instance): ()
	local random = Random.new(SKYLINE.Seed)
	local glassColors = {
		Color3.fromRGB(110, 140, 170),
		Color3.fromRGB(95, 120, 150),
		Color3.fromRGB(130, 150, 170),
		Color3.fromRGB(85, 105, 130),
	}
	local bandColors = {
		Color3.fromRGB(190, 190, 195),
		Color3.fromRGB(160, 160, 168),
		Color3.fromRGB(205, 198, 185),
	}
	local function scenery(p: Part): ()
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
	end
	for _ = 1, SKYLINE.Count do
		local angle = random:NextNumber(0, math.pi * 2)
		local radius = random:NextNumber(SKYLINE.InnerRadius, SKYLINE.OuterRadius)
		local width = random:NextNumber(24, 44)
		local depth = random:NextNumber(24, 44)
		local floors = random:NextInteger(3, 9)
		local glass = glassColors[random:NextInteger(1, #glassColors)]
		local band = bandColors[random:NextInteger(1, #bandColors)]
		local position = Vector3.new(math.cos(angle) * radius, -1, math.sin(angle) * radius)
		local onStreet = position.Z > STREET.NorthZ - depth / 2 - 10
			and position.Z < STREET.SouthZ + depth / 2 + 10
		if insideCampus(position, math.max(width, depth) / 2 + 16) or onStreet then
			continue
		end
		local storey = 9
		local height = floors * storey
		local block = Instance.new("Model")
		block.Name = "SkylineBuilding"
		block.Parent = parent
		local body = part(
			block,
			"SkylineGlass",
			Vector3.new(width, height, depth),
			CFrame.new(position.X, height / 2 - 1, position.Z),
			glass,
			Enum.Material.Glass
		)
		body.Reflectance = 0.15
		scenery(body)
		for floor = 0, floors do
			local y = floor * storey - 1
			scenery(
				part(
					block,
					"SkylineBand",
					Vector3.new(width + 0.8, if floor == floors then 2.5 else 1.4, depth + 0.8),
					CFrame.new(position.X, y + (if floor == floors then 1.25 else 0.7), position.Z),
					band,
					Enum.Material.Concrete
				)
			)
		end
		scenery(
			part(
				block,
				"SkylinePlantRoom",
				Vector3.new(width * 0.4, 5, depth * 0.4),
				CFrame.new(position.X + width * 0.15, height + 3.5, position.Z - depth * 0.1),
				band,
				Enum.Material.Concrete
			)
		)
	end
end

function OutdoorBuilder.build(parent: Instance, terrain: Terrain): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Outdoors"
	fillGround(terrain)
	CampusBuilder.paint(terrain)
	underBuildings(terrain)
	streetMarkings(folder)
	trees(folder)
	skyline(folder)
	CampusBuilder.build(folder)
	folder.Parent = parent
	return folder
end

return OutdoorBuilder
