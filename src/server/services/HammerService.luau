--!strict
-- Gives every character its equipped hammer on spawn and keeps it in hand.
-- The Backpack hotbar is hidden on the client, so the hammer is the only tool.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)
local HammerTool = require(ServerScriptService.Lib.HammerTool)
local SessionService = require(script.Parent.SessionService)

local HammerService = {}

local CHARACTER_LOAD_TIMEOUT = 10 -- seconds to wait for a Humanoid before giving up

local function equippedHammer(player: Player): HammerConfig.HammerDefinition?
	local session = SessionService.get(player)
	-- The character can spawn a moment before the session exists; fall back to the default.
	local hammerId = if session then session.EquippedHammerId else GameConfig.DefaultHammerId
	return HammerConfig.ById[hammerId]
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

	local tool = HammerTool.build(hammer)
	tool.Parent = backpack
	humanoid:EquipTool(tool)
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
