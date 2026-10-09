--!strict
--[[
	The "🎉 LEVEL UP!" card (2026-10-08, docs/GAMEPLAY_RULES.md "Level
	bonuses"). Display only: Player Level comes from the server (the Level
	attribute, from saved XP) and so do the bonuses it gives (BuffService).

	Several levels in a row (one big reward, or rewards close together) make
	one card with the total, e.g. "Level 10 -> Level 13 / +9 Base Damage
	+0.15% Crit": changes are gathered for a moment before the card shows.
	Joining, respawning, or a level going down (an admin) shows nothing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attributes"))
local LevelRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LevelRules"))

local AnnouncementController = require(script.Parent.AnnouncementController)

local LevelUpController = {}

-- How long level changes are gathered into one card.
local GATHER_SECONDS = 1.2
local CARD_SECONDS = 5
local ACCENT = Color3.fromRGB(255, 214, 120)

-- "Level 10 -> Level 13", "+9 Base Damage   +0.15% Crit"
function LevelUpController.cardText(fromLevel: number, toLevel: number): (string, string)
	local damage, crit = LevelRules.gains(fromLevel, toLevel)
	return string.format("Level %d → Level %d", fromLevel, toLevel),
		string.format("+%d Base Damage   +%.2f%% Crit", damage, crit * 100)
end

function LevelUpController.start(): ()
	local player = Players.LocalPlayer
	local last: number? = nil
	local gatheringFrom: number? = nil
	local token = 0

	local function onLevel(): ()
		local level = player:GetAttribute(Attributes.Level)
		if typeof(level) ~= "number" then
			return
		end
		local previous = last
		last = level
		if previous == nil then
			return -- first value after joining: not a level-up
		end
		if level < previous then
			gatheringFrom = nil -- lowered by an admin: no card
			token += 1
			return
		end
		if level == previous then
			return
		end
		gatheringFrom = gatheringFrom or previous
		token += 1
		local mine = token
		task.delay(GATHER_SECONDS, function()
			local from = gatheringFrom
			if token ~= mine or from == nil or last == nil then
				return
			end
			gatheringFrom = nil
			local body, detail = LevelUpController.cardText(from, last :: number)
			AnnouncementController.show({
				Title = "🎉 LEVEL UP!",
				Body = body,
				Detail = detail,
				Accent = ACCENT,
				Seconds = CARD_SECONDS,
			})
		end)
	end

	player:GetAttributeChangedSignal(Attributes.Level):Connect(onLevel)
	onLevel()
end

return LevelUpController
