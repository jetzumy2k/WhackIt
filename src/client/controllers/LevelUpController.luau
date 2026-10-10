--!strict
--[[
	The "🎉 LEVEL UP!" card (docs/GAMEPLAY_RULES.md "Level bonuses" and
	"Level rewards"). Display only: Player Level comes from the server (the
	Level attribute, from saved XP), and so do the bonuses (BuffService) and
	the level-up coins (SessionService, announced on Level.LevelUp).

	Several levels in a row (one big reward, or rewards close together) make
	one card with the total, e.g. "Level 10 → Level 13 / +3 Base Damage
	+0.15% Crit   +780 coins / Unlocked: Mint Trail": changes are gathered
	for a moment before the card shows. With nothing unlocked, the card says
	what the next reward is. Joining, respawning, or a level going down (an
	admin) shows nothing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attributes"))
local LevelRewardRules =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LevelRewardRules"))
local LevelRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LevelRules"))

local AnnouncementController = require(script.Parent.AnnouncementController)

local LevelUpController = {}

-- How long level changes are gathered into one card.
local GATHER_SECONDS = 1.2
local CARD_SECONDS = 6
local ACCENT = Color3.fromRGB(255, 214, 120)

-- "Level 10 → Level 13" and the detail lines: bonuses and coins, then what
-- was unlocked (or the next reward).
function LevelUpController.cardText(
	fromLevel: number,
	toLevel: number,
	coins: number
): (string, string)
	local damage, crit = LevelRules.gains(fromLevel, toLevel)
	local gains = string.format("+%d Base Damage   +%.2f%% Crit", damage, crit * 100)
	if coins > 0 then
		gains ..= string.format("   +%d coins", coins)
	end
	local unlocked: { string } = {}
	for level = fromLevel + 1, toLevel do
		for _, line in LevelRewardRules.rewardsAt(level) do
			table.insert(unlocked, line)
		end
	end
	local after: string
	if #unlocked > 0 then
		after = "Unlocked: " .. table.concat(unlocked, ", ")
	else
		local nextLevel, nextLines = LevelRewardRules.nextMilestone(toLevel)
		after = if nextLevel
			then string.format("Next at Lv %d: %s", nextLevel, table.concat(nextLines, ", "))
			else "👑 Max level!"
	end
	return string.format("Level %d → Level %d", fromLevel, toLevel), gains .. "\n" .. after
end

function LevelUpController.start(): ()
	local player = Players.LocalPlayer
	local last: number? = nil
	local gatheringFrom: number? = nil
	local coinsGathered = 0
	local token = 0

	-- Coins paid for new levels (only levels never rewarded before pay).
	local levelUpRemote =
		ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Level"):WaitForChild("LevelUp")
	assert(levelUpRemote:IsA("RemoteEvent"), "Level.LevelUp must be a RemoteEvent")
	levelUpRemote.OnClientEvent:Connect(function(payload: unknown)
		if typeof(payload) == "table" then
			local coins = (payload :: { [string]: unknown }).Coins
			if typeof(coins) == "number" and coins > 0 then
				coinsGathered += coins
			end
		end
	end)

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
			local coins = coinsGathered
			coinsGathered = 0
			local body, detail = LevelUpController.cardText(from, last :: number, coins)
			AnnouncementController.show({
				Title = if LevelRules.isMax(last :: number)
					then "👑 MAX LEVEL!"
					else "🎉 LEVEL UP!",
				Body = body,
				Detail = detail,
				Accent = ACCENT,
				Celebrate = true,
				Seconds = CARD_SECONDS,
			})
		end)
	end

	player:GetAttributeChangedSignal(Attributes.Level):Connect(onLevel)
	onLevel()
end

return LevelUpController
