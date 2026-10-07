--!strict
--[[
	Office boss buff drop chances (Config/DropRateConfig, Shared/DropRateRules),
	shared by every server. Admins change them in the Admin panel; they're
	saved in DataStore `DropRates` (key `Global`) and a MessagingService ping
	tells other servers to reload. A periodic reload covers missed pings.
	No saved value means the DropRateConfig defaults.

	Saved data is validated on every load. If loading fails, the current
	settings stay. AdminService does the permission checks before calling in.
]]

local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AdminConfig = require(ServerScriptService.Config.AdminConfig)
local DropRateRules = require(ReplicatedStorage.Shared.DropRateRules)

local DropRateService = {}

local settings: DropRateRules.Settings = DropRateRules.default()
local rateStore: DataStore? = nil
local changedCallbacks: { () -> () } = {}

local function apply(newSettings: DropRateRules.Settings): ()
	settings = newSettings
	for _, callback in changedCallbacks do
		task.spawn(callback)
	end
end

local function load(): ()
	local store = rateStore
	if store == nil then
		return
	end
	local ok, saved = pcall(function()
		return store:GetAsync(AdminConfig.DropRateKey)
	end)
	if not ok then
		warn("[DropRate] couldn't load drop rates, keeping current ones: " .. tostring(saved))
		return
	end
	if saved == nil then
		apply(DropRateRules.default())
		return
	end
	local parsed = DropRateRules.parse(saved)
	if parsed then
		apply(parsed)
	else
		warn("[DropRate] saved drop rates are invalid, keeping current ones")
	end
end

function DropRateService.settings(): DropRateRules.Settings
	return settings
end

-- The drop chance for one office boss roll in [0, 1), right now.
function DropRateService.chance(roll: number): number
	return DropRateRules.chanceFor(settings, os.time(), roll)
end

function DropRateService.onChanged(callback: () -> ()): ()
	table.insert(changedCallbacks, callback)
end

-- Saves `newSettings` (already validated) for every server, or clears the
-- saved value when nil so the defaults apply. Yields. Returns (ok, message).
function DropRateService.save(newSettings: DropRateRules.Settings?): (boolean, string)
	local store = rateStore
	if store == nil then
		return false, "Drop rates are unavailable (no DataStore access)."
	end
	local ok, err = pcall(function()
		if newSettings then
			store:SetAsync(AdminConfig.DropRateKey, newSettings)
		else
			store:RemoveAsync(AdminConfig.DropRateKey)
		end
	end)
	if not ok then
		warn("[DropRate] save failed: " .. tostring(err))
		return false, "Saving failed. Try again in a moment."
	end
	apply(newSettings or DropRateRules.default())
	local published, publishErr = pcall(function()
		MessagingService:PublishAsync(AdminConfig.DropRateTopic, "changed")
	end)
	if not published then
		-- Other servers still pick it up on their next refresh.
		warn("[DropRate] couldn't notify other servers: " .. tostring(publishErr))
	end
	return true, "Saved for all servers."
end

function DropRateService.init(): ()
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(AdminConfig.DropRateStoreName)
	end)
	if ok then
		rateStore = store
	else
		warn("[DropRate] DataStore unavailable: " .. tostring(store))
	end
end

function DropRateService.start(): ()
	load()
	local subscribed, err = pcall(function()
		MessagingService:SubscribeAsync(AdminConfig.DropRateTopic, function()
			load()
		end)
	end)
	if not subscribed then
		warn(
			"[DropRate] cross-server updates unavailable, using periodic refresh: " .. tostring(err)
		)
	end
	while true do
		task.wait(AdminConfig.DropRateRefreshSeconds)
		load()
	end
end

return DropRateService
