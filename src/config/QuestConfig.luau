--!strict
--[[
	Quests (major update Phase 2b, docs/QUESTS.md; decisions D7-D9). Quests
	only count things the game already does; the server counts them
	(QuestService), never the client. Values marked (P) are provisional.

	Kinds:
	  * Tutorial: a short chain, one quest at a time, in order.
	  * Daily: Slots quests drawn at 00:00 UTC, one free reroll a day, and a
	    bonus for claiming all of them.
	  * Weekly: Slots quests drawn on Mondays 00:00 UTC (like pickleball
	    seasons); each also rolls an office supply.

	Events (what a quest counts; QuestService.record):
	  DefeatBoss      a boss defeat that rewarded you (you qualified)
	  EarnCoins       coins from those defeats (amount)
	  ReachZen        a rewarded Zen
	  PlayMatch       a rewarded (not friendly) pickleball match, win or lose
	  WinMatch        a rewarded pickleball win
	  PlaceFurniture  a piece placed in your office
	  VisitOffice     arriving in another player's office
	  HatchPet        a pet hatched
]]

export type Kind = "Tutorial" | "Daily" | "Weekly"

export type Quest = {
	Id: string,
	Kind: Kind,
	Event: string,
	Target: number,
	Text: string, -- what to do, shown on the quest
	Coins: number,
	Xp: number,
	MinLevel: number?, -- drawn only for players at this Player Level or above
}

local EVENTS = table.freeze({
	"DefeatBoss",
	"EarnCoins",
	"ReachZen",
	"PlayMatch",
	"WinMatch",
	"PlaceFurniture",
	"VisitOffice",
	"HatchPet",
})

local function q(
	id: string,
	kind: Kind,
	event: string,
	target: number,
	text: string,
	coins: number,
	xp: number,
	minLevel: number?
): Quest
	return table.freeze({
		Id = id,
		Kind = kind,
		Event = event,
		Target = target,
		Text = text,
		Coins = coins,
		Xp = xp,
		MinLevel = minLevel,
	})
end

-- In order. Every step can be done alone.
local tutorial: { Quest } = {
	q("tut_first_boss", "Tutorial", "DefeatBoss", 1, "Whack your first boss", 50, 150),
	q("tut_zen", "Tutorial", "ReachZen", 1, "Bring your Stress Meter down to 0 (Zen)", 100, 300),
	q(
		"tut_furniture",
		"Tutorial",
		"PlaceFurniture",
		1,
		"Place a piece of furniture in your office (🏢 Social → Go to my office → Edit)",
		100,
		300
	),
	q("tut_five_bosses", "Tutorial", "DefeatBoss", 5, "Defeat 5 more bosses", 200, 600),
}

local daily: { Quest } = {
	q("d_bosses_3", "Daily", "DefeatBoss", 3, "Defeat 3 bosses", 120, 300),
	q("d_bosses_8", "Daily", "DefeatBoss", 8, "Defeat 8 bosses", 220, 600, 3),
	q("d_zen_1", "Daily", "ReachZen", 1, "Reach Zen", 120, 300),
	q("d_zen_2", "Daily", "ReachZen", 2, "Reach Zen twice", 200, 500, 3),
	q("d_coins_400", "Daily", "EarnCoins", 400, "Earn 400 coins from bosses", 120, 300),
	q("d_match_1", "Daily", "PlayMatch", 1, "Play a pickleball match", 150, 350),
	q(
		"d_furniture_2",
		"Daily",
		"PlaceFurniture",
		2,
		"Place 2 pieces of furniture in your office",
		100,
		250
	),
	q("d_visit_1", "Daily", "VisitOffice", 1, "Visit another player's office", 100, 250),
}

local weekly: { Quest } = {
	q("w_bosses_40", "Weekly", "DefeatBoss", 40, "Defeat 40 bosses", 700, 2000),
	q("w_zen_6", "Weekly", "ReachZen", 6, "Reach Zen 6 times", 600, 1800),
	q("w_coins_5000", "Weekly", "EarnCoins", 5000, "Earn 5,000 coins from bosses", 700, 2000),
	q("w_matches_5", "Weekly", "PlayMatch", 5, "Play 5 pickleball matches", 700, 2000),
	q("w_wins_3", "Weekly", "WinMatch", 3, "Win 3 pickleball matches", 800, 2200),
	q("w_visits_3", "Weekly", "VisitOffice", 3, "Visit 3 other players' offices", 500, 1500),
	q("w_hatch_1", "Weekly", "HatchPet", 1, "Hatch a pet", 500, 1500),
}

local byId: { [string]: Quest } = {}
for _, list in { tutorial, daily, weekly } do
	for _, quest in list do
		assert(byId[quest.Id] == nil, "duplicate quest id " .. quest.Id)
		assert(table.find(EVENTS, quest.Event), "unknown quest event " .. quest.Event)
		byId[quest.Id] = quest
	end
end

local QuestConfig = table.freeze({
	Events = EVENTS,
	Tutorial = table.freeze(tutorial),
	Daily = table.freeze(daily),
	Weekly = table.freeze(weekly),
	ById = table.freeze(byId),

	Slots = table.freeze({ Daily = 3, Weekly = 3 }),
	DailyRerolls = 1, -- free rerolls of an unfinished daily quest per UTC day
	-- Claiming all of today's daily quests (P).
	DailyBonus = table.freeze({ Coins = 200, Xp = 500 }),
	-- Weeks start Monday 00:00 UTC (1970-01-05 was a Monday).
	WeekEpoch = 4 * 86400,
	-- Progress is counted up to the target; amounts above this per event are
	-- ignored as bad input.
	MaxEventAmount = 1000000,
})

return QuestConfig
