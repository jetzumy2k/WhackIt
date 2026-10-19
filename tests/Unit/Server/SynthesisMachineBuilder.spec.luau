--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local OfficeBuilder = require(ServerScriptService.Lib.OfficeBuilder)
local StoreMachineBuilder = require(ServerScriptService.Lib.StoreMachineBuilder)
local SynthesisConfig = require(ReplicatedStorage.Config.SynthesisConfig)
local SynthesisMachineBuilder = require(ServerScriptService.Lib.SynthesisMachineBuilder)

type Box = { MinX: number, MaxX: number, MinY: number, MaxY: number, MinZ: number, MaxZ: number }

local function build(): Model
	return SynthesisMachineBuilder.build(Instance.new("Folder"))
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

local function solidParts(root: Instance): { BasePart }
	local list: { BasePart } = {}
	for _, part in parts(root) do
		if part.CanCollide then
			table.insert(list, part)
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

local function grow(b: Box, by: number): Box
	return {
		MinX = b.MinX - by,
		MaxX = b.MaxX + by,
		MinY = b.MinY,
		MaxY = b.MaxY,
		MinZ = b.MinZ - by,
		MaxZ = b.MaxZ + by,
	}
end

-- Keep-clear zones (floor to head height).
local function zone(minX: number, maxX: number, minZ: number, maxZ: number): Box
	return { MinX = minX, MaxX = maxX, MinY = 0.05, MaxY = 6, MinZ = minZ, MaxZ = maxZ }
end

local function prompts(model: Model): { ProximityPrompt }
	local list: { ProximityPrompt } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			table.insert(list, descendant)
		end
	end
	return list
end

return function()
	describe("SynthesisMachineBuilder.build", function()
		it("has one E prompt that says Synthesize", function()
			local machine = build()
			local list = prompts(machine)
			expect(#list).to.equal(1)
			local prompt = list[1]
			expect(prompt.Name).to.equal(SynthesisMachineBuilder.PROMPT_NAME)
			expect(prompt:GetAttribute(SynthesisMachineBuilder.PROMPT_ATTRIBUTE)).to.equal(true)
			expect(prompt.KeyboardKeyCode).to.equal(Enum.KeyCode.E)
			expect(prompt.HoldDuration).to.equal(0)
			expect(prompt.ActionText).to.equal("Synthesize")
			expect(prompt.MaxActivationDistance <= 10).to.equal(true)
			machine:Destroy()
		end)

		it("puts the server's reach check where the prompt is, wider than the prompt", function()
			local machine = build()
			local anchor = prompts(machine)[1].Parent :: Attachment
			local gap = (anchor.WorldPosition - SynthesisMachineBuilder.promptPosition()).Magnitude
			expect(gap < 0.01).to.equal(true)
			expect(SynthesisConfig.Reach > SynthesisMachineBuilder.PROMPT_DISTANCE).to.equal(true)
			machine:Destroy()
		end)

		it("stays light: few parts, one soft light, two small emitters", function()
			local machine = build()
			expect(#parts(machine) <= 70).to.equal(true)
			local lights, emitters = 0, 0
			for _, descendant in machine:GetDescendants() do
				if descendant:IsA("Light") then
					lights += 1
					expect((descendant :: PointLight).Shadows).to.equal(false)
				elseif descendant:IsA("ParticleEmitter") then
					emitters += 1
					expect(descendant.Rate <= 5).to.equal(true)
				end
			end
			expect(lights).to.equal(1)
			expect(emitters).to.equal(2)
			machine:Destroy()
		end)

		it("holds every part in place (anchored, or welded to an anchored ring root)", function()
			local machine = build()
			local rings = 0
			for _, child in machine:GetChildren() do
				if child:IsA("Model") then
					rings += 1
					expect(child:GetAttribute(SynthesisMachineBuilder.RING_ATTRIBUTE)).never.to.equal(
						nil
					)
				end
			end
			expect(rings).to.equal(2)
			for _, part in parts(machine) do
				if not part.Anchored then
					local ring = part:FindFirstAncestorWhichIsA("Model")
					expect(ring).never.to.equal(machine)
					local root = (ring :: Model).PrimaryPart
					expect(root).never.to.equal(nil)
					expect((root :: BasePart).Anchored).to.equal(true)
					expect(part.CanCollide).to.equal(false)
				end
			end
			machine:Destroy()
		end)

		it("has four input sockets, an output orb and a sign", function()
			local machine = build()
			local slots = 0
			for _, part in parts(machine) do
				if part:GetAttribute(SynthesisMachineBuilder.SLOT_ATTRIBUTE) then
					slots += 1
				end
			end
			expect(slots).to.equal(SynthesisMachineBuilder.SLOT_COUNT)
			expect(machine:FindFirstChild("OutputOrb")).never.to.equal(nil)
			expect(machine:FindFirstChild("Core")).never.to.equal(nil)
			expect(machine:FindFirstChild("Nameplate", true)).never.to.equal(nil)
			expect(machine:GetAttribute(SynthesisMachineBuilder.PLAY_ATTRIBUTE)).to.equal(0)
			machine:Destroy()
		end)
	end)

	describe("SynthesisMachineBuilder placement", function()
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
					zone(stairs.X - half - 1, stairs.X + half, 0, stairs.BottomZ),
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
					zone(-36, -26, 6, 28),
				}
				for _, part in parts(machine) do
					for _, area in keepClear do
						if overlaps(box(part), area) then
							error(part.Name .. " is in a keep-clear zone")
						end
					end
				end
				machine:Destroy()
			end
		)

		it("leaves walking room beside the hammer vending machine", function()
			local machine = build()
			local vendor = StoreMachineBuilder.build(Instance.new("Folder"))
			for _, mine in parts(machine) do
				-- At least 3 studs of open floor between the two machines.
				local around = grow(box(mine), 3)
				for _, theirs in parts(vendor) do
					if overlaps(around, box(theirs)) then
						error(string.format("%s is within 3 studs of %s", mine.Name, theirs.Name))
					end
				end
			end
			vendor:Destroy()
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
