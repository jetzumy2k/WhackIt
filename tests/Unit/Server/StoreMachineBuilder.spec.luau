--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local OfficeBuilder = require(ServerScriptService.Lib.OfficeBuilder)
local StoreMachineBuilder = require(ServerScriptService.Lib.StoreMachineBuilder)

type Box = { MinX: number, MaxX: number, MinY: number, MaxY: number, MinZ: number, MaxZ: number }

local function build(): Model
	return StoreMachineBuilder.build(Instance.new("Folder"))
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

-- World-space box of a (possibly turned) part.
local function box(part: BasePart): Box
	local cf = part.CFrame
	local half = part.Size / 2
	local function extent(axis: Vector3): number
		return math.abs(cf.RightVector:Dot(axis)) * half.X
			+ math.abs(cf.UpVector:Dot(axis)) * half.Y
			+ math.abs(cf.LookVector:Dot(axis)) * half.Z
	end
	local p = cf.Position
	local ex, ey, ez = extent(Vector3.xAxis), extent(Vector3.yAxis), extent(Vector3.zAxis)
	return {
		MinX = p.X - ex,
		MaxX = p.X + ex,
		MinY = p.Y - ey,
		MaxY = p.Y + ey,
		MinZ = p.Z - ez,
		MaxZ = p.Z + ez,
	}
end

local function overlaps(a: Box, b: Box): boolean
	return a.MinX < b.MaxX
		and a.MaxX > b.MinX
		and a.MinY < b.MaxY
		and a.MaxY > b.MinY
		and a.MinZ < b.MaxZ
		and a.MaxZ > b.MinZ
end

local function solidParts(root: Instance): { BasePart }
	local list: { BasePart } = {}
	for _, part in parts(root) do
		if part.CanCollide then
			table.insert(list, part)
		end
	end
	return list
end

-- Keep-clear zones (floor to head height).
local function zone(minX: number, maxX: number, minZ: number, maxZ: number): Box
	return { MinX = minX, MaxX = maxX, MinY = 0.05, MaxY = 6, MinZ = minZ, MaxZ = maxZ }
end

