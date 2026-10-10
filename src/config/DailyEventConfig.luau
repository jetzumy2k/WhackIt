--!strict
--[[
	The Event of the Day (major update Phase 5a, docs/DAILY_EVENTS.md;
	decisions D10, D12, D13). Every UTC day one event from Rotation runs in
	every server, chosen by the date alone (no storage, no admin). Players
	earn points from what they already do (ActivityService events, the same
	names as QuestConfig.Events); each event weights them differently, and
	every event can be finished alone. Reaching a tier pays it at once.
	Values marked (P) are provisional.
]]

export type Tier = {
	Points: number,
	Coins: number,
	Xp: number,
	Supply: boolean, -- an office supply roll (PickleballConfig.Supplies.Winner pool)
}

export type DailyEvent = {
	Id: string,
	Name: string,
	Icon: string,
	Text: string, -- one line: what the day is about
	Points: { [string]: number }, -- activity event -> points per unit
	PointsText: string, -- how points are earned, shown to players
}

local function e(
	id: string,
	name: string,
	icon: string,
	text: string,
	points: { [string]: number },
	pointsText: string
): DailyEvent
	return table.freeze({
		Id = id,
		Name = name,
		Icon = icon,
		Text = text,
		Points = table.freeze(points),
		PointsText = pointsText,
	})
end

-- In order; day n (days since 1970-01-01 UTC) runs Rotation[n % #Rotation + 1].
local rotation: { DailyEvent } = {
	e(
		"boss_celebration",
		"Boss Celebration",
		"🎉",
		"The bosses are throwing a party. Crash it!",
		{ DefeatBoss = 3, ReachZen = 4 },
		"3 per boss defeated, 4 per Zen"
	),
	e(
		"zen_challenge",
		"Zen Challenge",
		"🧘",
		"Find your calm as often as you can today.",
		{ ReachZen = 10, DefeatBoss = 1 },
		"10 per Zen, 1 per boss defeated"
	),
	e(
		"pickleball_day",
		"Pickleball Day",
		"🏓",
		"The Recreation Center is the place to be.",
		{ PlayMatch = 15, WinMatch = 10, DefeatBoss = 1 },
		"15 per pickleball match, +10 for a win, 1 per boss defeated"
	),
	e(
		"coin_rush",
		"Coin Rush",
		"💰",
		"Bring in the coins: every coin from a boss counts today.",
		{ EarnCoins = 0.05, DefeatBoss = 1 },
		"1 per 20 coins from bosses, 1 per boss defeated"
	),
	e(
		"office_makeover",
		"Office Makeover",
		"🛋️",
		"Spruce up the office and see what your coworkers did.",
		{ PlaceFurniture = 4, VisitOffice = 6, DefeatBoss = 1 },
		"4 per piece of furniture placed, 6 per office visited, 1 per boss defeated"
	),
}

local byId: { [string]: DailyEvent } = {}
for _, event in rotation do
	assert(byId[event.Id] == nil, "duplicate daily event " .. event.Id)
	byId[event.Id] = event
end

local DailyEventConfig = table.freeze({
	Rotation = table.freeze(rotation),
	ById = table.freeze(byId),
	-- The same goals every day (points), so the events stay comparable. (P)
	Tiers = table.freeze({
		table.freeze({ Points = 30, Coins = 100, Xp = 250, Supply = false }),
		table.freeze({ Points = 80, Coins = 250, Xp = 600, Supply = false }),
		table.freeze({ Points = 150, Coins = 500, Xp = 1200, Supply = true }),
	} :: { Tier }),
	-- Points above this per day are not counted (a sanity cap).
	MaxPoints = 100000,
})

return DailyEventConfig
