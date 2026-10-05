--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local Checks = require(ServerScriptService.Tests.Helpers.Checks)

return function()
	describe("BossConfig", function()
		it("defines at least one boss", function()
			expect(#BossConfig.List > 0).to.equal(true)
		end)

		it("uses unique, non-empty ids", function()
			local seen: { [string]: boolean } = {}
			for _, boss in BossConfig.List do
				expect(Checks.isNonEmptyString(boss.Id)).to.equal(true)
				expect(seen[boss.Id]).to.equal(nil)
				seen[boss.Id] = true
			end
		end)

		it("indexes every listed boss by id", function()
			local count = 0
			for id, boss in BossConfig.ById do
				expect(boss.Id).to.equal(id)
				count += 1
			end
			expect(count).to.equal(#BossConfig.List)
			for _, boss in BossConfig.List do
				expect(BossConfig.ById[boss.Id]).to.equal(boss)
			end
		end)

		it("has display text for every boss", function()
			for _, boss in BossConfig.List do
				expect(Checks.isNonEmptyString(boss.DisplayName)).to.equal(true)
				expect(Checks.isNonEmptyString(boss.Description)).to.equal(true)
			end
		end)

		it("uses positive, finite numeric stats", function()
			for _, boss in BossConfig.List do
				expect(Checks.isPositiveFinite(boss.MaxHealth)).to.equal(true)
				expect(Checks.isPositiveFinite(boss.DamageTakenMultiplier)).to.equal(true)
				expect(Checks.isPositiveFinite(boss.ScoreReward)).to.equal(true)
			end
		end)

		it("is read-only at every level", function()
			expect(table.isfrozen(BossConfig)).to.equal(true)
			expect(table.isfrozen(BossConfig.List)).to.equal(true)
			expect(table.isfrozen(BossConfig.ById)).to.equal(true)
			for _, boss in BossConfig.List do
				expect(table.isfrozen(boss)).to.equal(true)
			end
		end)
	end)
	describe("BossConfig progression", function()
		it("gives positive coin rewards", function()
			for _, boss in BossConfig.List do
				expect(Checks.isPositiveFinite(boss.CoinReward)).to.equal(true)
			end
		end)

		it(
			"needs nothing for the first boss and at least one defeat for every later boss",
			function()
				for index, boss in BossConfig.List do
					if index == 1 then
						expect(boss.UnlockDefeats).to.equal(0)
					else
						expect(boss.UnlockDefeats >= 1).to.equal(true)
						expect(boss.UnlockDefeats % 1).to.equal(0)
					end
				end
			end
		)
	end)
end
