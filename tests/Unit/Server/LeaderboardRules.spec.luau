--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local LeaderboardRules = require(ServerScriptService.Lib.LeaderboardRules)

local function entry(userId: number, score: number): LeaderboardRules.Entry
	return { UserId = userId, Name = "P" .. userId, Score = score }
end

return function()
	describe("LeaderboardRules.rank", function()
		it("orders by score, highest first", function()
			local top = LeaderboardRules.rank({ entry(1, 50), entry(2, 300), entry(3, 120) }, 10)
			expect(top[1].UserId).to.equal(2)
			expect(top[2].UserId).to.equal(3)
			expect(top[3].UserId).to.equal(1)
		end)

		it("breaks ties by UserId so the order is stable", function()
			local top = LeaderboardRules.rank({ entry(9, 100), entry(4, 100) }, 10)
			expect(top[1].UserId).to.equal(4)
		end)

		it("returns at most `limit` entries", function()
			local many = {}
			for id = 1, 25 do
				table.insert(many, entry(id, id))
			end
			expect(#LeaderboardRules.rank(many, 10)).to.equal(10)
		end)

		it("doesn't modify the input list", function()
			local list = { entry(1, 1), entry(2, 2) }
			LeaderboardRules.rank(list, 10)
			expect(list[1].UserId).to.equal(1)
		end)
	end)

	describe("LeaderboardRules text", function()
		it("adds thousands separators", function()
			expect(LeaderboardRules.formatScore(0)).to.equal("0")
			expect(LeaderboardRules.formatScore(999)).to.equal("999")
			expect(LeaderboardRules.formatScore(1000)).to.equal("1,000")
			expect(LeaderboardRules.formatScore(1234567)).to.equal("1,234,567")
		end)

		it("formats a row with rank, name and score", function()
			expect(LeaderboardRules.rowText(3, entry(7, 48600))).to.equal("3. P7  48,600")
		end)
	end)
end
