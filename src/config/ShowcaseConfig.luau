--!strict
--[[
	The Office Showcase (docs/SHOWCASE.md, major update Phase 6a, D17/D20).
	Players publish a snapshot of their office to a gallery shared by every
	server; anyone can open a read-only copy of it, even while the owner is
	offline, like it once and report it.
]]

export type Reason = { Id: string, Label: string }
export type Tab = { Id: string, Label: string }

local DAY = 24 * 60 * 60

local ShowcaseConfig = table.freeze({
	-- Who may publish: a little play first keeps throwaway accounts out.
	MinLevel = 5,
	MinItems = 5,
	-- Seconds between two publishes (or updates) of the same office.
	PublishCooldown = 5 * 60,

	-- Gallery tabs (Featured is picked by admins).
	Tabs = table.freeze({
		{ Id = "Featured", Label = "⭐ Featured" },
		{ Id = "Newest", Label = "🆕 Newest" },
		{ Id = "Top", Label = "❤️ Top this week" },
	} :: { Tab }),
	PageSize = 18,
	MaxFeatured = 12,

	-- Moderation: hidden for everyone (until an admin looks) after this many
	-- different players report it; twice as many once an admin approved it.
	HideAfterReports = 3,
	MaxReporters = 20, -- the most recent reporters kept, so nobody reports twice
	-- A removed office can't be published again for this long, and then
	-- waits for an admin before others see it.
	RemovedBlockSeconds = 7 * DAY,
	ReportReasons = table.freeze({
		{ Id = "Inappropriate", Label = "Inappropriate shapes or layout" },
		{ Id = "Offensive", Label = "Mean or offensive" },
		{ Id = "Spam", Label = "Spam or empty" },
		{ Id = "Other", Label = "Something else" },
	} :: { Reason }),

	-- Remembered per player (saved data): offices liked and offices hidden
	-- after a report. The oldest are forgotten first.
	MaxLiked = 300,
	MaxHidden = 100,

	-- Read-only copies stand in their own row of rooms next to the Office Wing
	-- (Config/OfficeConfig), one room per office being looked at.
	RoomOrigin = Vector3.new(2000, 300, 120),
	RoomSpacing = 60,
	MaxRooms = 8,
	-- An empty copy room is taken down after this many seconds.
	RoomIdleSeconds = 30,

	-- Server caches and batching (DataStore budgets).
	ListCacheSeconds = 60,
	SnapshotCacheSeconds = 120,
	FlushInterval = 60, -- likes and visits are added up and saved this often
})

return ShowcaseConfig
