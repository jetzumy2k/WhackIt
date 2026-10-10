--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local CampusBuilder = require(ServerScriptService.Lib.CampusBuilder)
local PickleballConfig = require(ReplicatedStorage.Config.PickleballConfig)

local CAMPUS = ArenaConfig.Campus
-- Parts lower than this (above the ground) can block someone walking.
local HEAD_HEIGHT = 6
-- Budget for the whole campus: well under "thousands of parts".
local MAX_PARTS = 500

type Box = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }

local function build(): Folder
	return CampusBuilder.build(Instance.new("Folder"))
end

local function parts(root: Instance): { BasePart }
	local list: { BasePart } = {}
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(list, descendant)
		end
	end
	return list
end

-- World-space XZ box and lowest Y of a (possibly turned) part.
local function footprint(part: BasePart): (Box, number)
	local cf = part.CFrame
	local half = part.Size / 2
	local extentX = math.abs(cf.RightVector.X) * half.X
		+ math.abs(cf.UpVector.X) * half.Y
		+ math.abs(cf.LookVector.X) * half.Z
	local extentY = math.abs(cf.RightVector.Y) * half.X
		+ math.abs(cf.UpVector.Y) * half.Y
		+ math.abs(cf.LookVector.Y) * half.Z
	local extentZ = math.abs(cf.RightVector.Z) * half.X
		+ math.abs(cf.UpVector.Z) * half.Y
		+ math.abs(cf.LookVector.Z) * half.Z
	local p = cf.Position
	return {
		MinX = p.X - extentX,
		MaxX = p.X + extentX,
		MinZ = p.Z - extentZ,
		MaxZ = p.Z + extentZ,
	},
		p.Y - extentY
end

local function overlaps(a: Box, b: Box): boolean
	return a.MinX < b.MaxX and a.MaxX > b.MinX and a.MinZ < b.MaxZ and a.MaxZ > b.MinZ
end

local function inside(a: Box, b: Box): boolean
	return a.MinX >= b.MinX and a.MaxX <= b.MaxX and a.MinZ >= b.MinZ and a.MaxZ <= b.MaxZ
end

local function touchesCircle(box: Box, center: Vector3, radius: number): boolean
	local x = math.clamp(center.X, box.MinX, box.MaxX)
	local z = math.clamp(center.Z, box.MinZ, box.MaxZ)
	return Vector2.new(x - center.X, z - center.Z).Magnitude <= radius
end

-- Walking lanes that must stay free: every walkway plus the entrance lane
-- through the plaza.
local function lanes(): { Box }
	local list: { Box } = {
		{
			MinX = -CAMPUS.EntranceWidth / 2,
			MaxX = CAMPUS.EntranceWidth / 2,
			MinZ = ArenaConfig.BuildingSouthZ,
			MaxZ = CAMPUS.Plaza.MaxZ,
		},
	}
	for _, walkway in CAMPUS.Walkways do
		table.insert(list, walkway)
	end
	return list
end

