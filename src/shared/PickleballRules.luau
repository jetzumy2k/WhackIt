--!strict
--[[
	Pickleball rules (docs/PICKLEBALL.md; standard USA Pickleball rules as
	decided in docs/MAJOR_GAME_UPDATE.md §21.1). Pure, so every rule is
	unit-tested; RecreationService applies them and the client only shows
	the results.

	  * Scoring: one game to 11, win by 2, only the serving side scores.
	    Singles: the server serves from the right on an even score, from the
	    left on an odd one. Doubles: both partners serve before a side-out
	    (the game's first serving team gets only one server, "0-0-2"); the
	    serving pair switch sides each time they score.
	  * Line calls: a ball on a line is in, except a serve on the kitchen line.
	  * Hits: the two-bounce rule and no volleys from the kitchen.
	  * Rating (Elo), the UTC day and season, daily reward caps, the office
	    supply roll, and seats in a challenge.

	Court-local coordinates as in Config/PickleballConfig: team 1 plays the
	+Z half, team 2 the -Z half. Facing the net, team 1's right is +X and
	team 2's right is -X.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PickleballConfig = require(ReplicatedStorage.Config.PickleballConfig)

-- "Right" or "Left" (a plain string: the old solver widens the literals).
export type Side = string

export type Score = {
	Mode: string,
	Points: { number }, -- [team] = points
	Serving: number, -- the serving team (1 or 2)
	ServerNumber: number, -- 1 or 2 (doubles; always 1 in singles)
	ServerSlot: number, -- which player of the serving team serves (1 or 2)
	RightSlot: { number }, -- [team] = the player standing in that team's right court
	Winner: number?,
}

export type Outcome = "Point" | "SecondServer" | "SideOut"

export type CourtShape = {
	Width: number,
	Length: number,
	Kitchen: number,
}

export type Bounds = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }

export type Record = {
	Rating: number,
	SeasonId: number,
	Wins: number, -- this season
	Losses: number, -- this season
	TotalWins: number,
	TotalLosses: number,
	DayKey: string, -- the UTC day the day counters belong to ("" = none yet)
	DayMatches: number, -- rewarded matches that day
	DayOpponents: { [string]: number }, -- opponentsKey -> rewarded matches that day
}

local PickleballRules = {}

local MAX_COUNTER = 2 ^ 40
local MAX_DAY_OPPONENTS = 32
local MAX_OPPONENTS_KEY = 128

function PickleballRules.other(team: number): number
	return if team == 1 then 2 else 1
end

function PickleballRules.isMode(value: unknown): boolean
	return value == "Singles" or value == "Doubles"
end

function PickleballRules.teamSize(mode: string): number
	return if mode == "Doubles" then 2 else 1
end

-- Scoring ---------------------------------------------------------------------------

function PickleballRules.newScore(mode: string, firstServing: number): Score
	local doubles = mode == "Doubles"
	return {
		Mode = mode,
		Points = { 0, 0 },
		Serving = firstServing,
		-- Doubles starts at "0-0-2": the first team gets only one server.
		ServerNumber = if doubles then 2 else 1,
		ServerSlot = 1,
		RightSlot = { 1, 1 },
		Winner = nil,
	}
end

local function sideOfSlot(score: Score, team: number, slot: number): Side
	return if score.RightSlot[team] == slot then "Right" else "Left"
end

-- Who serves, and from which court.
function PickleballRules.server(score: Score): (number, number, Side)
	local team = score.Serving
	if score.Mode ~= "Doubles" then
		local side: Side = if score.Points[team] % 2 == 0 then "Right" else "Left"
		return team, 1, side
	end
	return team, score.ServerSlot, sideOfSlot(score, team, score.ServerSlot)
end

-- Who receives (the player diagonally opposite the server) and from where.
function PickleballRules.receiver(score: Score): (number, number, Side)
	local _, _, side = PickleballRules.server(score)
	local team = PickleballRules.other(score.Serving)
	if score.Mode ~= "Doubles" then
		return team, 1, side
	end
	local slot = if side == "Right" then score.RightSlot[team] else 3 - score.RightSlot[team]
	return team, slot, side
end

-- The court a player stands in before a serve: the server and receiver
-- from the serve; their partners (doubles) take the other court.
function PickleballRules.positionOf(score: Score, team: number, slot: number): Side
	if score.Mode ~= "Doubles" then
		local _, _, side = PickleballRules.server(score)
		return side
	end
	return sideOfSlot(score, team, slot)
end

-- Applies a finished rally won by `team`. Returns what happened.
function PickleballRules.rallyWon(score: Score, team: number): Outcome
	if score.Winner then
		return "Point"
	end
	local doubles = score.Mode == "Doubles"
	if team == score.Serving then
		score.Points[team] += 1
		if doubles then
			-- The server switches sides with their partner after each point.
			score.RightSlot[team] = 3 - score.RightSlot[team]
		end
		local own, theirs = score.Points[team], score.Points[PickleballRules.other(team)]
		local game = PickleballConfig.Game
		if own >= game.PointsToWin and own - theirs >= game.WinBy then
			score.Winner = team
		end
		return "Point"
	end
	if doubles and score.ServerNumber == 1 then
		score.ServerNumber = 2
		score.ServerSlot = 3 - score.ServerSlot
		return "SecondServer"
	end
	local receiving = PickleballRules.other(score.Serving)
	score.Serving = receiving
	score.ServerNumber = 1
	score.ServerSlot = score.RightSlot[receiving]
	return "SideOut"
end

-- The score as players call it: "server-receiver" in singles, plus the
-- server number in doubles ("3-2-1").
function PickleballRules.callout(score: Score): string
	local serving = score.Serving
	local own, theirs = score.Points[serving], score.Points[PickleballRules.other(serving)]
	if score.Mode == "Doubles" then
		return string.format("%d-%d-%d", own, theirs, score.ServerNumber)
	end
	return string.format("%d-%d", own, theirs)
end

-- The team ahead, or nil on a tie (the time limit).
function PickleballRules.leader(score: Score): number?
	local a, b = score.Points[1], score.Points[2]
	if a == b then
		return nil
	end
	return if a > b then 1 else 2
end

-- Court geometry -----------------------------------------------------------------

-- The Z sign of a team's half.
function PickleballRules.halfSign(team: number): number
	return if team == 1 then 1 else -1
end

-- The X sign of a team's right court.
function PickleballRules.rightSign(team: number): number
	return if team == 1 then 1 else -1
end

local function sideSign(team: number, side: Side): number
	return PickleballRules.rightSign(team) * (if side == "Right" then 1 else -1)
end

-- A team's service court on one side (the lines count as in; the kitchen
-- line is checked separately).
function PickleballRules.serviceCourt(court: CourtShape, team: number, side: Side): Bounds
	local x = sideSign(team, side)
	local z = PickleballRules.halfSign(team)
	local halfWidth, halfLength = court.Width / 2, court.Length / 2
	return {
		MinX = if x > 0 then 0 else -halfWidth,
		MaxX = if x > 0 then halfWidth else 0,
		MinZ = if z > 0 then court.Kitchen else -halfLength,
		MaxZ = if z > 0 then halfLength else -court.Kitchen,
	}
end

-- Whether a point stands in a team's kitchen (its line included).
function PickleballRules.inKitchen(court: CourtShape, team: number, point: Vector3): boolean
	local z = point.Z * PickleballRules.halfSign(team)
	return z >= 0 and z <= court.Kitchen and math.abs(point.X) <= court.Width / 2
end

-- Whether a point is on a team's half of the court area (lines and
-- run-off included: everything past the net on their side).
function PickleballRules.onHalf(team: number, point: Vector3): boolean
	return point.Z * PickleballRules.halfSign(team) > 0
