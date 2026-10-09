--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local CourtBuilder = require(ServerScriptService.Lib.CourtBuilder)
local PickleballConfig = require(ReplicatedStorage.Config.PickleballConfig)

local COURT = PickleballConfig.Court

local function parts(root: Instance): { BasePart }
	local list: { BasePart } = {}
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(list, descendant)
		end
	end
	return list
end

return function()
	describe("CourtBuilder.build", function()
		it("builds every court with a board, and the sign's prompt", function()
			local holder = Instance.new("Folder")
			local center = CourtBuilder.build(holder)
			expect(#center.Courts).to.equal(#PickleballConfig.Center.Courts)
			for index, court in center.Courts do
				expect(court.Index).to.equal(index)
				expect(court.Model:GetAttribute(CourtBuilder.COURT_ATTRIBUTE)).to.equal(index)
				expect(court.Board.Text).to.equal(string.format("Court %d\nFree", index))
			end
			expect(center.Prompt.Name).to.equal(CourtBuilder.PROMPT_NAME)
			expect(center.Folder.Parent).to.equal(holder)
			holder:Destroy()
		end)

		it("keeps everything anchored and inside the campus", function()
			local holder = Instance.new("Folder")
			CourtBuilder.build(holder)
			local box = ArenaConfig.Campus.Boundary
			for _, part in parts(holder) do
				expect(part.Anchored).to.equal(true)
				local half = part.Size / 2
				local p = part.Position
				local within = p.X - half.X >= box.MinX
					and p.X + half.X <= box.MaxX
					and p.Z - half.Z >= box.MinZ
					and p.Z + half.Z <= box.MaxZ
				if not within then
					error(part:GetFullName() .. " sticks out of the campus")
				end
			end
			holder:Destroy()
		end)

		it("paints the lines without collisions and walls off the net", function()
			local holder = Instance.new("Folder")
			local center = CourtBuilder.build(holder)
			local court = center.Courts[1]
			local walls = 0
			for _, part in parts(court.Model) do
				if part.Name == "Line" or part.Name == "Sideline" or part.Name == "Surface" then
					expect(part.CanCollide).to.equal(false)
				end
				if part.Name == CourtBuilder.NET_WALL_NAME then
					walls += 1
					expect(part.CanCollide).to.equal(true)
					expect(part.Transparency).to.equal(1)
					expect(math.abs(part.Position.Z - court.Center.Z) < 0.01).to.equal(true)
					expect(part.Size.X >= COURT.Width + 2 * COURT.RunOff).to.equal(true)
				end
			end
			expect(walls).to.equal(1)
			holder:Destroy()
		end)

		it("converts between court-local and world points", function()
			local origin = PickleballConfig.Center.Courts[1]
			local point = Vector3.new(3, 1, -9)
			expect(CourtBuilder.toLocal(origin, CourtBuilder.toWorld(origin, point))).to.equal(
				point
			)
		end)
	end)
end