return function()
	describe("CampusBuilder.build", function()
		it("builds every area in its own folder", function()
			local campus = build()
			for _, name in
				{
					"FrontPlaza",
					"Walkways",
					"RelaxationGarden",
					"CoffeeCorner",
					"StressReliefZone",
					"Boundary",
				}
			do
				expect(campus:FindFirstChild(name)).never.to.equal(nil)
			end
			campus:Destroy()
		end)

		it("stays light: anchored parts, a small part count, no lights", function()
			local campus = build()
			local list = parts(campus)
			expect(#list <= MAX_PARTS).to.equal(true)
			for _, part in list do
				expect(part.Anchored).to.equal(true)
			end
			for _, descendant in campus:GetDescendants() do
				expect(descendant:IsA("Light")).to.equal(false)
				expect(descendant:IsA("ParticleEmitter")).to.equal(false)
			end
			campus:Destroy()
		end)

		it("keeps every walkway and the entrance lane free to walk", function()
			local campus = build()
			local boundary = campus:FindFirstChild("Boundary") :: Folder
			for _, part in parts(campus) do
				if part:IsDescendantOf(boundary) or not part.CanCollide then
					continue
				end
				local box, bottom = footprint(part)
				if bottom < CAMPUS.GroundY + HEAD_HEIGHT then
					for _, lane in lanes() do
						if overlaps(box, lane) then
							error(
								string.format(
									"%s blocks a walkway at %s",
									part:GetFullName(),
									tostring(part.Position)
								)
							)
						end
					end
				end
			end
			campus:Destroy()
		end)

		it("keeps every prop inside the boundary", function()
			local campus = build()
			local box = CAMPUS.Boundary
			local inner = {
				MinX = box.MinX + 1,
				MaxX = box.MaxX - 1,
				MinZ = box.MinZ + 1,
				MaxZ = box.MaxZ - 1,
			}
			local boundary = campus:FindFirstChild("Boundary") :: Folder
			for _, part in parts(campus) do
				if not part:IsDescendantOf(boundary) then
					local footprintBox = footprint(part)
					expect(inside(footprintBox, inner)).to.equal(true)
				end
			end
			campus:Destroy()
		end)

		it("walls the grounds with invisible, solid, unclickable walls", function()
			local campus = build()
			local walls = 0
			for _, part in parts(campus:FindFirstChild("Boundary") :: Folder) do
				if part.Name == CampusBuilder.BOUNDARY_NAME then
					walls += 1
					expect(part.CanCollide).to.equal(true)
					expect(part.Transparency).to.equal(1)
					expect(part.CanQuery).to.equal(false)
					expect(part.Size.Y >= 40).to.equal(true)
				end
			end
			expect(walls).to.equal(4)
			campus:Destroy()
		end)
	end)

	describe("ArenaConfig.Campus layout", function()
		it("puts the building, walkways and areas inside the boundary", function()
			local box = CAMPUS.Boundary
			local building = {
				MinX = -ArenaConfig.BuildingHalfWidth,
				MaxX = ArenaConfig.BuildingHalfWidth,
				MinZ = ArenaConfig.BuildingNorthZ,
				MaxZ = ArenaConfig.BuildingSouthZ,
			}
			expect(inside(building, box)).to.equal(true)
			expect(inside(CAMPUS.Plaza, box)).to.equal(true)
			for _, walkway in CAMPUS.Walkways do
				expect(inside(walkway, box)).to.equal(true)
			end
			for _, area in { CAMPUS.Garden, CAMPUS.CoffeeCorner, CAMPUS.StressReliefZone } do
				local c, r = area.Center, area.Radius
				expect(
					inside({ MinX = c.X - r, MaxX = c.X + r, MinZ = c.Z - r, MaxZ = c.Z + r }, box)
				).to.equal(true)
			end
			-- The street is scenery outside the walls.
			expect(CAMPUS.StreetNorthZ > box.MaxZ).to.equal(true)
		end)

		it("connects the entrance to every area by walkways", function()
			local walkways = CAMPUS.Walkways
			local main = walkways[1]
			local cross = walkways[2]
			-- Entrance lane -> plaza -> main walkway.
			expect(main.MinZ <= CAMPUS.Plaza.MaxZ).to.equal(true)
			expect(main.MinX >= -CAMPUS.EntranceWidth / 2 and main.MaxX <= CAMPUS.EntranceWidth / 2).to.equal(
				true
			)
			-- The main walkway leads to the Recreation Center (in front since
			-- 2026-10-10); a walkway from the loop reaches the Stress-Relief Zone.
			local rec = PickleballConfig.Center.Area
			expect(main.MaxZ >= rec.MinZ).to.equal(true)
			local zone = CAMPUS.StressReliefZone
			local zoneReached = false
			for _, walkway in walkways do
				zoneReached = zoneReached or touchesCircle(walkway, zone.Center, zone.Radius)
			end
			expect(zoneReached).to.equal(true)
			-- The cross walk meets the main walkway and reaches both side areas.
			expect(overlaps(main, cross)).to.equal(true)
			expect(touchesCircle(cross, CAMPUS.Garden.Center, CAMPUS.Garden.Radius)).to.equal(true)
			expect(touchesCircle(cross, CAMPUS.CoffeeCorner.Center, CAMPUS.CoffeeCorner.Radius)).to.equal(
				true
			)
		end)

		it("makes the entrance wide and tall enough for anyone", function()
			expect(CAMPUS.EntranceWidth >= 10).to.equal(true)
			expect(CAMPUS.EntranceHeight >= 8).to.equal(true)
		end)
	end)
end
