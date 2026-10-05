--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local BossConfig = require(ReplicatedStorage.Config.BossConfig)

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
end
