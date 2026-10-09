--!strict
-- Admin server announcements (docs/ADMIN.md "Announce"). The server enforces
-- these (Shared/AnnouncementRules); the panel shows them as hints. The
-- per-admin cooldown is an abuse limit, so it lives in the server-only
-- AdminConfig.

local AnnouncementConfig = table.freeze({
	-- Characters (not bytes) after cleaning.
	MaxLength = 200,
	-- How long the message stays on players' screens; the admin picks one.
	Durations = table.freeze({ 5, 10, 15, 30 }),
	DefaultSeconds = 10,
})

return AnnouncementConfig
