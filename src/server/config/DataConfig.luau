--!strict
-- Server-only persistence settings. Changing StoreName or KeyPrefix makes every
-- player start over, so treat them as permanent (see docs/DATA_SCHEMA.md).

local DataConfig = table.freeze({
	StoreName = "PlayerData",
	KeyPrefix = "Player_", -- full key: Player_<UserId>

	-- Global leaderboard (OrderedDataStores keyed by UserId): lifetime Score,
	-- and since 2026-10-07 XP (shown as Level) and current Coins for the
	-- board's Top Level / Top Coins tabs. All three are written from saved data.
	LeaderboardStoreName = "ScoreLeaderboard",
	XpLeaderboardStoreName = "XpLeaderboard",
	CoinsLeaderboardStoreName = "CoinsLeaderboard",
	LeaderboardSize = 10,
	LeaderboardReadInterval = 60, -- seconds between refreshes of the board
	LeaderboardWriteInterval = 120, -- seconds between saving a player's score to it

	-- Pickleball season board (RecreationRankService): one OrderedDataStore
	-- per season (<prefix><seasonId>, keyed by UserId, the season's rating),
	-- and the frozen top 10 of each finished season (key "Season_<id>").
	RecRatingStorePrefix = "RecRating_",
	RecSeasonsStoreName = "RecSeasons",

	-- Office Showcase (ShowcaseService): snapshots and the Featured list
	-- ("Office_<UserId>", "Featured"), plus OrderedDataStores
	-- <prefix>Newest, <prefix>Top_<weekId> and <prefix>Review.
	ShowcaseStoreName = "OfficeShowcase",
	ShowcaseBoardPrefix = "Showcase_",

	-- Shown when a player is kicked to protect their data.
	LoadFailedMessage = "We couldn't load your saved progress. Please rejoin in a moment.",
	SessionEndedMessage = "Your progress was opened on another server. Please rejoin.",
	NewerDataMessage = "Your progress was saved by a newer version of the game. Please rejoin.",
})

return DataConfig
