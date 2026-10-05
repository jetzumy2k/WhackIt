--!strict
-- Server-only persistence settings. Changing StoreName or KeyPrefix makes every
-- player start over, so treat them as permanent (see docs/DATA_SCHEMA.md).

local DataConfig = table.freeze({
	StoreName = "PlayerData",
	KeyPrefix = "Player_", -- full key: Player_<UserId>

	-- Global leaderboard (OrderedDataStore keyed by UserId, value = lifetime Score).
	LeaderboardStoreName = "ScoreLeaderboard",
	LeaderboardSize = 10,
	LeaderboardReadInterval = 60, -- seconds between refreshes of the board
	LeaderboardWriteInterval = 120, -- seconds between saving a player's score to it

	-- Shown when a player is kicked to protect their data.
	LoadFailedMessage = "We couldn't load your saved progress. Please rejoin in a moment.",
	SessionEndedMessage = "Your progress was opened on another server. Please rejoin.",
	NewerDataMessage = "Your progress was saved by a newer version of the game. Please rejoin.",
})

return DataConfig
