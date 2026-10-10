--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local TowerRules = require(ReplicatedStorage.Shared.TowerRules)

local function allBeaten(): { [string]: number }
	local defeats: { [string]: number } = {}
	for _, boss in BossConfig.List do
		if not boss.UnlockAfterAllBosses then
			defeats[boss.Id] = 1
		end
	end
	return defeats
end

return function()
	describe("TowerRules floors", function()
		it("lists floors bottom first with rising heights and numbers", function()
			local floors = TowerRules.floors()
			expect(#floors >= 4).to.equal(true)
			for index = 2, #floors do
				expect(floors[index].FloorY > floors[index - 1].FloorY).to.equal(true)
				expect(floors[index].Number).to.equal(floors[index - 1].Number + 1)
			end
			expect(TowerRules.floor("Department")).to.be.ok()
			expect(TowerRules.floor("Basement")).to.equal(nil)
		end)

		it("knows which floor a position is on", function()
			for _, floor in TowerRules.floors() do
				local spot = Vector3.new(-40, floor.FloorY + 3, -10)
				expect((TowerRules.floorAt(spot) :: TowerRules.Floor).Id).to.equal(floor.Id)
			end
			expect(TowerRules.floorAt(Vector3.new(0, 3, 400))).to.equal(nil) -- outside
		end)

		it("only accepts rides asked for at a door", function()
			for _, floor in TowerRules.floors() do
				local door = TowerRules.door(floor.Id) :: Vector3
				expect(TowerRules.atDoor(door + Vector3.new(5, -1, 0), 10)).to.equal(true)
			end
			expect(TowerRules.atDoor(Vector3.new(0, 3, 20), 10)).to.equal(false) -- the lobby spawn
		end)

		it("lands riders on the floor they asked for", function()
			for _, floor in TowerRules.floors() do
				local arrival = TowerRules.arrival(floor.Id) :: Vector3
				expect((TowerRules.floorAt(arrival) :: TowerRules.Floor).Id).to.equal(floor.Id)
			end
		end)
	end)

	describe("TowerRules access", function()
		it("always opens the ground and Senior floors", function()
			expect(TowerRules.status("Ground", {}, 1, nil, false).Open).to.equal(true)
			expect(TowerRules.status("Senior", {}, 1, nil, false).Open).to.equal(true)
		end)

		it("opens the Executive Floor like the CEO, with progress while locked", function()
			local level = GameConfig.UpstairsMinLevel
			expect(TowerRules.status("Executive", allBeaten(), level, nil, false).Open).to.equal(
				true
			)
			local locked = TowerRules.status("Executive", {}, level, nil, false)
			expect(locked.Open).to.equal(false)
			expect(locked.Progress).to.equal(0)
			expect((string.find(locked.Reason, "to go", 1, true))).to.be.ok()
			local low = TowerRules.status("Executive", allBeaten(), 1, nil, false)
			expect(low.Open).to.equal(false)
			expect((string.find(low.Reason, "Level", 1, true))).to.be.ok()
		end)

		it("opens the 4th floor at Level 30", function()
			local needed = GameConfig.PrincipalMinLevel
			expect(TowerRules.status("Department", {}, needed, nil, false).Open).to.equal(true)
			local locked = TowerRules.status("Department", {}, needed - 8, nil, false)
			expect(locked.Open).to.equal(false)
			expect(math.abs(locked.Progress - (needed - 8) / needed) < 1e-9).to.equal(true)
			expect(locked.Reason).to.equal(
				string.format("Reach Level %d (you're Level %d)", needed, needed - 8)
			)
		end)

		it("opens everything for an admin's bypass, and nothing that doesn't exist", function()
			expect(TowerRules.status("Department", {}, 1, nil, true).Open).to.equal(true)
			expect(TowerRules.status("Executive", {}, 1, nil, true).Open).to.equal(true)
			expect(TowerRules.status("Basement", {}, 99, nil, false).Open).to.equal(false)
		end)

		it("matches the Executive Floor's own config", function()
			expect((TowerRules.floor("Executive") :: TowerRules.Floor).FloorY).to.equal(
				ArenaConfig.Executive.FloorY
			)
		end)
	end)
end
