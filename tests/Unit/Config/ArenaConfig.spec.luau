--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)

return function()
	describe("ArenaConfig", function()
		it("spawns at least one boss", function()
			expect(#ArenaConfig.BossSpawns > 0).to.equal(true)
		end)

		it("only spawns bosses that exist in BossConfig", function()
			for _, spawn in ArenaConfig.BossSpawns do
				expect(BossConfig.ById[spawn.BossId]).never.to.equal(nil)
			end
		end)

		it("places every boss body above the floor (floor top is Y = 0)", function()
			local halfHeight = ArenaConfig.PlaceholderBossSize.Y / 2
			for _, spawn in ArenaConfig.BossSpawns do
				expect(spawn.Position.Y - halfHeight >= 0).to.equal(true)
			end
		end)

		it("is read-only", function()
			expect(table.isfrozen(ArenaConfig)).to.equal(true)
			expect(table.isfrozen(ArenaConfig.BossSpawns)).to.equal(true)
		end)
	end)
	describe("ArenaConfig stations", function()
		it("has exactly one station per boss", function()
			local seen: { [string]: number } = {}
			for _, spawn in ArenaConfig.BossSpawns do
				seen[spawn.BossId] = (seen[spawn.BossId] or 0) + 1
			end
			for _, boss in BossConfig.List do
				expect(seen[boss.Id]).to.equal(1)
			end
		end)

		it("spaces stations so one swing can only reach one boss", function()
			-- Server reach, including its lag grace.
			local reach = GameConfig.HitReach + GameConfig.HitReachGrace
			-- Height of a standing player's root above their floor.
			local ROOT_HEIGHT = 3
			for i, a in ArenaConfig.BossSpawns do
				for j, b in ArenaConfig.BossSpawns do
					if i < j then
						local floorA = a.FloorY
						local floorB = b.FloorY
						if floorA == floorB then
							expect((a.Position - b.Position).Magnitude > 2 * reach).to.equal(true)
						else
							-- A player standing on either floor can't reach the other floor's boss.
							expect(math.abs(floorA + ROOT_HEIGHT - b.Position.Y) > reach).to.equal(
								true
							)
							expect(math.abs(floorB + ROOT_HEIGHT - a.Position.Y) > reach).to.equal(
								true
							)
						end
					end
				end
			end
		end)
	end)
	describe("ArenaConfig Executive Floor", function()
		it("puts the CEO on the executive floor", function()
			local found = false
			for _, spawn in ArenaConfig.BossSpawns do
				if spawn.BossId == ArenaConfig.Executive.CeoBossId then
					found = true
					expect(spawn.FloorY).to.equal(ArenaConfig.Executive.FloorY)
				end
			end
			expect(found).to.equal(true)
		end)

		it("stands every boss on its floor, whatever its size", function()
			for _, spawn in ArenaConfig.BossSpawns do
				-- Vector3 stores 32-bit floats (e.g. 30 + 6.4 reads back as 36.4000015),
				-- so compare to a thousandth of a stud.
				expect(math.abs(spawn.Position.Y - spawn.Size.Y / 2 - spawn.FloorY) < 1e-3).to.equal(
					true
				)
			end
		end)

		it("lands elevator riders on the right floors", function()
			local executive = ArenaConfig.Executive
			expect(executive.ArriveUp.Y > executive.FloorY).to.equal(true)
			expect(executive.ArriveDown.Y > ArenaConfig.UpperFloorY).to.equal(true)
			expect(executive.ArriveDown.Y < executive.FloorY).to.equal(true)
		end)
	end)
end
