--!strict
-- Gives every character its equipped hammer on spawn and keeps it in hand.
-- The Backpack hotbar is hidden on the client, so the hammer is the only tool.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)
local HammerRules = require(ReplicatedStorage.Shared.HammerRules)
local HammerTool = require(ServerScriptService.Lib.HammerTool)
local PlayerDataService = require(script.Parent.PlayerDataService)

local HammerService = {}

local CHARACTER_LOAD_TIMEOUT = 10 -- seconds to wait for a Humanoid before giving up

local function equippedHammer(player: Player): HammerTool.HammerLook?
	-- Read from the saved data, not the session: on load, this service may run
	-- before SessionService has created the session. Before the data loads the
	-- character gets the default hammer, swapped once the data arrives.
	local data = PlayerDataService.get(player)
	if data == nil then
		return HammerConfig.ById[GameConfig.DefaultHammerId]
	end
	return HammerRules.resolve(data.EquippedHammerId, data.MysteryHammers)
end

local function removeHammers(container: Instance?): ()
	if container == nil then
		return
	end
	for _, child in container:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute(HammerTool.HAMMER_ID_ATTRIBUTE) ~= nil then
			child:Destroy()
		end
	end
end

local function giveHammer(player: Player, character: Model): ()
	local humanoid = character:WaitForChild("Humanoid", CHARACTER_LOAD_TIMEOUT)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if humanoid == nil or not humanoid:IsA("Humanoid") or backpack == nil then
		warn(string.format("[HammerService] could not equip hammer for %d", player.UserId))
		return
	end

	local hammer = equippedHammer(player)
	if hammer == nil then
		warn(string.format("[HammerService] unknown hammer for %d", player.UserId))
		return
	end

	-- Exactly one hammer: drop any earlier one (e.g. the default given before
	-- the saved data loaded).
	removeHammers(character)
	removeHammers(backpack)

	local tool = HammerTool.build(hammer)
	tool.Parent = backpack
	humanoid:EquipTool(tool)
end

-- Swaps the held hammer for the saved EquippedHammerId (after data loads or
-- the player equips a different hammer).
function HammerService.reequip(player: Player): ()
	local character = player.Character
	if character then
		task.spawn(giveHammer, player, character)
	end
end

local watched: { [Player]: boolean } = {}

local function watch(player: Player): ()
	-- A player joining between init() and start() is seen by both; watch once.
	if watched[player] then
		return
	end
	watched[player] = true

	player.CharacterAdded:Connect(function(character: Model)
		giveHammer(player, character)
	end)
	if player.Character then
		task.spawn(giveHammer, player, player.Character)
	end
end

function HammerService.init(): ()
	Players.PlayerAdded:Connect(watch)
	PlayerDataService.onLoaded(function(player: Player)
		HammerService.reequip(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		watched[player] = nil
	end)
end

function HammerService.start(): ()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return HammerService
