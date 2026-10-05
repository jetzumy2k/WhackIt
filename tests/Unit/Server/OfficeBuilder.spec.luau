--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local OfficeBuilder = require(ServerScriptService.Lib.OfficeBuilder)

-- Free space kept around each boss so players can walk up and swing.
local BOSS_CLEARANCE = 7

local function build(): Folder
	local holder = Instance.new("Folder")
	return OfficeBuilder.build(holder)
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

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

-- Whether `point` lies inside the part's (axis-aligned) box.
local function contains(part: BasePart, point: Vector3): boolean
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	return math.abs(localPoint.X) <= half.X
		and math.abs(localPoint.Y) <= half.Y
		and math.abs(localPoint.Z) <= half.Z
end

return function()
	describe("OfficeBuilder.build", function()
		it("builds one office per boss", function()
			local office = build()
			for _, boss in BossConfig.List do
				expect(office:FindFirstChild(boss.DisplayName .. " Office")).never.to.equal(nil)
			end
			office:Destroy()
		end)

		it("anchors every part", function()
			local office = build()
			for _, p in parts(office) do
				expect(p.Anchored).to.equal(true)
			end
			office:Destroy()
		end)

		it("puts each boss inside its own office", function()
			local half = ArenaConfig.OfficeSize / 2
			for _, entry in ArenaConfig.Offices do
				for _, spawn in ArenaConfig.BossSpawns do
					if spawn.BossId == entry.BossId then
						local offset = spawn.Position - entry.Center
						expect(math.abs(offset.X) < half.X - BOSS_CLEARANCE).to.equal(true)
						expect(math.abs(offset.Z) < half.Z - BOSS_CLEARANCE).to.equal(true)
					end
				end
			end
		end)

		it("keeps furniture clear of every boss", function()
			local office = build()
			for _, p in parts(office) do
				if p:GetAttribute(OfficeBuilder.FURNITURE_ATTRIBUTE) then
					for _, spawn in ArenaConfig.BossSpawns do
						expect(flatDistance(p.Position, spawn.Position) >= BOSS_CLEARANCE).to.equal(
							true
						)
					end
				end
			end
			office:Destroy()
		end)

		it("keeps the walk from each door to its boss free of furniture", function()
			local office = build()
			local doorHalf = ArenaConfig.DoorWidth / 2
			local frontZ = ArenaConfig.OfficeSize.Z / 2
			for _, entry in ArenaConfig.Offices do
				for _, p in parts(office) do
					if p:GetAttribute(OfficeBuilder.FURNITURE_ATTRIBUTE) then
						local offset = p.Position - entry.Center
						local inPath = math.abs(offset.X) < doorHalf
							and offset.Z > 0
							and offset.Z < frontZ
						expect(inPath).to.equal(false)
					end
				end
			end
			office:Destroy()
		end)

		it("leaves each doorway open", function()
			local office = build()
			for _, entry in ArenaConfig.Offices do
				local doorway = entry.Center
					+ Vector3.new(0, ArenaConfig.DoorHeight / 2, ArenaConfig.OfficeSize.Z / 2)
				for _, p in parts(office) do
					expect(contains(p, doorway)).to.equal(false)
				end
			end
			office:Destroy()
		end)

		it("keeps the spawn point in the lobby, clear of rooms and props", function()
			local office = build()
			local spawn = ArenaConfig.SpawnPosition + Vector3.new(0, 3, 0)
			for _, p in parts(office) do
				expect(contains(p, spawn)).to.equal(false)
			end
			for _, entry in ArenaConfig.Offices do
				expect(math.abs(spawn.Z - entry.Center.Z) > ArenaConfig.OfficeSize.Z / 2).to.equal(
					true
				)
			end
			office:Destroy()
		end)
	end)
	describe("OfficeBuilder upper floor", function()
		it("builds stairs whose top step meets the upper floor", function()
			local office = build()
			local highest = -math.huge
			local steps = 0
			for _, p in parts(office) do
				if p.Name == "Step" then
					steps += 1
					highest = math.max(highest, p.Position.Y + p.Size.Y / 2)
				end
			end
			expect(steps > 0).to.equal(true)
			expect(highest).to.equal(ArenaConfig.UpperFloorY)
			office:Destroy()
		end)

		it("keeps every step a comfortable 1-stud climb", function()
			expect(ArenaConfig.Stairs.StepHeight <= 1).to.equal(true)
			expect(ArenaConfig.Stairs.StepDepth >= 1).to.equal(true)
		end)

		it("leaves the top of the stairs open to the upper corridor", function()
			local office = build()
			local stairs = ArenaConfig.Stairs
			-- Just above the landing, where a player steps off the stairs.
			local stepOff = Vector3.new(stairs.X, ArenaConfig.UpperFloorY + 2, 0.2)
			for _, p in parts(office) do
				expect(contains(p, stepOff)).to.equal(false)
			end
			office:Destroy()
		end)

		it("puts Senior offices on the upper floor", function()
			for _, entry in ArenaConfig.Offices do
				local isSenior = string.sub(entry.BossId, 1, 7) == "senior_"
				expect(entry.Center.Y).to.equal(if isSenior then ArenaConfig.UpperFloorY else 0)
			end
		end)
	end)
	describe("OfficeBuilder eye comfort", function()
		-- Perceived brightness, 0 (black) .. 1 (white).
		local function luminance(color: Color3): number
			return 0.2126 * color.R + 0.7152 * color.G + 0.0722 * color.B
		end

		local SURFACE_NAMES = {
			"Wall",
			"Slab",
			"Roof",
			"Lintel",
			"LobbyFront",
			"Carpet",
		}
		local function isLargeSurface(p: BasePart): boolean
			for _, fragment in SURFACE_NAMES do
				if string.find(p.Name, fragment, 1, true) then
					return true
				end
			end
			return false
		end

		it("keeps walls, ceilings and carpets muted (no near-white surfaces)", function()
			local office = build()
			local checked = 0
			for _, p in parts(office) do
				if isLargeSurface(p) and p.Material ~= Enum.Material.Glass then
					checked += 1
					expect(luminance(p.Color) <= 0.45).to.equal(true)
				end
			end
			expect(checked > 0).to.equal(true)
			office:Destroy()
		end)

		it("keeps every light dim", function()
			local office = build()
			for _, light in office:GetDescendants() do
				if light:IsA("PointLight") then
					expect(light.Brightness <= 1).to.equal(true)
				end
			end
			office:Destroy()
		end)

		it("uses glowing Neon only for thin accent strips", function()
			local office = build()
			for _, p in parts(office) do
				if p.Material == Enum.Material.Neon then
					local thinnest = math.min(p.Size.X, p.Size.Y, p.Size.Z)
					expect(thinnest <= 0.3).to.equal(true)
					expect(p.Transparency > 0).to.equal(true)
				end
			end
			office:Destroy()
		end)
	end)
end