end

-- Judges the first bounce of a shot hit by `hitter`. `serveSide` is the
-- court the serve came from (nil for any other shot). Returns the fault,
-- or nil if the ball is in.
function PickleballRules.judgeBounce(
	court: CourtShape,
	point: Vector3,
	hitter: number,
	serveSide: Side?
): string?
	local receiver = PickleballRules.other(hitter)
	if not PickleballRules.onHalf(receiver, point) then
		return "Net" -- it never crossed the net
	end
	if math.abs(point.X) > court.Width / 2 or math.abs(point.Z) > court.Length / 2 then
		return "Out"
	end
	if serveSide then
		if math.abs(point.Z) <= court.Kitchen then
			return "ServeKitchen"
		end
		-- Diagonal: the receiver's court on the same side as the server's.
		if point.X * sideSign(receiver, serveSide) < 0 then
			return "WrongCourt"
		end
	end
	return nil
end

-- A fault the hitter commits by hitting now. `shotIndex` counts the shots
-- of the rally (the serve is 0, its return 1, the third shot 2);
-- `bounced`: the ball has bounced on the hitter's side.
function PickleballRules.hitFault(shotIndex: number, bounced: boolean, inKitchen: boolean): string?
	if not bounced and shotIndex <= 2 then
		return "TwoBounce"
	end
	if not bounced and inKitchen then
		return "KitchenVolley"
	end
	return nil
