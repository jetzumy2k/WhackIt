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

	describe("LeaderboardRules.merge", function()
		local function name(userId: number): string
			return "Offline" .. userId
		end

		it("combines the three stores' pages into one row per player", function()
			local rows = LeaderboardRules.merge({
				Score = { { UserId = 1, Value = 500 }, { UserId = 2, Value = 300 } },
				Xp = { { UserId = 2, Value = 9000 } },
				Coins = { { UserId = 1, Value = 40 } },
			}, {}, name)
			expect(#rows).to.equal(2)
			local byId: { [number]: LeaderboardRules.Row } = {}
			for _, row in rows do
				byId[row.UserId] = row
			end
			expect(byId[1].Score).to.equal(500)
			expect(byId[1].Coins).to.equal(40)
			expect(byId[1].Xp).to.equal(nil) -- unknown: shown as a dash
			expect(byId[2].Xp).to.equal(9000)
			expect(byId[2].Name).to.equal("Offline2")
		end)

		it("prefers the live values and names of players in this server", function()
			local rows = LeaderboardRules.merge(
				{ Score = { { UserId = 7, Value = 100 } } },
				{ { UserId = 7, Name = "Here", Score = 150, Xp = 180, Coins = 3 } },
				name
			)
			expect(#rows).to.equal(1)
			expect(rows[1].Name).to.equal("Here")
			expect(rows[1].Score).to.equal(150)
			expect(rows[1].Coins).to.equal(3)
		end)

		it("ignores bad values instead of showing them", function()
			local rows = LeaderboardRules.merge({
				Score = {
					{ UserId = 1, Value = -5 },
					{ UserId = 2, Value = 0 / 0 },
					{ UserId = 3, Value = math.huge },
					{ UserId = 0, Value = 10 },
				},
			}, {}, name)
			for _, row in rows do
				expect(row.Score).to.equal(nil)
			end
		end)
	end)

	describe("LeaderboardRules.rankBy and positionOf", function()
		local rows: { LeaderboardRules.Row } = {
			{ UserId = 1, Name = "A", Score = 10, Xp = 900, Coins = 5 },
			{ UserId = 2, Name = "B", Score = 30, Xp = 100 },
			{ UserId = 3, Name = "C", Score = 20, Coins = 50 },
		}

		it("ranks by the chosen stat, leaving out players without it", function()
			local byScore = LeaderboardRules.rankBy(rows, "Score", 10)
			expect(byScore[1].UserId).to.equal(2)
			expect(byScore[3].UserId).to.equal(1)
			local byCoins = LeaderboardRules.rankBy(rows, "Coins", 10)
			expect(#byCoins).to.equal(2)
			expect(byCoins[1].UserId).to.equal(3)
			expect(LeaderboardRules.rankBy(rows, "Xp", 10)[1].UserId).to.equal(1)
			expect(#LeaderboardRules.rankBy(rows, "Score", 2)).to.equal(2)
		end)

		it("finds a player's place", function()
			local byScore = LeaderboardRules.rankBy(rows, "Score", 10)
			expect(LeaderboardRules.positionOf(byScore, 3)).to.equal(2)
			expect(LeaderboardRules.positionOf(byScore, 99)).to.equal(nil)
		end)
	end)
end
