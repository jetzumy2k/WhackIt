--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local Checks = require(ServerScriptService.Tests.Helpers.Checks)
local NpcBuilder = require(ServerScriptService.Lib.NpcBuilder)
local NpcConfig = require(ReplicatedStorage.Config.NpcConfig)

type Box = { MinX: number, MaxX: number, MinY: number, MaxY: number, MinZ: number, MaxZ: number }

local function build(): Folder
	return NpcBuilder.build(Instance.new("Folder"))
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

local function zone(minX: number, maxX: number, minZ: number, maxZ: number): Box
	return { MinX = minX, MaxX = maxX, MinY = -1, MaxY = 10, MinZ = minZ, MaxZ = maxZ }
end

return function()
	describe("NpcConfig", function()
		it("has 3 to 5 NPCs with unique ids", function()
			expect(#NpcConfig.List >= 3 and #NpcConfig.List <= 5).to.equal(true)
			local seen: { [string]: boolean } = {}
			for _, npc in NpcConfig.List do
				expect(seen[npc.Id]).to.equal(nil)
				seen[npc.Id] = true
				expect(NpcConfig.ById[npc.Id]).to.equal(npc)
			end
		end)

		it("only says short, friendly lines", function()
			for _, npc in NpcConfig.List do
				expect(#npc.Lines > 0).to.equal(true)
				for _, line in npc.Lines do
					expect(#line > 0 and #line <= NpcConfig.MaxLineLength).to.equal(true)
					local found = Checks.blockedWord(line)
					if found then
						error(string.format("%q contains %q", line, found))
					end
				end
			end
		end)

		it("pairs chat partners with each other", function()
			for _, npc in NpcConfig.List do
				if npc.Partner then
					local partner = NpcConfig.ById[npc.Partner]
					expect(partner).never.to.equal(nil)
					expect(partner.Partner).to.equal(npc.Id)
				end
			end
		end)
	end)

	describe("NpcBuilder.build", function()
		it("builds every NPC, outside the bosses folder, without a Humanoid", function()
			local folder = build()
			expect(folder.Name).never.to.equal("Bosses")
			expect(#folder:GetChildren()).to.equal(#NpcConfig.List)
			for _, descendant in folder:GetDescendants() do
				expect(descendant:IsA("Humanoid")).to.equal(false)
				expect(descendant:IsA("Light")).to.equal(false)
				expect(descendant:IsA("ParticleEmitter")).to.equal(false)
			end
			folder:Destroy()
		end)

		it("never blocks, can't be hit or clicked, and stays small", function()
			local folder = build()
			for _, model in folder:GetChildren() do
				expect(#parts(model) <= 20).to.equal(true)
			end
			for _, part in parts(folder) do
				expect(part.CanCollide).to.equal(false)
				expect(part.CanQuery).to.equal(false)
				expect(part.CanTouch).to.equal(false)
			end
			folder:Destroy()
		end)

		it("holds every part in place: anchored roots, the rest welded to them", function()
			local folder = build()
			for _, model in folder:GetChildren() do
				for _, name in { NpcBuilder.BODY, NpcBuilder.HEAD, NpcBuilder.ARM } do
					local root = model:FindFirstChild(name)
					expect(root).never.to.equal(nil)
					expect((root :: BasePart).Anchored).to.equal(true)
				end
				for _, part in parts(model) do
					if not part.Anchored then
						local held = false
						for _, constraint in model:GetDescendants() do
							if
								constraint:IsA("WeldConstraint")
								and constraint.Part1 == part
								and constraint.Part0
								and constraint.Part0.Anchored
							then
								held = true
							end
						end
						expect(held).to.equal(true)
					end
				end
			end
			folder:Destroy()
		end)

		it("stands on the floor, never under it", function()
			local folder = build()
			for _, part in parts(folder) do
				expect(box(part).MinY >= -0.05).to.equal(true)
			end
			folder:Destroy()
		end)

		it("keeps the leaderboard, stairs, vending machine, spawn and entrance clear", function()
			local folder = build()
			local stairs = ArenaConfig.Stairs
			local machine = ArenaConfig.StoreMachine.Position
			local spawn = ArenaConfig.SpawnPosition
			local entrance = ArenaConfig.Campus.EntranceWidth / 2 + 1
			local keepClear = {
				-- The leaderboard and the floor in front of it.
				zone(-36, -26, 6, 28),
				zone(stairs.X - stairs.Width / 2 - 2, 36, 0, ArenaConfig.BuildingSouthZ),
				zone(machine.X - 4, machine.X + 4, machine.Z - 4, machine.Z + 4),
				zone(spawn.X - 6, spawn.X + 6, spawn.Z - 6, spawn.Z + 6),
				zone(-entrance, entrance, 20, ArenaConfig.BuildingSouthZ),
			}
			for _, part in parts(folder) do
				for _, area in keepClear do
					if overlaps(box(part), area) then
						error(string.format("%s is in a keep-clear area", part:GetFullName()))
					end
				end
			end
			folder:Destroy()
		end)
	end)
end
