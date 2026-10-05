--!strict
-- Server-only store administration settings (docs/STORE.md).

local StoreAdminConfig = table.freeze({
	-- Extra admins besides the experience owner (the creator, or the owner of the
	-- creator group, is always an admin). Add Roblox UserIds here.
	AdminUserIds = table.freeze({} :: { number }),

	-- In Studio playtests the local tester is an admin so the panel can be tried.
	StudioTesterIsAdmin = true,

	-- Store mode used until an admin has saved one (and if loading it fails).
	DefaultMode = "On",

	-- Where the admin's settings live, shared by all servers.
	SettingsStoreName = "StoreSettings",
	SettingsKey = "Global",
	MessagingTopic = "StoreSettings",

	-- Re-read the saved settings this often, in case a cross-server message was missed.
	RefreshSeconds = 300,

	-- How long ProcessReceipt waits for a player's data to load, and for the
	-- purchase to be saved, before asking Roblox to retry later.
	ReceiptDataWaitSeconds = 20,
	ReceiptSaveWaitSeconds = 20,
})

return StoreAdminConfig
