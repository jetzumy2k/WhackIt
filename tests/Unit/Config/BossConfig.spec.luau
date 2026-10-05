--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Config.BossConfig)

local function isPositiveFinite(value: number): boolean
	-- value == value rejects NaN.
	return value == value and value > 0 and value < math.huge
end

return function()
	describe("BossConfig", function()
		it("defines at least one boss", function()
			expect(#BossConfig > 0).to.equal(true)
		end)

		it("uses unique, non-empty ids", function()
			local seen: { [string]: boolean } = {}
			for _, boss in BossConfig do
				expect(#boss.Id > 0).to.equal(true)
				expect(seen[boss.Id]).to.equal(nil)
				seen[boss.Id] = true
			end
		end)

		it("has display text for every boss", function()
			for _, boss in BossConfig do
				expect(#boss.DisplayName > 0).to.equal(true)
				expect(#boss.Description > 0).to.equal(true)
			end
		end)

		it("uses positive, finite numeric stats", function()
			for _, boss in BossConfig do
				expect(isPositiveFinite(boss.MaxHealth)).to.equal(true)
				expect(isPositiveFinite(boss.HitDamage)).to.equal(true)
				expect(isPositiveFinite(boss.ScoreReward)).to.equal(true)
			end
		end)
	end)
end
