--!strict
--[[
	Level reward looks (docs/GAMEPLAY_RULES.md "Level rewards"): the hammer
	trail, Zen glow and office theme a player picked from the ones their
	level unlocked (the office theme is painted by OfficeService).

	  * Level.SetCosmetic(kind, id): "Trail", "Glow" or "Office", and "" (default) or a
	    LevelRewardConfig id the player's level has unlocked. Saved in
	    PlayerData.Cosmetics.
	  * The look in use is published as the TrailStyle / GlowStyle player
	    attributes (MoodService draws the glow, HammerService the trail), and
	    only while still unlocked: if an admin lowers the level, the default
	    look comes back until the level does.

	Level-up coins are paid where XP is added (SessionService.addXp); titles
	follow the level on their own (MoodService).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Attributes = require(ReplicatedStorage.Shared.Attributes)
local HammerService = require(script.Parent.HammerService)
local LevelRewardRules = require(ReplicatedStorage.Shared.LevelRewardRules)
local LevelRules = require(ReplicatedStorage.Shared.LevelRules)
local OfficeService = require(script.Parent.OfficeService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)
local RemoteController = require(ServerScriptService.Controllers.RemoteController)
local RemoteLimits = require(ServerScriptService.Config.RemoteLimits)

local SetCosmeticRemote = ReplicatedStorage.Remotes.Level.SetCosmetic

local LevelRewardService = {}

-- Publishes the looks in use; re-equips the hammer when the trail changed.
local function apply(player: Player): ()
	local data = PlayerDataService.get(player)
	if data == nil then
		return
	end
	local level = LevelRules.levelFor(data.Xp)
	local trail = LevelRewardRules.effective("Trail", data.Cosmetics.Trail, level)
	local glow = LevelRewardRules.effective("Glow", data.Cosmetics.Glow, level)
	-- Joining with the default trail needs no rebuild (HammerService already
	-- hands out the hammer when data loads).
	local previous = player:GetAttribute(Attributes.TrailStyle)
	local trailChanged = previous ~= trail and not (previous == nil and trail == "")
	player:SetAttribute(Attributes.TrailStyle, trail)
	player:SetAttribute(Attributes.GlowStyle, glow)
	if trailChanged then
		HammerService.reequip(player)
	end
	OfficeService.applyTheme(player)
end

local function onSetCosmetic(player: Player, rawKind: unknown, rawId: unknown): ()
	local parsedKind, id = LevelRewardRules.parseChoice(rawKind, rawId)
	if parsedKind == nil or id == nil then
		return RemoteController.reject(player, "Level.SetCosmetic", "unknown look")
	end
	local kind = parsedKind :: LevelRewardRules.CosmeticKind
	local data = PlayerDataService.get(player)
	if data == nil then
		return
	end
	-- A locked pick is a normal UI race (the level just changed): ignore it.
	if LevelRewardRules.isUnlocked(kind, id, LevelRules.levelFor(data.Xp)) then
		if kind == "Trail" then
			data.Cosmetics.Trail = id
		elseif kind == "Glow" then
			data.Cosmetics.Glow = id
		else
			data.Cosmetics.Office = id
		end
		apply(player)
	end
	ProgressService.sync(player)
end

function LevelRewardService.init(): ()
	RemoteController.bind(SetCosmeticRemote, {
		name = "Level.SetCosmetic",
		maxArgs = 2,
		rateLimit = RemoteLimits.Settings,
	}, onSetCosmetic)
	PlayerDataService.onLoaded(function(player: Player)
		apply(player)
		-- Levels change with XP (and admins): keep the looks in step.
		player:GetAttributeChangedSignal(Attributes.Level):Connect(function()
			apply(player)
		end)
	end)
end

return LevelRewardService
