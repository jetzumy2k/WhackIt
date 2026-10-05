--!strict
-- Server-only persistence settings. Changing StoreName or KeyPrefix makes every
-- player start over, so treat them as permanent (see docs/DATA_SCHEMA.md).

local DataConfig = table.freeze({
	StoreName = "PlayerData",
	KeyPrefix = "Player_", -- full key: Player_<UserId>

	-- Shown when a player is kicked to protect their data.
	LoadFailedMessage = "We couldn't load your saved progress. Please rejoin in a moment.",
	SessionEndedMessage = "Your progress was opened on another server. Please rejoin.",
	NewerDataMessage = "Your progress was saved by a newer version of the game. Please rejoin.",
})

return DataConfig
