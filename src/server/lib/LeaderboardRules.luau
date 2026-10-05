--!strict
-- Pure helpers for the global leaderboard: ranking and the text shown per row.

export type Entry = {
	UserId: number,
	Name: string,
	Score: number,
}

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

return LeaderboardRules
