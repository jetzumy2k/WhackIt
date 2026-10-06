--!strict
-- Server-only settings for the Admin panel (docs/ADMIN.md). Who is an admin
-- is set in StoreAdminConfig (AdminUserIds, StudioTesterIsAdmin).

local AdminConfig = table.freeze({
	-- Set Level: highest level an admin can give.
	MaxSetLevel = 500,
	-- Set Damage: fixed damage per hit (0 clears it). Session only.
	MaxSetDamage = 1000000,

	-- Custom bosses, shared by every server.
	CustomBossStoreName = "CustomBosses",
	CustomBossKey = "Global",
	CustomBossTopic = "CustomBosses",
	CustomBossRefreshSeconds = 300,

	-- Ban / suspend (Players:BanAsync). Seconds; -1 is permanent.
	BanDurations = table.freeze({
		["1 hour"] = 3600,
		["1 day"] = 86400,
		["3 days"] = 3 * 86400,
		["7 days"] = 7 * 86400,
		["30 days"] = 30 * 86400,
		Permanent = -1,
	} :: { [string]: number }),
	-- Shown to the banned player, so only fixed, pre-written texts are allowed.
	BanReasons = table.freeze({
		Cheating = "Cheating or exploiting.",
		Harassment = "Harassing other players.",
		Inappropriate = "Inappropriate behavior.",
		Rules = "Breaking the game rules.",
	} :: { [string]: string }),
	-- The admin's private note (moderation history only, never shown to players).
	MaxNoteLength = 200,
	-- Roblox usernames are 3-20 characters.
	MaxUsernameLength = 20,
})

return AdminConfig
