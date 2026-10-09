--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local FurnitureRules = require(ReplicatedStorage.Shared.FurnitureRules)
local OfficeConfig = require(ReplicatedStorage.Config.OfficeConfig)
local OfficeWingBuilder = require(ServerScriptService.Lib.OfficeWingBuilder)

local function build(index: number): (OfficeWingBuilder.Room, Folder)
	local folder = Instance.new("Folder")
	return OfficeWingBuilder.buildRoom(index, folder), folder
end

return function()
	describe("OfficeWingBuilder.buildRoom", function()
		it("puts the floor's top at the slot's origin, in its own model", function()
			local room, folder = build(2)
			expect(room.Floor.Position).to.equal(FurnitureRules.slotOrigin(2))
			local floor = room.Model:FindFirstChild("Floor") :: BasePart
			expect(math.abs(floor.Position.Y + floor.Size.Y / 2 - room.Floor.Position.Y) < 0.01).to.equal(
				true
			)
			expect(room.Model:GetAttribute(OfficeWingBuilder.SLOT_ATTRIBUTE)).to.equal(2)
			expect(room.Furniture.Parent).to.equal(room.Model)
			folder:Destroy()
		end)

		it("closes the room: walls all round, a ceiling, the door shut", function()
			local room, folder = build(1)
			local half = OfficeConfig.RoomSize / 2
			-- A ray from the middle of the room at head height hits a wall or
			-- the door in every direction, and the ceiling straight up.
			local centre = room.Floor.Position + Vector3.new(0, 5, 0)
			local cast = RaycastParams.new()
			cast.FilterType = Enum.RaycastFilterType.Include
			cast.FilterDescendantsInstances = { room.Model }
			folder.Parent = workspace
			for _, direction in
				{ Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis, Vector3.yAxis }
			do
				local hit = workspace:Raycast(centre, direction * (half + 10), cast)
				expect(hit).never.to.equal(nil)
			end
			folder:Destroy()
		end)

		it("keeps the arrival spot clear and inside the room", function()
			local room, folder = build(3)
			folder.Parent = workspace
			local arrival = (room.Floor * CFrame.new(OfficeConfig.Arrival)).Position
			expect(FurnitureRules.slotAt(arrival, 3)).to.equal(3)
			local params = OverlapParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { room.Model }
			local blocking =
				workspace:GetPartBoundsInBox(CFrame.new(arrival), Vector3.new(3, 4, 3), params)
			expect(#blocking).to.equal(0)
			folder:Destroy()
		end)

		it("stays light: anchored parts, one soft light, no shadows", function()
			local room, folder = build(1)
			local parts, lights = 0, 0
			for _, descendant in room.Model:GetDescendants() do
				if descendant:IsA("BasePart") then
					parts += 1
					expect(descendant.Anchored).to.equal(true)
				elseif descendant:IsA("Light") then
					lights += 1
					expect(descendant.Brightness <= 1).to.equal(true)
					expect(descendant.Shadows).to.equal(false)
				end
			end
			expect(parts <= 20).to.equal(true)
			expect(lights).to.equal(1)
			folder:Destroy()
		end)
	end)
end