end

-- Aiming -------------------------------------------------------------------------

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Where a shot by `hitter` is aimed, from the client's aim (u across in
-- [-1, 1], v from the net to the baseline in [0, 1]; both clamped). A serve
-- aims into the diagonal service court.
function PickleballRules.aimTarget(
	court: CourtShape,
	hitter: number,
	u: number,
	v: number,
	serveSide: Side?
): Vector3
	local across = math.clamp(u, -1, 1)
	local depth = math.clamp(v, 0, 1)
	local receiver = PickleballRules.other(hitter)
	local z = PickleballRules.halfSign(receiver)
	local halfWidth, halfLength = court.Width / 2, court.Length / 2
	if serveSide then
		local x = sideSign(receiver, serveSide) * lerp(0.5, halfWidth - 0.5, (across + 1) / 2)
		return Vector3.new(x, 0, z * lerp(court.Kitchen + 1, halfLength - 1, depth))
	end
	return Vector3.new(across * (halfWidth - 0.5), 0, z * lerp(1, halfLength - 0.5, depth))
end

export type ShotTuning = {
	MinSpeed: number,
	MaxSpeed: number,
	MinDuration: number,
	PowerScatter: number,
	ReachScatter: number,
	SweetSpot: number,
	Reach: number,
}

-- Seconds a shot takes to cover `distance` along the ground.
function PickleballRules.shotDuration(shot: ShotTuning, distance: number, power: number): number
	local speed = lerp(shot.MinSpeed, shot.MaxSpeed, math.clamp(power, 0, 1))
	return math.max(shot.MinDuration, distance / speed)
end

-- How far from its aim a shot may land: harder shots and stretched hits
-- (the ball far from the player) spread more.
function PickleballRules.scatterRadius(
	shot: ShotTuning,
	reachDistance: number,
	power: number
): number
	local stretch =
		math.clamp((reachDistance - shot.SweetSpot) / (shot.Reach - shot.SweetSpot), 0, 1)
	return shot.PowerScatter * math.clamp(power, 0, 1) + shot.ReachScatter * stretch
end

-- A random point within `radius` of `target` on the court surface.
function PickleballRules.scatter(target: Vector3, radius: number, random: Random): Vector3
	if radius <= 0 then
		return target
	end
	local angle = random:NextNumber(0, 2 * math.pi)
	local distance = radius * math.sqrt(random:NextNumber())
	return Vector3.new(
		target.X + math.cos(angle) * distance,
		0,
		target.Z + math.sin(angle) * distance
	)
end

-- Rating -----------------------------------------------------------------------------

function PickleballRules.expected(rating: number, opponent: number): number
	return 1 / (1 + 10 ^ ((opponent - rating) / 400))
end

-- The rating change for one player: their team's average against the
-- other team's average (decision D5). Whole points.
function PickleballRules.ratingChange(
	teamRating: number,
	opponentRating: number,
	won: boolean
): number
	local score = if won then 1 else 0
	local delta = PickleballConfig.Rating.K
		* (score - PickleballRules.expected(teamRating, opponentRating))
	return math.floor(delta + 0.5)
end

function PickleballRules.clampRating(rating: number): number
	local config = PickleballConfig.Rating
	return math.clamp(math.floor(rating + 0.5), config.Min, config.Max)
end

function PickleballRules.average(values: { number }): number
	if #values == 0 then
		return PickleballConfig.Rating.Start
	end
	local total = 0
	for _, value in values do
		total += value
	end
	return total / #values
end

-- Days and seasons --------------------------------------------------------------

-- The UTC date of a unix time, "YYYY-MM-DD".
function PickleballRules.dayKey(unixTime: number): string
	local date = os.date("!*t", math.floor(unixTime))
	return string.format("%04d-%02d-%02d", date.year, date.month, date.day)
end

function PickleballRules.seasonId(unixTime: number): number
	local season = PickleballConfig.Season
	return math.max(0, math.floor((unixTime - season.Epoch) / season.Seconds))
end

-- Unix time a season ends (the next one starts).
function PickleballRules.seasonEnds(seasonId: number): number
	local season = PickleballConfig.Season
	return season.Epoch + (seasonId + 1) * season.Seconds
end

-- The same opponents in any order give the same key.
function PickleballRules.opponentsKey(userIds: { number }): string
	local sorted = table.clone(userIds)
	table.sort(sorted)
	local parts = {}
	for _, userId in sorted do
		table.insert(parts, string.format("%d", userId))
	end
	return table.concat(parts, "-")
