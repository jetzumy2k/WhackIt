--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local OfficeBuilder = require(ServerScriptService.Lib.OfficeBuilder)
local TowerRules = require(ReplicatedStorage.Shared.TowerRules)

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
						-- Only bosses on the same floor share the room with this furniture.
						local sameFloor = p.Position.Y >= spawn.FloorY
							and p.Position.Y < spawn.FloorY + 14
						if sameFloor then
							-- Clearance grows with bigger bosses (the CEO).
							local needed = BOSS_CLEARANCE + spawn.Size.X / 2 - 3
							expect(flatDistance(p.Position, spawn.Position) >= needed).to.equal(
								true
							)
						end
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
						-- Only furniture on this office's own floor can be in the way.
						local sameFloor = offset.Y >= 0 and offset.Y < ArenaConfig.OfficeSize.Y
						local inPath = sameFloor
							and math.abs(offset.X) < doorHalf
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

		it("leaves a clear walk from the spawn out through the lobby entrance", function()
			local office = build()
			local campus = ArenaConfig.Campus
			local spawn = ArenaConfig.SpawnPosition
			-- Sample the straight line from the spawn to just outside the front,
			-- at knee, waist and head height.
			for z = spawn.Z, ArenaConfig.BuildingSouthZ + 3, 0.5 do
				for _, height in { 1, 3, 5 } do
					for _, x in { -2, 0, 2 } do
						local point = Vector3.new(x, height, z)
						for _, p in parts(office) do
							if p.CanCollide and contains(p, point) then
								error(
									string.format(
										"%s blocks the way out at %s",
										p.Name,
										tostring(point)
									)
								)
							end
						end
					end
				end
			end
			expect(campus.EntranceHeight > 6).to.equal(true)
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

		it("leaves open floor in front of the bottom step to walk onto the stairs", function()
			local office = build()
			local stairs = ArenaConfig.Stairs
			-- Room to approach: the front wall's inner face is well beyond the first step.
			expect(ArenaConfig.BuildingSouthZ - 0.5 - stairs.BottomZ >= 6).to.equal(true)
			-- Where a player stands to step on, at body height, across the stair's width.
			for _, dx in { -2, 0, 2 } do
				for _, dz in { 1, 3 } do
					local standAt = Vector3.new(stairs.X + dx, 2.5, stairs.BottomZ + dz)
					for _, p in parts(office) do
						if p.CanCollide and contains(p, standAt) then
							error(
								string.format(
									"%s blocks the foot of the stairs at %s",
									p.Name,
									tostring(standAt)
								)
							)
						end
					end
				end
			end
			office:Destroy()
		end)

		it("keeps the top step's landing on this side of the upper corridor", function()
			local stairs = ArenaConfig.Stairs
			local steps = math.round(ArenaConfig.UpperFloorY / stairs.StepHeight)
			expect(stairs.BottomZ - steps * stairs.StepDepth >= 0).to.equal(true)
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

		it("puts Senior offices on the upper floor and Principal offices on the 4th", function()
			for _, entry in ArenaConfig.Offices do
				local isSenior = string.sub(entry.BossId, 1, 7) == "senior_"
				local isPrincipal = string.sub(entry.BossId, 1, 10) == "principal_"
				expect(entry.Center.Y).to.equal(
					if isSenior
						then ArenaConfig.UpperFloorY
						elseif isPrincipal then ArenaConfig.DepartmentFloor.FloorY
						else 0
				)
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
	describe("OfficeBuilder Executive Floor", function()
		it("builds an elevator door on every floor", function()
			local office = build()
			for _, floor in ArenaConfig.Tower.Floors do
				local door = office:FindFirstChild(floor.DoorName, true)
				expect(door).never.to.equal(nil)
				expect(math.abs((door :: BasePart).Position.Y - (floor.FloorY + 4)) < 1e-3).to.equal(
					true
				)
			end
			office:Destroy()
		end)

		it("keeps the elevator arrival spots clear", function()
			local office = build()
			local executive = ArenaConfig.Executive
			local points = { executive.ArriveUp, executive.ArriveDown }
			for _, floor in ArenaConfig.Tower.Floors do
				table.insert(points, TowerRules.arrival(floor.Id) :: Vector3)
			end
			for _, point in points do
				for _, p in parts(office) do
					expect(contains(p, point)).to.equal(false)
				end
			end
			office:Destroy()
		end)

		it("gives each tower arrival a floor to stand on", function()
			local office = build()
			for _, floor in ArenaConfig.Tower.Floors do
				local arrival = TowerRules.arrival(floor.Id) :: Vector3
				local below = arrival - Vector3.new(0, 3.2, 0)
				local supported = floor.FloorY == 0 -- the ground floor is the baseplate
				for _, p in parts(office) do
					if p.CanCollide and contains(p, below) then
						supported = true
					end
				end
				expect(supported).to.equal(true)
			end
			office:Destroy()
		end)
	end)
	describe("OfficeBuilder tower shell (visual overhaul V1a)", function()
		it("wraps the tower in a curtain wall up to the roof, with a crown sign", function()
			local office = build()
			local top = ArenaConfig.Rooftop.FloorY
			local highest = 0
			for _, p in parts(office) do
				if p.Name == "CurtainGlass" then
					highest = math.max(highest, p.Position.Y + p.Size.Y / 2)
				end
			end
			expect(highest > top - 2).to.equal(true)
			expect(office:FindFirstChild("CrownSign", true)).never.to.equal(nil)
			office:Destroy()
		end)

		it(
			"builds the Break Room and the Meeting Room with open doorways from the corridor",
			function()
				local office = build()
				expect(office:FindFirstChild("Break Room", true)).never.to.equal(nil)
				expect(office:FindFirstChild("Meeting Room", true)).never.to.equal(nil)
				for _, side in { -1, 1 } do
					for _, z in { -1, 0, 1 } do
						local doorway = Vector3.new(side * 61, 4, z)
						for _, p in parts(office) do
							if p.CanCollide and contains(p, doorway) then
								error(
									p.Name
										.. " blocks the podium room doorway at "
										.. tostring(doorway)
								)
							end
						end
					end
				end
				office:Destroy()
			end
		)

		it("keeps the shell outside the floors players walk on", function()
			local office = build()
			local shell = office:FindFirstChild("Curtain Wall", true) :: Instance
			for _, p in parts(shell) do
				-- The tower's storeys (north block) and the podium under its roof.
				local position = p.Position
				local withinX = math.abs(position.X) < ArenaConfig.BuildingHalfWidth - 1
				local inTower = withinX
					and position.Z > ArenaConfig.BuildingNorthZ + 1
					and position.Z < -1
					and position.Y < ArenaConfig.Executive.CeilingY
				local inPodium = withinX
					and position.Z > 1
					and position.Z < ArenaConfig.BuildingSouthZ - 1
					and position.Y < ArenaConfig.RoofY
				expect(inTower or inPodium).to.equal(false)
			end
			office:Destroy()
		end)
	end)
	describe("OfficeBuilder Rooftop Lounge", function()
		it("builds the lounge with both boards and their prompts", function()
			local office = build()
			local roof = office:FindFirstChild("Rooftop Lounge", true)
			expect(roof).never.to.equal(nil)
			for _, name in { "MissionBoardPrompt", "EventBoardPrompt" } do
				local prompt = (roof :: Instance):FindFirstChild(name, true)
				expect(prompt).never.to.equal(nil)
				expect((prompt :: Instance):IsA("ProximityPrompt")).to.equal(true)
			end
			office:Destroy()
		end)

		it("keeps everything on the deck inside the parapet and above the CEO's ceiling", function()
			local office = build()
			local roof = office:FindFirstChild("Rooftop Lounge", true) :: Instance
			for _, p in parts(roof) do
				expect(math.abs(p.Position.X) <= ArenaConfig.BuildingHalfWidth).to.equal(true)
				expect(
					p.Position.Z >= ArenaConfig.Rooftop.NorthZ
						and p.Position.Z <= ArenaConfig.Rooftop.SouthZ
				).to.equal(true)
				expect(p.Position.Y >= ArenaConfig.Executive.CeilingY).to.equal(true)
			end
			office:Destroy()
		end)
	end)
	describe("OfficeBuilder interior finish (visual overhaul V1c)", function()
		it("finishes the lobby, the corridors and the podium rooms", function()
			local office = build()
			for _, name in
				{ "Lobby Finish", "Corridor Art", "Room Finish", "FloorGuide", "ReceptionFront" }
			do
				expect(office:FindFirstChild(name, true)).never.to.equal(nil)
			end
			office:Destroy()
		end)

		it("lists every tower floor on the floor guide", function()
			local office = build()
			local guide = office:FindFirstChild("FloorGuide", true) :: Instance
			local label = guide:FindFirstChildWhichIsA("TextLabel", true) :: TextLabel
			for _, floor in ArenaConfig.Tower.Floors do
				expect((string.find(label.Text, floor.Name, 1, true))).to.be.ok()
			end
			office:Destroy()
		end)
	end)
end
