--!strict
-- Rests every hammer holder's hammer on their shoulder (Lib/SwingAnimator):
-- the local player and everyone else, since joint posing is local to each
-- client. Starts when a hammer Tool is equipped, stops when it is put away.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attributes"))
local SwingAnimator = require(script.Parent.Parent.Lib.SwingAnimator)

local HammerPoseController = {}

local function isHammer(instance: Instance): boolean
	return instance:IsA("Tool") and instance:GetAttribute(Attributes.HammerId) ~= nil
end

local function refresh(character: Model): ()
	local holding = false
	for _, child in character:GetChildren() do
		if isHammer(child) then
			holding = true
			break
		end
	end
	SwingAnimator.setHolding(character, holding)
end

local function watchCharacter(character: Model): ()
	character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") then
			refresh(character)
		end
	end)
	character.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("Tool") then
			refresh(character)
		end
	end)
	refresh(character)
end

local function watchPlayer(player: Player): ()
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
end

function HammerPoseController.start(): ()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

return HammerPoseController
