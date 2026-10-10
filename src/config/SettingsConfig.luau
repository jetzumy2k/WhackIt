--!strict
-- Player settings (docs/UI.md "Settings"). Every setting is an on/off switch
-- saved in the player's data (PlayerData.Settings) and changed through the
-- Settings.Set remote, which only accepts the keys listed here.
--
-- Adding a setting: add an entry below. Saved data needs no migration: a
-- missing key reads as its Default (Shared/SettingsRules.sanitize).

export type Setting = {
	Key: string,
	Default: boolean,
	Label: string,
	Description: string,
}

local list: { Setting } = {
	{
		Key = "ReducedMotion",
		Default = false,
		Label = "Reduced motion",
		Description = "Panels and cards appear without zooming, bars jump to their new value, hits don't shake the camera and sprinting doesn't zoom out. Roblox's own Reduced Motion setting turns this on too.",
	},
	{
		Key = "HideChallenges",
		Default = false,
		Label = "Hide challenge notices",
		Description = "Other players' pickleball challenges don't pop up as cards. You can still see and accept them in the Pickleball panel.",
	},
}

local byKey: { [string]: Setting } = {}
for _, setting in list do
	assert(byKey[setting.Key] == nil, "duplicate setting key " .. setting.Key)
	byKey[setting.Key] = table.freeze(setting)
end

local SettingsConfig = table.freeze({
	List = table.freeze(list),
	ByKey = table.freeze(byKey),
	-- Bounds for keys kept from saved data that this server doesn't know
	-- (a newer server may have added them), so a rolling update loses nothing.
	MaxKeyLength = 32,
	MaxSavedKeys = 32,
})

return SettingsConfig
