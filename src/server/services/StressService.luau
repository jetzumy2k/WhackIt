--!strict
-- Owns each player's Stress Meter. The value is saved with the player's data
-- (PlayerDataService) and mirrored to the Player's "Stress" attribute purely so
-- clients can display it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require(ReplicatedStorage.Shared.Attributes)
local PlayerDataService = require(script.Parent.PlayerDataService)
local StressRules = require(ReplicatedStorage.Shared.StressRules)

local StressService = {}

-- Returns the stress actually relieved (less than requested near zero).
function StressService.relieve(player: Player, relief: number): number
	local data = PlayerDataService.get(player)
	if data == nil or relief <= 0 then
		return 0
	end
	local current = data.Stress
	local nextStress = StressRules.applyRelief(current, relief)
	data.Stress = nextStress
	player:SetAttribute(Attributes.Stress, nextStress)
	return current - nextStress
end

function StressService.init(): ()
	PlayerDataService.onLoaded(function(player: Player, data: PlayerDataService.PlayerData)
		player:SetAttribute(Attributes.Stress, data.Stress)
	end)
end

return StressService
