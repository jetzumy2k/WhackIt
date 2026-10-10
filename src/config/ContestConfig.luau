--!strict
--[[
	Weekly office design contests (docs/CONTESTS.md, major update Phase 6b,
	owner decisions D18/D19).

	Weeks run Monday 00:00 to Monday 00:00 UTC (Shared/ShowcaseRules.weekId).
	Monday-Friday: enter with your office. Saturday-Sunday: vote. The week's
	results are frozen FreezeDelay after it ends and paid when players join.
]]

export type Theme = {
	Id: string,
	Name: string,
	Icon: string,
	Text: string,
	-- Furniture that fits the theme; each different one used counts.
	Items: { string },
}

export type Prize = {
	FromRank: number,
	ToRank: number,
	Coins: number,
	Xp: number,
	Item: string?, -- Special furniture (Config/FurnitureConfig)
}

local themes: { Theme } = {
	{
		Id = "zen_retreat",
		Name = "Zen Retreat",
		Icon = "🧘",
		Text = "A calm corner to breathe out: plants, soft light, somewhere to sit.",
		Items = {
			"plant_small",
			"plant_tall",
			"rug_round",
			"floor_lamp",
			"bean_bag",
			"zen_fountain",
			"aquarium",
			"bonsai_zen",
		},
	},
	{
		Id = "tech_startup",
		Name = "Tech Startup",
		Icon = "💻",
		Text = "Screens, servers and a whiteboard full of big ideas.",
		Items = {
			"workstation",
			"server_rack",
			"tv_screen",
			"desk_standing",
			"whiteboard",
			"printer",
			"arcade",
			"bean_bag",
		},
	},
	{
		Id = "cozy_cafe",
		Name = "Cozy Café",
		Icon = "☕",
		Text = "Coffee, comfy seats and the smell of fresh snacks.",
		Items = {
			"coffee_station",
			"sofa",
			"chair_lounge",
			"rug_rect",
			"floor_lamp",
			"plant_small",
			"mini_fridge",
			"snack_machine",
		},
	},
	{
		Id = "game_room",
		Name = "Game Room",
		Icon = "🕹️",
		Text = "The best break room in the building.",
		Items = {
			"arcade",
			"tv_screen",
			"bean_bag",
			"sofa",
			"stress_ball",
			"snack_machine",
			"neon_calm_sign",
			"mini_fridge",
		},
	},
	{
		Id = "executive_suite",
		Name = "Executive Suite",
		Icon = "👔",
		Text = "Very important office. Very important bookshelf.",
		Items = {
			"chair_office",
			"bookshelf",
			"filing_cabinet",
			"rug_rect",
			"coat_rack",
			"desk_executive",
			"golden_statue",
			"trophy_gold",
		},
	},
	{
		Id = "sports_club",
		Name = "Sports Club",
		Icon = "🏓",
		Text = "Trophies on the shelf, paddles on the wall, the match on TV.",
		Items = {
			"water_cooler",
			"stress_ball",
			"poster_easel",
			"tv_screen",
			"coat_rack",
			"paddle_rack",
			"ball_bucket",
			"champion_plaque",
		},
	},
}
for _, theme in themes do
	table.freeze(theme.Items)
	table.freeze(theme)
end

local ContestConfig = table.freeze({
	Themes = table.freeze(themes),

	-- Days 0-4 of the week (Monday-Friday) take entries, days 5-6 voting.
	EntryDays = 5,
	-- Results wait this long after the week ends, so every server has saved
	-- its last votes.
	FreezeDelay = 15 * 60,
	-- Finished weeks checked for prizes when a player joins.
	ClaimWeeks = 3,

	-- Entering: the same bar as sharing in the Showcase.
	MinLevel = 5,
	MinItems = 5,
	EntryCooldown = 5 * 60,

	-- Voting.
	VoteMinLevel = 5,
	DailyVotes = 30,
	-- Seconds a voter must spend in an entry before rating it.
	MinViewSeconds = 5,
	MinStars = 1,
	MaxStars = 5,

	-- Score = fair average of the stars + theme bonus. The fair average
	-- starts every entry at PriorStars as if it had PriorVotes votes, so a
	-- handful of 5-star votes can't beat many honest ones.
	PriorStars = 3,
	PriorVotes = 5,
	-- Entries need this many votes to be ranked.
	MinVotesToRank = 3,
	-- Different theme items for the whole bonus, and the bonus in stars.
	FitTarget = 4,
	ThemeBonus = 0.5,

	Prizes = table.freeze({
		table.freeze({ FromRank = 1, ToRank = 1, Coins = 2000, Xp = 3000, Item = "design_trophy" }),
		table.freeze({ FromRank = 2, ToRank = 3, Coins = 1000, Xp = 1500, Item = "design_plaque" }),
		table.freeze({ FromRank = 4, ToRank = 10, Coins = 500, Xp = 800, Item = "design_ribbon" }),
	} :: { Prize }),
	-- Every other entry that wasn't removed.
	Participation = table.freeze({ FromRank = 0, ToRank = 0, Coins = 150, Xp = 300 } :: Prize),
	ResultsSize = 10,

	-- Server caches and batching (DataStore budgets).
	EntriesCacheSeconds = 120,
	FlushInterval = 60,
})

return ContestConfig