return function()
	describe("StoreMachineBuilder.build", function()
		it("has one E prompt that opens the hammer store", function()
			local machine = build()
			local prompts = {}
			for _, descendant in machine:GetDescendants() do
				if descendant:IsA("ProximityPrompt") then
					table.insert(prompts, descendant)
				end
			end
			expect(#prompts).to.equal(1)
			local prompt = prompts[1] :: ProximityPrompt
			expect(prompt:GetAttribute(StoreMachineBuilder.PROMPT_ATTRIBUTE)).to.equal(true)
			expect(prompt.KeyboardKeyCode).to.equal(Enum.KeyCode.E)
			expect(prompt.HoldDuration).to.equal(0)
			expect(prompt.MaxActivationDistance <= 10).to.equal(true)
			expect((string.find(prompt.ActionText, "Hammer Store", 1, true))).never.to.equal(nil)
			machine:Destroy()
		end)

		it("stays light: few parts, no lights or particles, thin neon only", function()
			local machine = build()
			local list = parts(machine)
			expect(#list <= 90).to.equal(true)
			local neon = 0
			for _, part in list do
				if
					part.Material == Enum.Material.Neon
					and part.Name ~= "Pommel"
					and part.Name ~= "Star"
				then
					if part:GetAttribute(StoreMachineBuilder.GLOW_ATTRIBUTE) == true then
						neon += 1
						expect(part.CanCollide).to.equal(false)
						-- Sizes are stored as 32-bit floats (0.1 reads back as 0.1000000015).
						expect(math.min(part.Size.X, part.Size.Y, part.Size.Z) <= 0.12).to.equal(
							true
						)
					end
				end
			end
			expect(neon <= 4).to.equal(true)
			for _, descendant in machine:GetDescendants() do
				expect(descendant:IsA("Light")).to.equal(false)
				expect(descendant:IsA("ParticleEmitter")).to.equal(false)
			end
			machine:Destroy()
		end)

		it("holds every part in place (anchored, or welded to an anchored display root)", function()
			local machine = build()
			for _, part in parts(machine) do
				if not part.Anchored then
					local display = part:FindFirstAncestorWhichIsA("Model")
					expect(display).never.to.equal(machine)
					local root = (display :: Model).PrimaryPart
					expect(root).never.to.equal(nil)
					expect((root :: BasePart).Anchored).to.equal(true)
				end
			end
			machine:Destroy()
		end)

		it("shows three display hammers", function()
			local machine = build()
			local displays = 0
			for _, child in machine:GetChildren() do
				if
					child:IsA("Model") and child:GetAttribute(StoreMachineBuilder.DISPLAY_ATTRIBUTE)
				then
					displays += 1
				end
			end
			expect(displays).to.equal(3)
			machine:Destroy()
		end)
	end)

	describe("StoreMachineBuilder placement", function()
		it("stands inside the lobby, on the floor", function()
			local machine = build()
			for _, part in solidParts(machine) do
				local b = box(part)
				expect(b.MinX >= -36 and b.MaxX <= 36).to.equal(true)
				expect(b.MinZ >= 0 and b.MaxZ <= ArenaConfig.BuildingSouthZ).to.equal(true)
				expect(b.MinY >= -0.01).to.equal(true)
			end
			machine:Destroy()
		end)

		it(
			"keeps the stairs, their landing, the spawn, the entrance and the leaderboard clear",
			function()
				local machine = build()
				local stairs = ArenaConfig.Stairs
				local half = stairs.Width / 2
				local campus = ArenaConfig.Campus
				local spawn = ArenaConfig.SpawnPosition
				local keepClear = {
					-- The stairs themselves and a 1-stud margin on their open side.
					zone(stairs.X - half - 1, stairs.X + half, 0, stairs.BottomZ),
					-- The landing in front of the bottom step, out to the front wall.
					zone(
						stairs.X - half - 2,
						stairs.X + half,
						stairs.BottomZ,
						ArenaConfig.BuildingSouthZ
					),
					zone(spawn.X - 6, spawn.X + 6, spawn.Z - 6, spawn.Z + 6),
					zone(
						-campus.EntranceWidth / 2 - 1,
						campus.EntranceWidth / 2 + 1,
						20,
						ArenaConfig.BuildingSouthZ
					),
					-- Leaderboard wall and the space in front of it.
					zone(-36, -26, 6, 28),
				}
				for _, part in solidParts(machine) do
					for _, area in keepClear do
						expect(overlaps(box(part), area)).to.equal(false)
					end
				end
				machine:Destroy()
			end
		)

		it("leaves the walk from the spawn to the bottom of the stairs open", function()
			local machine = build()
			local spawn = ArenaConfig.SpawnPosition
			local stairs = ArenaConfig.Stairs
			local foot = Vector3.new(stairs.X, 0, stairs.BottomZ + 2)
			for step = 0, 40 do
				local point = spawn:Lerp(foot, step / 40)
				local lane = zone(point.X - 1.5, point.X + 1.5, point.Z - 1.5, point.Z + 1.5)
				for _, part in solidParts(machine) do
					expect(overlaps(box(part), lane)).to.equal(false)
				end
			end
			machine:Destroy()
		end)

		it("doesn't overlap the lobby's walls, stairs or furniture", function()
			local machine = build()
			local office = OfficeBuilder.build(Instance.new("Folder"))
			for _, mine in solidParts(machine) do
				local mineBox = box(mine)
				for _, theirs in solidParts(office) do
					if overlaps(mineBox, box(theirs)) then
						error(string.format("%s overlaps %s", mine.Name, theirs:GetFullName()))
					end
				end
			end
			office:Destroy()
			machine:Destroy()
		end)
	end)
end
