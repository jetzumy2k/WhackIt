--!strict
--[[
	Outdoor surroundings of the office building: grass Terrain, a street with
	sidewalk in front of the lobby, trees around the building and a city skyline
	in the distance (seen through the office windows and the lobby glass).

	Deterministic (fixed random seed) so every server looks the same. Distant
	skyline blocks don't collide or cast shadows; players never reach them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)

local OutdoorBuilder = {}

local GROUND_SIZE = 720 -- studs across the grass area
local STREET = { NorthZ = 48, SouthZ = 64 } -- the road runs east-west in front of the lobby
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
	-- Sidewalk between the lobby front and the street.
	terrain:FillBlock(
		CFrame.new(0, -2.8, (ArenaConfig.BuildingSouthZ + STREET.NorthZ) / 2 + 1),
		Vector3.new(GROUND_SIZE, 4, STREET.NorthZ - ArenaConfig.BuildingSouthZ - 2),
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

local function trees(parent: Instance): ()
	local random = Random.new(TREE_SEED)
	local half = ArenaConfig.BuildingHalfWidth
	-- Along the sidewalk in front of the lobby, both sides of the entrance.
	for x = -half + 6, half - 6, 18 do
		if math.abs(x) > 20 then
			tree(
				parent,
				Vector3.new(x, -1, ArenaConfig.BuildingSouthZ + 8),
				random:NextNumber(9, 12)
			)
		end
	end
	-- A loose ring of trees behind and beside the building.
	for _ = 1, 40 do
		local angle = random:NextNumber(0, math.pi * 2)
		local radius = random:NextNumber(110, 170)
		local position = Vector3.new(math.cos(angle) * radius, -1, math.sin(angle) * radius - 10)
		-- Keep the street clear.
		if position.Z < STREET.NorthZ - 4 or position.Z > STREET.SouthZ + 4 then
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
		local building = part(
			parent,
			"SkylineBuilding",
			Vector3.new(width, height, width),
			CFrame.new(math.cos(angle) * radius, height / 2 - 1, math.sin(angle) * radius),
			palette[random:NextInteger(1, #palette)],
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
	streetMarkings(folder)
	trees(folder)
	skyline(folder)
	folder.Parent = parent
	return folder
end

return OutdoorBuilder
