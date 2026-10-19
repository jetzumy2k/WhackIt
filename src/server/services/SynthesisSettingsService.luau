--!strict
--[[
	Admin on/off switches for Synthesis Machine recipes (docs/SYNTHESIS.md),
	shared by every server. Admins flip them in Admin -> Synthesis; they're
	saved in DataStore `SynthesisSettings` (key `Global`) and a
	MessagingService ping tells other servers to reload. A periodic reload
	covers missed pings. No saved switch means the recipe's
	SynthesisConfig Enabled.

	The switches in effect go to Shared/SynthesisRules.setSwitches (so the
	server's plan() refuses a switched-off recipe at once) and to the
	Remotes.Synthesis attributes "On_<recipe id>", which replicate to every
	client for the window and the Admin panel.

	Saved data is validated on every load. If loading fails, the current
	switches stay. Without DataStore access (Studio, unpublished place) a
	change applies to this server only. AdminService does the permission
	checks before calling in.
]]

local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AdminConfig = require(ServerScriptService.Config.AdminConfig)
local SynthesisRules = require(ReplicatedStorage.Shared.SynthesisRules)

local SynthesisSettingsService = {}

local settingsStore: DataStore? = nil
local changedCallbacks: { () -> () } = {}

local function apply(switches: SynthesisRules.Switches): ()
	SynthesisRules.setSwitches(switches)
	local folder = ReplicatedStorage.Remotes.Synthesis
	for name, on in SynthesisRules.switchAttributes() do
		folder:SetAttribute(name, on)
	end
	for _, callback in changedCallbacks do
		task.spawn(callback)
	end
end

local function load(): ()
	local store = settingsStore
	if store == nil then
		return
	end
	local ok, saved = pcall(function()
		return store:GetAsync(AdminConfig.SynthesisKey)
	end)
	if not ok then
		warn("[Synthesis] couldn't load recipe switches, keeping current ones: " .. tostring(saved))
		return
	end
	if saved == nil then
		apply({})
		return
	end
	local parsed = SynthesisRules.parseSwitches(saved)
	if parsed then
		apply(parsed)
	else
		warn("[Synthesis] saved recipe switches are invalid, keeping current ones")
	end
end

function SynthesisSettingsService.onChanged(callback: () -> ()): ()
	table.insert(changedCallbacks, callback)
end

-- Turns one recipe on or off for every server, or (recipeId nil) clears every
-- switch so the config applies again. Yields. Returns (ok, message).
function SynthesisSettingsService.save(recipeId: string?, on: boolean): (boolean, string)
	local store = settingsStore
	if store == nil then
		local switches = if recipeId then SynthesisRules.switches() else {}
		if recipeId then
			switches[recipeId] = on
		end
		apply(switches)
		return true, "Changed in this server only (no DataStore access)."
	end
	local applied: SynthesisRules.Switches = {}
	-- Returns a value so pcall gives (ok, error) on both paths.
	local ok, err = pcall(function(): boolean
		if recipeId == nil then
			store:RemoveAsync(AdminConfig.SynthesisKey)
		else
			local id: string = recipeId
			-- UpdateAsync so two admins on different servers can't undo each
			-- other's switches.
			store:UpdateAsync(AdminConfig.SynthesisKey, function(old: unknown)
				local parsed = if old == nil then nil else (SynthesisRules.parseSwitches(old))
				local switches: SynthesisRules.Switches = parsed or {}
				switches[id] = on
				applied = switches
				return switches
			end)
		end
		return true
	end)
	if not ok then
		warn("[Synthesis] saving recipe switches failed: " .. tostring(err))
		return false, "Saving failed. Try again in a moment."
	end
	apply(applied)
	local published, publishErr = pcall(function()
		MessagingService:PublishAsync(AdminConfig.SynthesisTopic, "changed")
	end)
	if not published then
		-- Other servers still pick it up on their next refresh.
		warn("[Synthesis] couldn't notify other servers: " .. tostring(publishErr))
	end
	return true, "Saved for all servers."
end

function SynthesisSettingsService.init(): ()
	-- The config's switches until the saved ones load.
	apply({})
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(AdminConfig.SynthesisStoreName)
	end)
	if ok then
		settingsStore = store
	else
		warn("[Synthesis] DataStore unavailable: " .. tostring(store))
	end
end

function SynthesisSettingsService.start(): ()
	load()
	local subscribed, err = pcall(function()
		MessagingService:SubscribeAsync(AdminConfig.SynthesisTopic, function()
			load()
		end)
	end)
	if not subscribed then
		warn(
			"[Synthesis] cross-server updates unavailable, using periodic refresh: "
				.. tostring(err)
		)
	end
	while true do
		task.wait(AdminConfig.SynthesisRefreshSeconds)
		load()
	end
end

return SynthesisSettingsService
