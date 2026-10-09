--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)
local PickleballConfig = require(ReplicatedStorage.Config.PickleballConfig)
local PickleballRules = require(ReplicatedStorage.Shared.PickleballRules)

local COURT = PickleballConfig.Court
local SHOT = PickleballConfig.Shot

-- Plays rallies won by `team` until the score changes hands or `count` run out.
local function win(score: PickleballRules.Score, team: number, count: number): ()
	for _ = 1, count do
		PickleballRules.rallyWon(score, team)
	end
end

return function()
	describe("PickleballRules singles scoring", function()
		it("only the serving side scores; a lost rally is a side-out", function()
			local score = PickleballRules.newScore("Singles", 1)
			expect(PickleballRules.rallyWon(score, 1)).to.equal("Point")
			expect(score.Points[1]).to.equal(1)
			expect(PickleballRules.rallyWon(score, 2)).to.equal("SideOut")
			expect(score.Points[2]).to.equal(0)
			expect(score.Serving).to.equal(2)
		end)

		it("serves from the right on an even score and the left on an odd one", function()
			local score = PickleballRules.newScore("Singles", 1)
			local _, _, side = PickleballRules.server(score)
			expect(side).to.equal("Right")
			win(score, 1, 1)
			_, _, side = PickleballRules.server(score)
			expect(side).to.equal("Left")
			local _, _, receiverSide = PickleballRules.receiver(score)
			expect(receiverSide).to.equal("Left") -- diagonal: same named court
		end)

		it("calls the score server first", function()
			local score = PickleballRules.newScore("Singles", 1)
			win(score, 1, 3)
			PickleballRules.rallyWon(score, 2)
			expect(PickleballRules.callout(score)).to.equal("0-3")
		end)

		it("needs 11 points and a 2-point lead", function()
			local score = PickleballRules.newScore("Singles", 1)
			score.Points = { 10, 10 }
			PickleballRules.rallyWon(score, 1)
			expect(score.Winner).to.equal(nil) -- 11-10
			PickleballRules.rallyWon(score, 1)
			expect(score.Winner).to.equal(1) -- 12-10
			score = PickleballRules.newScore("Singles", 2)
			win(score, 2, 11)
			expect(score.Winner).to.equal(2)
		end)

		it("names the leader for the time limit, or nil on a tie", function()
			local score = PickleballRules.newScore("Singles", 1)
			expect(PickleballRules.leader(score)).to.equal(nil)
			win(score, 1, 2)
			expect(PickleballRules.leader(score)).to.equal(1)
		end)
	end)

	describe("PickleballRules doubles scoring", function()
		it("starts at 0-0-2: the first team loses the serve after one fault", function()
			local score = PickleballRules.newScore("Doubles", 1)
			expect(PickleballRules.callout(score)).to.equal("0-0-2")
			expect(PickleballRules.rallyWon(score, 2)).to.equal("SideOut")
			expect(score.Serving).to.equal(2)
			expect(PickleballRules.callout(score)).to.equal("0-0-1")
		end)

		it("gives both partners a serve after the start", function()
			local score = PickleballRules.newScore("Doubles", 1)
			PickleballRules.rallyWon(score, 2) -- side-out to team 2, server 1
			local _, firstSlot = PickleballRules.server(score)
			expect(PickleballRules.rallyWon(score, 1)).to.equal("SecondServer")
			local _, secondSlot = PickleballRules.server(score)
			expect(secondSlot).to.equal(3 - firstSlot)
			expect(PickleballRules.callout(score)).to.equal("0-0-2")
			expect(PickleballRules.rallyWon(score, 1)).to.equal("SideOut")
			expect(score.Serving).to.equal(1)
		end)

		it("the serving pair switch courts after each point; the server keeps serving", function()
			local score = PickleballRules.newScore("Doubles", 1)
			local team, slot, side = PickleballRules.server(score)
			expect(side).to.equal("Right")
			PickleballRules.rallyWon(score, 1)
			local team2, slot2, side2 = PickleballRules.server(score)
			expect(team2).to.equal(team)
			expect(slot2).to.equal(slot)
			expect(side2).to.equal("Left")
			-- The partner moved to the right court.
			expect(PickleballRules.positionOf(score, 1, 3 - slot)).to.equal("Right")
			-- The receiving pair never switch.
			expect(PickleballRules.positionOf(score, 2, 1)).to.equal("Right")
		end)

		it("the receiver is the player diagonally opposite the server", function()
			local score = PickleballRules.newScore("Doubles", 1)
			PickleballRules.rallyWon(score, 1) -- server now serves from the left
			local team, slot, side = PickleballRules.receiver(score)
			expect(team).to.equal(2)
			expect(side).to.equal("Left")
			expect(PickleballRules.positionOf(score, team, slot)).to.equal("Left")
		end)
	end)

	describe("PickleballRules line calls", function()
		local half = COURT.Length / 2

		it("a ball on the line is in; past it is out", function()
			expect(
				PickleballRules.judgeBounce(COURT, Vector3.new(COURT.Width / 2, 0, -half), 1, nil)
			).to.equal(nil)
			expect(
				PickleballRules.judgeBounce(
					COURT,
					Vector3.new(COURT.Width / 2 + 0.1, 0, -10),
					1,
					nil
				)
			).to.equal("Out")
			expect(PickleballRules.judgeBounce(COURT, Vector3.new(0, 0, -half - 0.1), 1, nil)).to.equal(
				"Out"
			)
		end)

		it("a ball landing on the hitter's own side never crossed the net", function()
			expect(PickleballRules.judgeBounce(COURT, Vector3.new(0, 0, 5), 1, nil)).to.equal("Net")
			expect(PickleballRules.judgeBounce(COURT, Vector3.new(0, 0, -5), 2, nil)).to.equal(
				"Net"
			)
		end)

		it("a rally shot may land in the kitchen", function()
			expect(PickleballRules.judgeBounce(COURT, Vector3.new(0, 0, -2), 1, nil)).to.equal(nil)
		end)

		it("a serve must clear the kitchen and its line and land diagonally", function()
			-- Team 1 serving from the right (+X): lands in team 2's right court (-X).
			local good = Vector3.new(-5, 0, -15)
			expect(PickleballRules.judgeBounce(COURT, good, 1, "Right")).to.equal(nil)
			expect(
				PickleballRules.judgeBounce(COURT, Vector3.new(-5, 0, -COURT.Kitchen), 1, "Right")
			).to.equal("ServeKitchen")
			expect(PickleballRules.judgeBounce(COURT, Vector3.new(5, 0, -15), 1, "Right")).to.equal(
				"WrongCourt"
			)
			-- The centre line is in.
			expect(PickleballRules.judgeBounce(COURT, Vector3.new(0, 0, -15), 1, "Right")).to.equal(
				nil
			)
			-- Team 2 serving from its left (+X for team 2): lands at team 1's left (-X).
			expect(PickleballRules.judgeBounce(COURT, Vector3.new(-5, 0, 15), 2, "Left")).to.equal(
				nil
			)
			expect(PickleballRules.judgeBounce(COURT, Vector3.new(5, 0, 15), 2, "Left")).to.equal(
				"WrongCourt"
			)
		end)

		it("service courts sit between the kitchen line and the baseline", function()
			local box = PickleballRules.serviceCourt(COURT, 2, "Right")
			expect(box.MaxX).to.equal(0) -- team 2's right is -X
			expect(box.MaxZ).to.equal(-COURT.Kitchen)
			expect(box.MinZ).to.equal(-half)
			local own = PickleballRules.serviceCourt(COURT, 1, "Left")
			expect(own.MaxX).to.equal(0)
			expect(own.MinZ).to.equal(COURT.Kitchen)
		end)

		it("knows who stands in their kitchen", function()
			expect(PickleballRules.inKitchen(COURT, 1, Vector3.new(0, 3, COURT.Kitchen))).to.equal(
				true
			)
			expect(PickleballRules.inKitchen(COURT, 1, Vector3.new(0, 3, COURT.Kitchen + 0.5))).to.equal(
				false
			)
			expect(PickleballRules.inKitchen(COURT, 2, Vector3.new(0, 3, -3))).to.equal(true)
			expect(PickleballRules.inKitchen(COURT, 2, Vector3.new(0, 3, 3))).to.equal(false)
		end)
	end)

	describe("PickleballRules hits", function()
		it("the return and the third shot must bounce first", function()
			expect(PickleballRules.hitFault(1, false, false)).to.equal("TwoBounce")
			expect(PickleballRules.hitFault(2, false, false)).to.equal("TwoBounce")
			expect(PickleballRules.hitFault(1, true, true)).to.equal(nil)
			expect(PickleballRules.hitFault(3, false, false)).to.equal(nil) -- volleys allowed now
		end)

		it("no volleys from the kitchen, but a bounced ball may be hit there", function()
			expect(PickleballRules.hitFault(4, false, true)).to.equal("KitchenVolley")
			expect(PickleballRules.hitFault(4, true, true)).to.equal(nil)
		end)

		it("aims into the opponent's half, clamping the aim", function()
			local target = PickleballRules.aimTarget(COURT, 1, 5, -3, nil)
			expect(target.Z < 0).to.equal(true)
			expect(math.abs(target.X) <= COURT.Width / 2).to.equal(true)
			local deep = PickleballRules.aimTarget(COURT, 2, 0, 1, nil)
			expect(deep.Z > 0 and deep.Z <= COURT.Length / 2).to.equal(true)
		end)

		it("aims a serve into the diagonal service court, past the kitchen", function()
			for _, u in { -1, 0, 1 } do
				for _, v in { 0, 1 } do
					local target = PickleballRules.aimTarget(COURT, 1, u, v, "Right")
					expect(PickleballRules.judgeBounce(COURT, target, 1, "Right")).to.equal(nil)
					local other = PickleballRules.aimTarget(COURT, 2, u, v, "Left")
					expect(PickleballRules.judgeBounce(COURT, other, 2, "Left")).to.equal(nil)
				end
			end
		end)

		it("harder and stretched shots spread more", function()
			local clean = PickleballRules.scatterRadius(SHOT, 1, 0)
			expect(clean).to.equal(0)
			expect(PickleballRules.scatterRadius(SHOT, 1, 1)).to.equal(SHOT.PowerScatter)
			expect(PickleballRules.scatterRadius(SHOT, SHOT.Reach, 0)).to.equal(SHOT.ReachScatter)
		end)

		it("scatters within the radius", function()
			local random = Random.new(7)
			local target = Vector3.new(2, 0, -10)
			for _ = 1, 50 do
				local point = PickleballRules.scatter(target, 3, random)
				expect((point - target).Magnitude <= 3 + 1e-6).to.equal(true)
				expect(point.Y).to.equal(0)
			end
			expect(PickleballRules.scatter(target, 0, random)).to.equal(target)
		end)

		it("faster shots take less time, but never less than the minimum", function()
			local slow = PickleballRules.shotDuration(SHOT, 30, 0)
			local fast = PickleballRules.shotDuration(SHOT, 30, 1)
			expect(fast < slow).to.equal(true)
			expect(PickleballRules.shotDuration(SHOT, 1, 1)).to.equal(SHOT.MinDuration)
		end)
	end)

	describe("PickleballRules rating", function()
		it("an even match moves both by half of K", function()
			local half = PickleballConfig.Rating.K / 2
			expect(PickleballRules.ratingChange(1000, 1000, true)).to.equal(half)
			expect(PickleballRules.ratingChange(1000, 1000, false)).to.equal(-half)
		end)

		it("beating a stronger player pays more than beating a weaker one", function()
			expect(
				PickleballRules.ratingChange(1000, 1400, true)
					> PickleballRules.ratingChange(1400, 1000, true)
			).to.equal(true)
		end)

		it("clamps ratings and averages teams", function()
			expect(PickleballRules.clampRating(-50)).to.equal(PickleballConfig.Rating.Min)
			expect(PickleballRules.clampRating(1e9)).to.equal(PickleballConfig.Rating.Max)
			expect(PickleballRules.average({ 900, 1100 })).to.equal(1000)
			expect(PickleballRules.average({})).to.equal(PickleballConfig.Rating.Start)
		end)
	end)

	describe("PickleballRules days, seasons and caps", function()
		it("uses the UTC date", function()
			-- 2026-10-10 23:30 UTC.
			expect(PickleballRules.dayKey(1791675000)).to.equal("2026-10-10")
			expect(PickleballRules.dayKey(1791675000 + 3600)).to.equal("2026-10-11")
		end)

		it("seasons are 4 weeks long and start on a Monday 00:00 UTC", function()
			local season = PickleballConfig.Season
			expect(season.Seconds).to.equal(28 * 86400)
			local id = PickleballRules.seasonId(1791675000)
			local starts = PickleballRules.seasonEnds(id - 1)
			expect(starts <= 1791675000 and 1791675000 < PickleballRules.seasonEnds(id)).to.equal(
				true
			)
			local date = os.date("!*t", starts)
			expect(date.wday).to.equal(2) -- Monday
			expect(date.hour).to.equal(0)
		end)

		it("the same opponents give the same key in any order", function()
			expect(PickleballRules.opponentsKey({ 30, 4 })).to.equal("4-30")
			expect(PickleballRules.opponentsKey({ 4, 30 })).to.equal("4-30")
		end)

		it("caps rewarded matches per day and per set of opponents", function()
			local rewards = PickleballConfig.Rewards
			local record = PickleballRules.defaultRecord(0)
			PickleballRules.forDay(record, "2026-10-10")
			for _ = 1, rewards.SameOpponentsPerDay do
				expect(PickleballRules.canEarn(record, "7")).to.equal(true)
				PickleballRules.noteRewarded(record, "7")
			end
			expect(PickleballRules.canEarn(record, "7")).to.equal(false)
			expect(PickleballRules.canEarn(record, "8")).to.equal(true)
			record.DayMatches = rewards.DailyRewarded
			expect(PickleballRules.canEarn(record, "9")).to.equal(false)
			-- A new UTC day starts the counters again.
			PickleballRules.forDay(record, "2026-10-11")
			expect(PickleballRules.canEarn(record, "7")).to.equal(true)
		end)

		it("a new season resets the rating and the season record, not the totals", function()
			local record = PickleballRules.defaultRecord(3)
			record.Rating, record.Wins, record.TotalWins = 1300, 5, 9
			PickleballRules.forSeason(record, 3)
			expect(record.Rating).to.equal(1300)
			PickleballRules.forSeason(record, 4)
			expect(record.Rating).to.equal(PickleballConfig.Rating.Start)
			expect(record.Wins).to.equal(0)
			expect(record.TotalWins).to.equal(9)
		end)

		it("sanitizes a saved record", function()
			local record = PickleballRules.sanitizeRecord({
				Rating = 0 / 0,
				Wins = -4,
				TotalWins = 12.7,
				DayKey = "yesterday",
				DayMatches = 99,
				DayOpponents = { ["1-2"] = 2 },
			})
			expect(record.Rating).to.equal(PickleballConfig.Rating.Start)
			expect(record.Wins).to.equal(0)
			expect(record.TotalWins).to.equal(12)
			-- A broken day key drops the day's counters.
			expect(record.DayKey).to.equal("")
			expect(record.DayMatches).to.equal(0)
			expect((next(record.DayOpponents))).to.equal(nil)
			local kept = PickleballRules.sanitizeRecord({
				DayKey = "2026-10-10",
				DayMatches = 3,
				DayOpponents = { ["1-2"] = 2, bad = 1, ["3"] = "x" },
			})
			expect(kept.DayMatches).to.equal(3)
			expect(kept.DayOpponents["1-2"]).to.equal(2)
			expect(kept.DayOpponents.bad).to.equal(nil)
			expect(kept.DayOpponents["3"]).to.equal(nil)
			expect(PickleballRules.sanitizeRecord("nope").Rating).to.equal(
				PickleballConfig.Rating.Start
			)
		end)
	end)

	describe("PickleballRules supplies and seats", function()
		it("every supply is a Special furniture item and the weights add up to 100", function()
			for _, pool in { PickleballConfig.Supplies.Winner, PickleballConfig.Supplies.Loser } do
				local total = 0
				for _, entry in pool do
					local item = FurnitureConfig.ByKey[entry.Item]
					expect(item ~= nil and item.Tier == "Special").to.equal(true)
					total += entry.Weight
				end
				expect(total).to.equal(100)
			end
		end)

		it("rolls only items from the pool", function()
			local random = Random.new(11)
			local pool = PickleballConfig.Supplies.Loser
			local allowed: { [string]: boolean } = {}
			for _, entry in pool do
				allowed[entry.Item] = true
			end
			for _ = 1, 200 do
				expect(allowed[PickleballRules.rollSupply(pool, random)]).to.equal(true)
			end
		end)

		it("seats a singles opponent on team 2, then is full", function()
			expect(PickleballRules.pickTeam("Singles", { 1, 0 }, nil)).to.equal(2)
			expect(PickleballRules.pickTeam("Singles", { 1, 0 }, 1)).to.equal(2)
			expect(PickleballRules.isFull("Singles", { 1, 1 })).to.equal(true)
			expect(PickleballRules.pickTeam("Singles", { 1, 1 }, nil)).to.equal(nil)
		end)

		it("lets doubles players pick a team with room", function()
			expect(PickleballRules.pickTeam("Doubles", { 1, 0 }, 1)).to.equal(1)
			expect(PickleballRules.pickTeam("Doubles", { 2, 0 }, 1)).to.equal(2)
			expect(PickleballRules.pickTeam("Doubles", { 2, 1 }, nil)).to.equal(2)
			expect(PickleballRules.isFull("Doubles", { 2, 1 })).to.equal(false)
			expect(PickleballRules.isFull("Doubles", { 2, 2 })).to.equal(true)
		end)
	end)
end
