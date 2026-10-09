--!strict
--[[
	Player settings (docs/UI.md "Settings", docs/REMOTE_CONTRACTS.md
	"Settings.Set"). The client names a known setting and an on/off value; the
	server checks both (Shared/SettingsRules.parseChange), saves the value in
	the player's data and sends a fresh Profile.Sync so the UI shows the saved
	state. Settings are cosmetic: no setting changes damage, rewards or access.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)
local RemoteController = require(ServerScriptService.Controllers.RemoteController)
local RemoteLimits = require(ServerScriptService.Config.RemoteLimits)
local SettingsRules = require(ReplicatedStorage.Shared.SettingsRules)

local SetRemote = ReplicatedStorage.Remotes.Settings.Set

local SettingsService = {}

local function onSet(player: Player, rawKey: unknown, rawValue: unknown): ()
	local key, value = SettingsRules.parseChange(rawKey, rawValue)
	if key == nil or value == nil then
		return RemoteController.reject(
			player,
			"SettingsSet",
			"unknown setting or non-boolean value"
		)
	end
	local data = PlayerDataService.get(player)
	if data == nil then
		return -- still loading: nothing to save into yet
	end
	data.Settings[key] = value
	ProgressService.sync(player)
end

function SettingsService.init(): ()
	RemoteController.bind(SetRemote, {
		name = "SettingsSet",
		maxArgs = 2,
		rateLimit = RemoteLimits.Settings,
	}, onSet)
end

return SettingsService
