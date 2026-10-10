--!strict
--[[
	Pure rules for the weekly office design contests (docs/CONTESTS.md,
	Phase 6b, D18/D19). ContestService decides with these; the client uses
	the week, phase and theme fit to show the contest page.

	An Entry is one player's office entered in one week: a Showcase snapshot
	(layout, theme, owner, moderation; Shared/ShowcaseRules) plus the week,
	the theme fit worked out when it was entered, and its votes.
	A State is what the player's saved data remembers: weeks entered, prizes
	paid, and this week's and today's votes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ContestConfig = require(ReplicatedStorage.Config.ContestConfig)
local FurnitureRules = require(ReplicatedStorage.Shared.FurnitureRules)
local ShowcaseRules = require(ReplicatedStorage.Shared.ShowcaseRules)

export type Phase = "Entry" | "Voting"

export type Entry = {
	Snapshot: ShowcaseRules.Snapshot,
	Week: number,
	ThemeId: string,
	Fit: number, -- 0..1
	Votes: number,
	Sum: number, -- all stars added up
}

export type State = {
	Entered: { number }, -- weeks entered, oldest first
	LastEnteredAt: number,
	Claimed: { number }, -- weeks whose prize was paid
	VoteWeek: number, -- the week Voted belongs to
	Voted: { number }, -- owners voted for that week
	VoteDay: number, -- the UTC day VotesToday belongs to
	VotesToday: number, -- entries dealt to vote on today (a skipped one counts too)
}

export type Placed = { UserId: number, Name: string, Score: number, Votes: number }

local ContestRules = {}

local DAY = 24 * 60 * 60
local WEEK = 7 * DAY
-- 1970-01-05 00:00 UTC was a Monday (as in ShowcaseRules.weekId).
local FIRST_MONDAY = 4 * DAY
local MAX_ENTERED = 6
local MAX_CLAIMED = 24
local MAX_VOTED = 500
local MAX_VOTES = 2 ^ 40

local function isWhole(value: unknown): boolean
	return typeof(value) == "number" and value == value and value == math.floor(value)
end

local function count(value: unknown, max: number): number
	if typeof(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(math.floor(value :: number), 0, max)
end

local function numbers(raw: unknown, max: number, allowNegative: boolean): { number }
	local list: { number } = {}
	if typeof(raw) ~= "table" then
		return list
	end
	for _, value in raw :: { unknown } do
		local ok = isWhole(value) and (allowNegative or (value :: number) >= 0) and value ~= 0
		if ok and not table.find(list, value :: number) then
			table.insert(list, value :: number)
		end
	end
	while #list > max do
		table.remove(list, 1)
	end
	return list
end

-- Calendar -----------------------------------------------------------------------------

function ContestRules.weekId(now: number): number
	return ShowcaseRules.weekId(now)
end

function ContestRules.weekStart(weekId: number): number
	return FIRST_MONDAY + weekId * WEEK
end

function ContestRules.dayIndex(now: number): number
	return math.floor(now / DAY)
end

function ContestRules.phase(now: number): Phase
	local day = math.floor((now - ContestRules.weekStart(ContestRules.weekId(now))) / DAY)
	return if day < ContestConfig.EntryDays then "Entry" else "Voting"
end

-- When the current phase ends (unix seconds).
function ContestRules.phaseEnds(now: number): number
	local start = ContestRules.weekStart(ContestRules.weekId(now))
	return if ContestRules.phase(now) == "Entry"
		then start + ContestConfig.EntryDays * DAY
		else start + WEEK
end

-- When a week's results may be frozen and paid.
function ContestRules.resultsAt(weekId: number): number
	return ContestRules.weekStart(weekId + 1) + ContestConfig.FreezeDelay
end

function ContestRules.themeFor(weekId: number): ContestConfig.Theme
	local themes = ContestConfig.Themes
	return themes[(weekId % #themes) + 1]
end

-- Scoring --------------------------------------------------------------------------------

-- How well a layout fits the theme (0..1) and how many different theme items it uses.
function ContestRules.themeFit(
	layout: FurnitureRules.Layout,
	theme: ContestConfig.Theme
): (number, number)
	local used: { [string]: boolean } = {}
	local distinct = 0
	for _, entry in layout do
		if not used[entry.Item] and table.find(theme.Items, entry.Item) then
			used[entry.Item] = true
			distinct += 1
		end
	end
	return math.clamp(distinct / ContestConfig.FitTarget, 0, 1), distinct
end

-- The fair average of the stars plus the theme bonus.
function ContestRules.score(votes: number, sum: number, fit: number): number
	local prior = ContestConfig.PriorStars * ContestConfig.PriorVotes
	local average = (prior + sum) / (ContestConfig.PriorVotes + votes)
	return average + math.clamp(fit, 0, 1) * ContestConfig.ThemeBonus
end

-- The value saved on the week's score board, or nil while it has too few votes.
function ContestRules.rankValue(entry: Entry): number?
	if entry.Votes < ContestConfig.MinVotesToRank then
		return nil
	end
	return math.floor(ContestRules.score(entry.Votes, entry.Sum, entry.Fit) * 10000 + 0.5)
end

function ContestRules.isStars(value: unknown): boolean
	return isWhole(value)
		and (value :: number) >= ContestConfig.MinStars
		and (value :: number) <= ContestConfig.MaxStars
end

-- Entries --------------------------------------------------------------------------------

--[[
	The entry after the owner enters (or updates) with `layout` now. `old` is
	this week's saved entry, if any: its votes and moderation carry over (a
	removed entry stays out). Nil and a reason if refused.
]]
function ContestRules.enter(
	old: Entry?,
	userId: number,
	name: string,
	layout: FurnitureRules.Layout,
	theme: string,
	now: number
): (Entry?, string?)
	if old and old.Snapshot.Moderation == "Removed" then
		return nil, "A moderator removed your entry this week."
	end
	local snapshot, reason =
		ShowcaseRules.publish(if old then old.Snapshot else nil, userId, name, layout, theme, now)
	if snapshot == nil then
		return nil, reason
	end
	local week = ContestRules.weekId(now)
	local contestTheme = ContestRules.themeFor(week)
	local fit = ContestRules.themeFit(snapshot.Layout, contestTheme)
	return {
		Snapshot = snapshot,
		Week = week,
		ThemeId = contestTheme.Id,
		Fit = fit,
		Votes = if old then old.Votes else 0,
		Sum = if old then old.Sum else 0,
	},
		nil
end

function ContestRules.addVotes(entry: Entry, votes: number, sum: number): ()
	entry.Votes = math.clamp(entry.Votes + votes, 0, MAX_VOTES)
	entry.Sum = math.clamp(entry.Sum + sum, 0, MAX_VOTES * ContestConfig.MaxStars)
end

function ContestRules.sanitizeEntry(raw: unknown, userId: number, weekId: number): Entry?
	if typeof(raw) ~= "table" then
		return nil
	end
	local data = raw :: { [string]: unknown }
	if data.Week ~= weekId then
		return nil
	end
	local snapshot = ShowcaseRules.sanitizeSnapshot(data.Snapshot, userId)
	if snapshot == nil then
		return nil
	end
	local votes = count(data.Votes, MAX_VOTES)
	local fit = if typeof(data.Fit) == "number" and data.Fit == data.Fit
		then math.clamp(data.Fit :: number, 0, 1)
		else 0
	return {
		Snapshot = snapshot,
		Week = weekId,
		ThemeId = if typeof(data.ThemeId) == "string" then data.ThemeId :: string else "",
		Fit = fit,
		Votes = votes,
		Sum = math.clamp(
			count(data.Sum, MAX_VOTES * ContestConfig.MaxStars),
			0,
			votes * ContestConfig.MaxStars
		),
	}
end

-- In the contest: entered and not hidden by moderation.
function ContestRules.isVisible(entry: Entry): boolean
	return ShowcaseRules.isVisible(entry.Snapshot)
end

-- Player state ---------------------------------------------------------------------------

function ContestRules.defaultState(): State
	return {
		Entered = {},
		LastEnteredAt = 0,
		Claimed = {},
		VoteWeek = -1,
		Voted = {},
		VoteDay = -1,
		VotesToday = 0,
	}
end

function ContestRules.sanitizeState(raw: unknown): State
	local state = ContestRules.defaultState()
	if typeof(raw) ~= "table" then
		return state
	end
	local data = raw :: { [string]: unknown }
	state.Entered = numbers(data.Entered, MAX_ENTERED, false)
	state.LastEnteredAt = count(data.LastEnteredAt, 2 ^ 40)
	state.Claimed = numbers(data.Claimed, MAX_CLAIMED, false)
	state.VoteWeek = if isWhole(data.VoteWeek) then data.VoteWeek :: number else -1
	state.Voted = numbers(data.Voted, MAX_VOTED, true)
	state.VoteDay = if isWhole(data.VoteDay) then data.VoteDay :: number else -1
	state.VotesToday = count(data.VotesToday, ContestConfig.DailyVotes)
	return state
end

-- Starts a new week's or day's voting count when it changed (in place).
function ContestRules.rollVotes(state: State, now: number): ()
	local week = ContestRules.weekId(now)
	if state.VoteWeek ~= week then
		state.VoteWeek = week
		state.Voted = {}
	end
	local day = ContestRules.dayIndex(now)
	if state.VoteDay ~= day then
		state.VoteDay = day
		state.VotesToday = 0
	end
end

function ContestRules.votesLeft(state: State, now: number): number
	if state.VoteDay ~= ContestRules.dayIndex(now) then
		return ContestConfig.DailyVotes
	end
	return math.max(0, ContestConfig.DailyVotes - state.VotesToday)
end

function ContestRules.hasEntered(state: State, weekId: number): boolean
	return table.find(state.Entered, weekId) ~= nil
end

function ContestRules.canEnter(
	level: number,
	items: number,
	state: State,
	now: number
): (boolean, string?)
	if ContestRules.phase(now) ~= "Entry" then
		return false, "Entries are closed. Vote for your favourites until Monday!"
	end
	if level < ContestConfig.MinLevel then
		return false, string.format("Reach Level %d to enter the contest.", ContestConfig.MinLevel)
	end
	if items < ContestConfig.MinItems then
		return false,
			string.format(
				"Place at least %d pieces of furniture first (you have %d).",
				ContestConfig.MinItems,
				items
			)
	end
	local wait = state.LastEnteredAt + ContestConfig.EntryCooldown - now
	if state.LastEnteredAt > 0 and wait > 0 then
		return false,
			string.format("You can update your entry again in %d min.", math.ceil(wait / 60))
	end
	return true, nil
end

function ContestRules.canVote(level: number, state: State, now: number): (boolean, string?)
	if ContestRules.phase(now) ~= "Voting" then
		return false, "Voting opens on Saturday (UTC)."
	end
	if level < ContestConfig.VoteMinLevel then
		return false, string.format("Reach Level %d to vote.", ContestConfig.VoteMinLevel)
	end
	if ContestRules.votesLeft(state, now) <= 0 then
		return false, "You've used today's votes. More tomorrow!"
	end
	return true, nil
end

-- Uses one of today's votes for a dealt entry (in place). Dealing, not
-- voting, uses it up, so nobody can skip until a friend's entry comes up.
function ContestRules.useBallot(state: State, now: number): ()
	ContestRules.rollVotes(state, now)
	state.VotesToday += 1
end

-- Records a vote for `ownerId` (in place). False if already voted this week.
function ContestRules.recordVote(state: State, ownerId: number, now: number): boolean
	ContestRules.rollVotes(state, now)
	if table.find(state.Voted, ownerId) then
		return false
	end
	table.insert(state.Voted, ownerId)
	while #state.Voted > MAX_VOTED do
		table.remove(state.Voted, 1)
	end
	return true
end

-- Remembers an entered week (in place).
function ContestRules.noteEntered(state: State, weekId: number, now: number): ()
	if not table.find(state.Entered, weekId) then
		table.insert(state.Entered, weekId)
		while #state.Entered > MAX_ENTERED do
			table.remove(state.Entered, 1)
		end
	end
	state.LastEnteredAt = now
end

-- Finished weeks this player entered whose results are out and not yet paid
-- (at most ClaimWeeks back), oldest first.
function ContestRules.claimableWeeks(state: State, now: number): { number }
	local current = ContestRules.weekId(now)
	local weeks: { number } = {}
	for _, week in state.Entered do
		if
			week < current
			and week >= current - ContestConfig.ClaimWeeks
			and now >= ContestRules.resultsAt(week)
			and not table.find(state.Claimed, week)
		then
			table.insert(weeks, week)
		end
	end
	table.sort(weeks)
	return weeks
end

function ContestRules.noteClaimed(state: State, weekId: number): ()
	if not table.find(state.Claimed, weekId) then
		table.insert(state.Claimed, weekId)
		while #state.Claimed > MAX_CLAIMED do
			table.remove(state.Claimed, 1)
		end
	end
end

-- Results ---------------------------------------------------------------------------------

-- The prize for a place (1 = winner); the participation prize otherwise.
function ContestRules.prizeFor(rank: number?): ContestConfig.Prize
	if rank then
		for _, prize in ContestConfig.Prizes do
			if rank >= prize.FromRank and rank <= prize.ToRank then
				return prize
			end
		end
	end
	return ContestConfig.Participation
end

function ContestRules.rankOf(results: { Placed }, userId: number): number?
	for index, placed in results do
		if placed.UserId == userId then
			return index
		end
	end
	return nil
end

-- A saved results list, checked; nil if it isn't one.
function ContestRules.sanitizeResults(raw: unknown): { Placed }?
	if typeof(raw) ~= "table" then
		return nil
	end
	local top = (raw :: { [string]: unknown }).Top
	if typeof(top) ~= "table" then
		return nil
	end
	local results: { Placed } = {}
	for _, value in top :: { unknown } do
		if typeof(value) == "table" and #results < ContestConfig.ResultsSize then
			local data = value :: { [string]: unknown }
			if isWhole(data.UserId) and data.UserId ~= 0 and typeof(data.Score) == "number" then
				table.insert(results, {
					UserId = data.UserId :: number,
					Name = if typeof(data.Name) == "string"
						then string.sub(data.Name :: string, 1, 40)
						else "Player",
					Score = data.Score :: number,
					Votes = count(data.Votes, MAX_VOTES),
				})
			end
		end
	end
	return results
end

--[[
	Picks a random entry to vote on from `ids`: not `self`, not already voted
	for, not hidden. `random(n)` returns 1..n. Nil if none is left.
]]
function ContestRules.pickBallot(
	ids: { number },
	self: number,
	voted: { number },
	hidden: { number },
	random: (n: number) -> number
): number?
	local choices: { number } = {}
	for _, id in ids do
		if id ~= self and not table.find(voted, id) and not table.find(hidden, id) then
			table.insert(choices, id)
		end
	end
	if #choices == 0 then
		return nil
	end
	return choices[random(#choices)]
end

return ContestRules
