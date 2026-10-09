--!strict
--[[
	Player settings on the client (docs/UI.md "Settings"). The saved values
	arrive in Profile.Sync (ProgressController); a change is shown at once and
	sent to the server (Settings.Set), whose next sync confirms or corrects it.
	Settings are cosmetic, so showing them before the server confirms is safe.

	Reduced motion is pushed into Lib/UiTokens, which every animation asks.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsRules =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SettingsRules"))

local ProgressController = require(script.Parent.ProgressController)
local UiTokens = require(script.Parent.Parent.Lib.UiTokens)

local SettingsController = {}

local changedEvent = Instance.new("BindableEvent")

-- Fires after any setting changed (locally or from a sync).
SettingsController.Changed = changedEvent.Event

local current: SettingsRules.Settings = SettingsRules.defaults()

local function same(a: SettingsRules.Settings, b: SettingsRules.Settings): boolean
	for key, value in a do
		if b[key] ~= value then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

-- Profile.Sync arrives after every coin or XP change: only real setting
-- changes are passed on.
local function apply(settings: SettingsRules.Settings): ()
	if same(current, settings) then
		return
	end
	current = settings
	UiTokens.setReducedMotion(SettingsRules.get(current, "ReducedMotion"))
	changedEvent:Fire()
end

function SettingsController.get(key: string): boolean
	return SettingsRules.get(current, key)
end

-- Shows the new value now and asks the server to save it.
function SettingsController.set(key: string, value: boolean): ()
	local updated = table.clone(current)
	updated[key] = value
	apply(updated)
	local remote =
		ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Settings"):WaitForChild("Set")
	assert(remote:IsA("RemoteEvent"), "Settings.Set must be a RemoteEvent")
	remote:FireServer(key, value)
end

function SettingsController.start(): ()
	local function refresh(): ()
		local snapshot = ProgressController.get()
		if snapshot then
			apply(snapshot.Settings)
		end
	end
	ProgressController.Changed:Connect(refresh)
	refresh()
end

return SettingsController
