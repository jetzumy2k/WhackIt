--!strict
-- Owns each player's Stress Meter. The value lives here and is mirrored to the
-- Player's "Stress" attribute purely so clients can display it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require(ReplicatedStorage.Shared.Attributes)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local StressRules = require(ReplicatedStorage.Shared.StressRules)

local StressService = {}

local stressByPlayer: { [Player]: number } = {}

local function setStress(player: Player, stress: number): ()
	stressByPlayer[player] = stress
	player:SetAttribute(Attributes.Stress, stress)
end

local function track(player: Player): ()
	if stressByPlayer[player] == nil then
		setStress(player, GameConfig.StartingStress)
	end
end

-- Returns the stress actually relieved (less than requested near zero).
function StressService.relieve(player: Player, relief: number): number
	local current = stressByPlayer[player]
	if current == nil or relief <= 0 then
		return 0
	end
	local nextStress = StressRules.applyRelief(current, relief)
	setStress(player, nextStress)
	return current - nextStress
end

function StressService.init(): ()
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(function(player: Player)
		stressByPlayer[player] = nil
	end)
end

function StressService.start(): ()
	for _, player in Players:GetPlayers() do
		track(player)
	end
end

return StressService
