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
			for i, a in ArenaConfig.BossSpawns do
				for j, b in ArenaConfig.BossSpawns do
					if i < j then
						expect((a.Position - b.Position).Magnitude > 2 * GameConfig.HitReach).to.equal(
							true
						)
					end
				end
			end
		end)
	end)
end
