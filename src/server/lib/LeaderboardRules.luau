--!strict
-- Pure helpers for the global leaderboard (LeaderboardService): ranking, the
-- text shown per row, and combining the three ranked stats (Score, XP for
-- Level, Coins) with the live values of players in this server.

export type Entry = {
	UserId: number,
	Name: string,
	Score: number,
}

-- One player's known stats. A stat is nil when unknown (e.g. an offline
-- player who isn't in that stat's top list); the board shows a dash.
export type Row = {
	UserId: number,
	Name: string,
	Score: number?,
	Xp: number?,
	Coins: number?,
}

-- A ranked stat: "Score", "Xp" (Level) or "Coins".
export type Stat = string

-- One entry from an OrderedDataStore page.
export type PageItem = { UserId: number, Value: number }

local LeaderboardRules = {}

-- Highest score first; ties broken by lower UserId so the order is stable.
function LeaderboardRules.rank(entries: { Entry }, limit: number): { Entry }
	local sorted = table.clone(entries)
	table.sort(sorted, function(a: Entry, b: Entry): boolean
		if a.Score ~= b.Score then
			return a.Score > b.Score
		end
		return a.UserId < b.UserId
	end)
	local top: { Entry } = {}
	for index = 1, math.min(limit, #sorted) do
		table.insert(top, sorted[index])
	end
	return top
end

-- "1,234,567" style thousands separators.
function LeaderboardRules.formatScore(score: number): string
	local digits = tostring(math.floor(math.max(0, score)))
	local formatted = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

function LeaderboardRules.rowText(rank: number, entry: Entry): string
	return string.format("%d. %s  %s", rank, entry.Name, LeaderboardRules.formatScore(entry.Score))
end

LeaderboardRules.STATS = table.freeze({ "Score", "Xp", "Coins" })

local function valueOf(row: Row, stat: Stat): number?
	if stat == "Score" then
		return row.Score
	elseif stat == "Xp" then
		return row.Xp
	elseif stat == "Coins" then
		return row.Coins
	end
	return nil
end

local function setValue(row: Row, stat: Stat, value: number): ()
	if stat == "Score" then
		row.Score = value
	elseif stat == "Xp" then
		row.Xp = value
	elseif stat == "Coins" then
		row.Coins = value
	end
end

-- Whole, non-negative and finite; anything else (bad saved values) is unknown.
local function clean(value: unknown): number?
	if typeof(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
		return nil
	end
	return math.floor(value)
end

-- Rows that have `stat`, highest first (ties: lower UserId), at most `limit`.
function LeaderboardRules.rankBy(rows: { Row }, stat: Stat, limit: number): { Row }
	local withStat: { Row } = {}
	for _, row in rows do
		if valueOf(row, stat) ~= nil then
			table.insert(withStat, row)
		end
	end
	table.sort(withStat, function(a: Row, b: Row): boolean
		local va, vb = valueOf(a, stat) :: number, valueOf(b, stat) :: number
		if va ~= vb then
			return va > vb
		end
		return a.UserId < b.UserId
	end)
	local top: { Row } = {}
	for index = 1, math.min(limit, #withStat) do
		table.insert(top, withStat[index])
	end
	return top
end

-- Combines the stores' top pages with the players in this server (whose live
-- values are fresher and win) into one row per player. `nameFor` gives a
-- display name for players not in this server.
function LeaderboardRules.merge(
	pages: { [Stat]: { PageItem } },
	online: { Row },
	nameFor: (userId: number) -> string
): { Row }
	local byUserId: { [number]: Row } = {}
	local order: { Row } = {}
	local function rowFor(userId: number, name: string?): Row
		local row = byUserId[userId]
		if row == nil then
			row = { UserId = userId, Name = name or nameFor(userId) }
			byUserId[userId] = row
			table.insert(order, row)
		end
		return row :: Row
	end
	for _, player in online do
		local row = rowFor(player.UserId, player.Name)
		row.Name = player.Name
		for _, stat in LeaderboardRules.STATS do
			local value = clean(valueOf(player, stat))
			if value then
				setValue(row, stat, value)
			end
		end
	end
	for stat, page in pages do
		for _, item in page do
			local value = clean(item.Value)
			if value and item.UserId > 0 then
				local row = rowFor(item.UserId, nil)
				-- Players here already have their live value.
				if valueOf(row, stat) == nil then
					setValue(row, stat, value)
				end
			end
		end
	end
	return order
end

-- 1-based position of `userId` in a ranked list, or nil.
function LeaderboardRules.positionOf(ranked: { Row }, userId: number): number?
	for index, row in ranked do
		if row.UserId == userId then
			return index
		end
	end
	return nil
end

return LeaderboardRules