end

-- Saved record ---------------------------------------------------------------------

function PickleballRules.defaultRecord(seasonId: number): Record
	return {
		Rating = PickleballConfig.Rating.Start,
		SeasonId = seasonId,
		Wins = 0,
		Losses = 0,
		TotalWins = 0,
		TotalLosses = 0,
		DayKey = "",
		DayMatches = 0,
		DayOpponents = {},
	}
end

local function counter(value: unknown): number
	if typeof(value) ~= "number" or value ~= value or value == math.huge then
		return 0
	end
	return math.clamp(math.floor(value), 0, MAX_COUNTER)
end

-- A clean copy of a saved record (missing or broken fields default).
function PickleballRules.sanitizeRecord(raw: unknown): Record
	local record = PickleballRules.defaultRecord(0)
	if typeof(raw) ~= "table" then
		return record
	end
	local data = raw :: { [string]: unknown }
	local rating = data.Rating
	if typeof(rating) == "number" and rating == rating and math.abs(rating) ~= math.huge then
		record.Rating = PickleballRules.clampRating(rating)
	end
	record.SeasonId = counter(data.SeasonId)
	record.Wins = counter(data.Wins)
	record.Losses = counter(data.Losses)
	record.TotalWins = counter(data.TotalWins)
	record.TotalLosses = counter(data.TotalLosses)
	local dayKey = data.DayKey
	if typeof(dayKey) == "string" and string.match(dayKey, "^%d%d%d%d%-%d%d%-%d%d$") then
		record.DayKey = dayKey
		record.DayMatches = counter(data.DayMatches)
		local opponents = data.DayOpponents
		if typeof(opponents) == "table" then
			local kept = 0
			for key, value in opponents :: { [unknown]: unknown } do
				if
					kept < MAX_DAY_OPPONENTS
					and typeof(key) == "string"
					and #key <= MAX_OPPONENTS_KEY
					and string.match(key, "^[%d%-]+$")
					and counter(value) > 0
				then
					record.DayOpponents[key] = counter(value)
					kept += 1
				end
			end
		end
	end
	return record
end

-- Starts a new season's rating and record when the season changed.
function PickleballRules.forSeason(record: Record, seasonId: number): ()
	if record.SeasonId ~= seasonId then
		record.SeasonId = seasonId
		record.Rating = PickleballConfig.Rating.Start
		record.Wins = 0
		record.Losses = 0
	end
end

-- Starts the day's counters when the UTC day changed.
function PickleballRules.forDay(record: Record, dayKey: string): ()
	if record.DayKey ~= dayKey then
		record.DayKey = dayKey
		record.DayMatches = 0
		record.DayOpponents = {}
	end
end

-- Whether a match against `opponents` (opponentsKey) is still rewarded
-- today. Call forDay first.
function PickleballRules.canEarn(record: Record, opponents: string): boolean
	local rewards = PickleballConfig.Rewards
	return record.DayMatches < rewards.DailyRewarded
		and (record.DayOpponents[opponents] or 0) < rewards.SameOpponentsPerDay
end

-- Counts a rewarded match. Call forDay first.
function PickleballRules.noteRewarded(record: Record, opponents: string): ()
	record.DayMatches += 1
	record.DayOpponents[opponents] = (record.DayOpponents[opponents] or 0) + 1
end

-- Office supplies and seats ------------------------------------------------------

-- One item from a weighted pool (Config/PickleballConfig.Supplies).
function PickleballRules.rollSupply(pool: { PickleballConfig.SupplyWeight }, random: Random): string
	local total = 0
	for _, entry in pool do
		total += entry.Weight
	end
	local roll = random:NextNumber(0, total)
	for _, entry in pool do
		roll -= entry.Weight
		if roll < 0 then
			return entry.Item
		end
	end
	return pool[#pool].Item
end

-- The team a player joining a challenge goes to, or nil if it's full.
-- `counts` = players on each team so far (the challenger is on team 1).
function PickleballRules.pickTeam(mode: string, counts: { number }, wanted: number?): number?
	local size = PickleballRules.teamSize(mode)
	if wanted and (wanted == 1 or wanted == 2) and counts[wanted] < size then
		return wanted
	end
	if counts[2] < size then
		return 2
	end
	if counts[1] < size then
		return 1
	end
	return nil
end

function PickleballRules.isFull(mode: string, counts: { number }): boolean
	local size = PickleballRules.teamSize(mode)
	return counts[1] >= size and counts[2] >= size
end

return PickleballRules
