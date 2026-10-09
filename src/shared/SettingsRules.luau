--!strict
--[[
	Pure rules for player settings (Config/SettingsConfig, docs/UI.md
	"Settings"). Used by the server to sanitize saved data and check
	Settings.Set requests, and by the client to read Profile.Sync.

	Settings are on/off switches only. A setting this server doesn't know is
	kept as saved (bounded): a newer server may have added it, and dropping it
	during a rolling update would reset the player's choice.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsConfig = require(ReplicatedStorage.Config.SettingsConfig)
local Validate = require(script.Parent.Validate)

export type Settings = { [string]: boolean }

local SettingsRules = {}

function SettingsRules.defaults(): Settings
	local settings: Settings = {}
	for _, setting in SettingsConfig.List do
		settings[setting.Key] = setting.Default
	end
	return settings
end

-- A clean copy: every known setting present (default when missing or not a
-- boolean), plus up to MaxSavedKeys unknown boolean ones with id-like keys.
function SettingsRules.sanitize(raw: unknown): Settings
	local settings = SettingsRules.defaults()
	if typeof(raw) ~= "table" then
		return settings
	end
	local unknownKept = 0
	for key, value in raw :: { [unknown]: unknown } do
		if typeof(value) ~= "boolean" then
			continue
		end
		if typeof(key) == "string" and SettingsConfig.ByKey[key] then
			settings[key] = value
		else
			local id = Validate.id(key, SettingsConfig.MaxKeyLength)
			if id and unknownKept < SettingsConfig.MaxSavedKeys then
				settings[id] = value
				unknownKept += 1
			end
		end
	end
	return settings
end

-- A Settings.Set request: a known key and a boolean. Returns nil for anything
-- else, so the server can refuse it.
function SettingsRules.parseChange(rawKey: unknown, rawValue: unknown): (string?, boolean?)
	local key = Validate.id(rawKey, SettingsConfig.MaxKeyLength)
	if key == nil or SettingsConfig.ByKey[key] == nil then
		return nil, nil
	end
	local value = Validate.boolean(rawValue)
	if value == nil then
		return nil, nil
	end
	return key, value
end

-- The value of a known setting, falling back to its default.
function SettingsRules.get(settings: Settings?, key: string): boolean
	local value = if settings then settings[key] else nil
	if typeof(value) == "boolean" then
		return value
	end
	local setting = SettingsConfig.ByKey[key]
	return if setting then setting.Default else false
end

return SettingsRules
