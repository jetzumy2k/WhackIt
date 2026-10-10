--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ContestConfig = require(ReplicatedStorage.Config.ContestConfig)
local ContestRules = require(ReplicatedStorage.Shared.ContestRules)
local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)
local FurnitureRules = require(ReplicatedStorage.Shared.FurnitureRules)

local DAY = 86400
-- 2026-10-12 00:00 UTC, a Monday.
local MONDAY = 1_791_763_200

local function layoutOf(items: { string }): FurnitureRules.Layout
	local layout: FurnitureRules.Layout = {}
	for index, item in items do
		table.insert(layout, { Id = index, Item = item, X = -16 + index * 4, Z = 0, R = 0 })
	end
	return layout
end

return function()
	describe("ContestConfig", function()
		it("only names furniture that exists, with enough everyday items per theme", function()
			for _, theme in ContestConfig.Themes do
				local basic = 0
				for _, key in theme.Items do
					local item = FurnitureConfig.ByKey[key]
					expect(item).never.to.equal(nil)
					if item and item.Tier == "Basic" then
						basic += 1
					end
				end
				-- The whole theme bonus must be reachable without rare items.
				expect(basic >= ContestConfig.FitTarget).to.equal(true)
			end
		end)

		it("gives prizes that are real Special furniture, places in order", function()
			local expected = 1
			for _, prize in ContestConfig.Prizes do
				expect(prize.FromRank).to.equal(expected)
				expected = prize.ToRank + 1
				local item = FurnitureConfig.ByKey[prize.Item or ""]
				expect(item ~= nil and item.Tier == "Special").to.equal(true)
			end
			expect(expected - 1).to.equal(ContestConfig.ResultsSize)
		end)
	end)

	describe("ContestRules calendar", function()
		it("takes entries Monday-Friday and votes Saturday-Sunday", function()
			expect(ContestRules.phase(MONDAY)).to.equal("Entry")
			expect(ContestRules.phase(MONDAY + 5 * DAY - 1)).to.equal("Entry")
			expect(ContestRules.phase(MONDAY + 5 * DAY)).to.equal("Voting")
			expect(ContestRules.phase(MONDAY + 7 * DAY - 1)).to.equal("Voting")
			expect(ContestRules.phaseEnds(MONDAY + 3600)).to.equal(MONDAY + 5 * DAY)
			expect(ContestRules.phaseEnds(MONDAY + 6 * DAY)).to.equal(MONDAY + 7 * DAY)
			expect(ContestRules.weekStart(ContestRules.weekId(MONDAY + 2 * DAY))).to.equal(MONDAY)
		end)

		it("rotates themes week by week", function()
			local week = ContestRules.weekId(MONDAY)
			expect(ContestRules.themeFor(week).Id).never.to.equal(
				ContestRules.themeFor(week + 1).Id
			)
			expect(ContestRules.themeFor(week).Id).to.equal(
				ContestRules.themeFor(week + #ContestConfig.Themes).Id
			)
		end)
	end)

	describe("ContestRules scoring", function()
		it("counts different theme items only", function()
			local theme = ContestConfig.Themes[1]
			local fit, used = ContestRules.themeFit(
				layoutOf({ theme.Items[1], theme.Items[1], "desk_basic" }),
				theme
			)
			expect(used).to.equal(1)
			expect(fit).to.equal(1 / ContestConfig.FitTarget)
			local full = { table.unpack(theme.Items, 1, ContestConfig.FitTarget + 1) }
			expect((ContestRules.themeFit(layoutOf(full), theme))).to.equal(1)
		end)

		it("keeps a few 5-star votes from beating many honest ones", function()
			local few = ContestRules.score(3, 15, 0)
			local many = ContestRules.score(60, 60 * 4.3, 0)
			expect(many > few).to.equal(true)
			expect(ContestRules.score(0, 0, 0)).to.equal(ContestConfig.PriorStars)
			expect(ContestRules.score(0, 0, 1)).to.equal(
				ContestConfig.PriorStars + ContestConfig.ThemeBonus
			)
		end)

		it("ranks only entries with enough votes", function()
			local entry = (
				ContestRules.enter(nil, 5, "Bo", layoutOf({ "desk_basic" }), "", MONDAY)
			) :: ContestRules.Entry
			expect(ContestRules.rankValue(entry)).to.equal(nil)
			ContestRules.addVotes(
				entry,
				ContestConfig.MinVotesToRank,
				5 * ContestConfig.MinVotesToRank
			)
			expect(ContestRules.rankValue(entry)).never.to.equal(nil)
		end)

		it("accepts 1-5 whole stars only", function()
			expect(ContestRules.isStars(1)).to.equal(true)
			expect(ContestRules.isStars(5)).to.equal(true)
			expect(ContestRules.isStars(0)).to.equal(false)
			expect(ContestRules.isStars(6)).to.equal(false)
			expect(ContestRules.isStars(2.5)).to.equal(false)
			expect(ContestRules.isStars("5")).to.equal(false)
		end)
	end)

	describe("ContestRules entries", function()
		it("keeps votes when updated and refuses a removed entry", function()
			local first = (
				ContestRules.enter(nil, 5, "Bo", layoutOf({ "desk_basic" }), "", MONDAY)
			) :: ContestRules.Entry
			expect(first.Week).to.equal(ContestRules.weekId(MONDAY))
			ContestRules.addVotes(first, 2, 9)
			local again = (
				ContestRules.enter(first, 5, "Bo", layoutOf({ "sofa" }), "", MONDAY + 999)
			) :: ContestRules.Entry
			expect(again.Votes).to.equal(2)
			expect(again.Snapshot.Layout[1].Item).to.equal("sofa")
			again.Snapshot.Moderation = "Removed"
			expect((ContestRules.enter(again, 5, "Bo", layoutOf({ "sofa" }), "", MONDAY + 2000))).to.equal(
				nil
			)
		end)

		it("reads back a saved entry of the right week and owner only", function()
			local entry = (
				ContestRules.enter(nil, 5, "Bo", layoutOf({ "desk_basic" }), "", MONDAY)
			) :: ContestRules.Entry
			local week = entry.Week
			expect(ContestRules.sanitizeEntry(entry, 5, week)).never.to.equal(nil)
			expect(ContestRules.sanitizeEntry(entry, 6, week)).to.equal(nil)
			expect(ContestRules.sanitizeEntry(entry, 5, week + 1)).to.equal(nil)
			local broken = table.clone(entry) :: any
			broken.Votes = 2
			broken.Sum = 500
			broken.Fit = 7
			local fixed = ContestRules.sanitizeEntry(broken, 5, week) :: ContestRules.Entry
			expect(fixed.Sum).to.equal(10)
			expect(fixed.Fit).to.equal(1)
		end)
	end)

	describe("ContestRules player state", function()
		it("needs the entry days, level, furniture and cooldown to enter", function()
			local state = ContestRules.defaultState()
			expect((ContestRules.canEnter(10, 10, state, MONDAY))).to.equal(true)
			expect((ContestRules.canEnter(10, 10, state, MONDAY + 6 * DAY))).to.equal(false)
			expect((ContestRules.canEnter(ContestConfig.MinLevel - 1, 10, state, MONDAY))).to.equal(
				false
			)
			expect((ContestRules.canEnter(10, ContestConfig.MinItems - 1, state, MONDAY))).to.equal(
				false
			)
			ContestRules.noteEntered(state, ContestRules.weekId(MONDAY), MONDAY)
			expect((ContestRules.canEnter(10, 10, state, MONDAY + 60))).to.equal(false)
			expect(ContestRules.hasEntered(state, ContestRules.weekId(MONDAY))).to.equal(true)
		end)

		it("counts votes once per entry per week, dealt entries within the daily limit", function()
			local state = ContestRules.defaultState()
			local saturday = MONDAY + 5 * DAY
			expect((ContestRules.canVote(10, state, MONDAY))).to.equal(false)
			expect((ContestRules.canVote(ContestConfig.VoteMinLevel - 1, state, saturday))).to.equal(
				false
			)
			expect((ContestRules.canVote(10, state, saturday))).to.equal(true)
			ContestRules.useBallot(state, saturday)
			expect(ContestRules.recordVote(state, 7, saturday)).to.equal(true)
			expect(ContestRules.recordVote(state, 7, saturday + 10)).to.equal(false)
			-- Skipped entries use up votes too.
			for _ = 2, ContestConfig.DailyVotes do
				ContestRules.useBallot(state, saturday)
			end
			expect(ContestRules.votesLeft(state, saturday)).to.equal(0)
			expect((ContestRules.canVote(10, state, saturday))).to.equal(false)
			-- Sunday: new votes; the same entry still once per week.
			expect(ContestRules.votesLeft(state, saturday + DAY)).to.equal(ContestConfig.DailyVotes)
			expect(ContestRules.recordVote(state, 7, saturday + DAY)).to.equal(false)
			-- Next week everything starts over.
			expect(ContestRules.recordVote(state, 7, saturday + 7 * DAY)).to.equal(true)
		end)

		it("pays finished weeks once, after the results are out", function()
			local state = ContestRules.defaultState()
			local week = ContestRules.weekId(MONDAY)
			ContestRules.noteEntered(state, week, MONDAY)
			expect(#ContestRules.claimableWeeks(state, MONDAY + 6 * DAY)).to.equal(0)
			expect(#ContestRules.claimableWeeks(state, MONDAY + 7 * DAY)).to.equal(0) -- not frozen yet
			local after = ContestRules.resultsAt(week)
			expect(ContestRules.claimableWeeks(state, after)[1]).to.equal(week)
			ContestRules.noteClaimed(state, week)
			expect(#ContestRules.claimableWeeks(state, after)).to.equal(0)
			-- Too old: not paid any more.
			local old = ContestRules.defaultState()
			ContestRules.noteEntered(old, week, MONDAY)
			expect(
				#ContestRules.claimableWeeks(old, after + (ContestConfig.ClaimWeeks + 1) * 7 * DAY)
			).to.equal(0)
		end)

		it("repairs saved state", function()
			local state = ContestRules.sanitizeState({
				Entered = { 1, 1, -3, 2.5, 4 },
				VotesToday = 999,
				Voted = { -5, 0, 9 },
			})
			expect(#state.Entered).to.equal(2)
			expect(state.VotesToday).to.equal(ContestConfig.DailyVotes)
			expect(#state.Voted).to.equal(2) -- Studio ids may be negative; 0 is nobody
			expect(ContestRules.sanitizeState(nil).VoteWeek).to.equal(-1)
		end)
	end)

	describe("ContestRules results", function()
		it("gives each place its prize and everyone else the participation prize", function()
			expect(ContestRules.prizeFor(1).Item).to.equal("design_trophy")
			expect(ContestRules.prizeFor(3).Item).to.equal("design_plaque")
			expect(ContestRules.prizeFor(10).Item).to.equal("design_ribbon")
			expect(ContestRules.prizeFor(11)).to.equal(ContestConfig.Participation)
			expect(ContestRules.prizeFor(nil)).to.equal(ContestConfig.Participation)
		end)

		it("reads saved results and finds a place", function()
			local good: unknown = { UserId = 4, Name = "A", Score = 4.2, Votes = 9 }
			local broken: unknown = { UserId = "x", Score = 1 }
			local second: unknown = { UserId = 8, Name = "B", Score = 3.9, Votes = 5 }
			local raw = { Top = { good, broken, second } }
			local results = ContestRules.sanitizeResults(raw) :: { ContestRules.Placed }
			expect(#results).to.equal(2)
			expect(ContestRules.rankOf(results, 8)).to.equal(2)
			expect(ContestRules.rankOf(results, 99)).to.equal(nil)
			expect(ContestRules.sanitizeResults("nope")).to.equal(nil)
		end)

		it("deals a random entry that isn't yours, voted or hidden", function()
			local pick = ContestRules.pickBallot(
				{ 1, 2, 3, 4 },
				1,
				{ 2 },
				{ 3 },
				function(n: number): number
					return n
				end
			)
			expect(pick).to.equal(4)
			expect(ContestRules.pickBallot({ 1 }, 1, {}, {}, math.random)).to.equal(nil)
		end)
	end)
end
