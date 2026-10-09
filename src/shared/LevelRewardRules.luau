--!strict
--[[
	Pure rules for level rewards (Config/LevelRewardConfig, docs/GAMEPLAY_RULES.md
	"Level rewards"): titles, the coins a level-up pays, what each level
	unlocks, and which trail / glow a player may use. The server grants and
	checks with these; the client shows the same reward track.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)
local LevelRewardConfig = require(ReplicatedStorage.Config.LevelRewardConfig)
local Validate = require(script.Parent.Validate)

export type CosmeticKind = "Trail" | "Glow"

-- The trail and glow a player picked ("" = the default look).
export type Cosmetics = { Trail: string, Glow: string }

local LevelRewardRules = {}

LevelRewardRules.KINDS = table.freeze({ "Trail", "Glow" } :: { CosmeticKind })

function LevelRewardRules.titleFor(level: number): string
	local name = LevelRewardConfig.Titles[1].Name
	for _, title in LevelRewardConfig.Titles do
		if level >= title.Level then
			name = title.Name
		end
	end
	return name
end

-- Coins for reaching every level after `fromLevel` up to `toLevel`.
function LevelRewardRules.coinsBetween(fromLevel: number, toLevel: number): number
	local low = math.max(1, math.floor(fromLevel))
	local high = math.min(GameConfig.MaxLevel, math.floor(toLevel))
	local total = 0
	for level = low + 1, high do
		total += LevelRewardConfig.CoinsPerLevel * level
	end
	return total
end

local function catalogue(kind: string): { LevelRewardConfig.Cosmetic }
	return if kind == "Trail" then LevelRewardConfig.Trails else LevelRewardConfig.Glows
end

function LevelRewardRules.cosmetic(kind: string, id: string): LevelRewardConfig.Cosmetic?
	return if kind == "Trail"
		then LevelRewardConfig.TrailsById[id]
		else LevelRewardConfig.GlowsById[id]
end

-- "" (the default look) is always allowed; others need their level.
function LevelRewardRules.isUnlocked(kind: string, id: string, level: number): boolean
	if id == "" then
		return true
	end
	local item = LevelRewardRules.cosmetic(kind, id)
	return item ~= nil and level >= item.Level
end

-- The pick that applies now: the saved one if still unlocked, else default.
function LevelRewardRules.effective(kind: string, id: string, level: number): string
	return if LevelRewardRules.isUnlocked(kind, id, level) then id else ""
end

-- A Level.SetCosmetic request: a known kind and "" or a known id.
function LevelRewardRules.parseChoice(rawKind: unknown, rawId: unknown): (CosmeticKind?, string?)
	local kind: CosmeticKind
	if rawKind == "Trail" then
		kind = "Trail"
	elseif rawKind == "Glow" then
		kind = "Glow"
	else
		return nil, nil
	end
	if rawId == "" then
		return kind, ""
	end
	local id = Validate.id(rawId, 32)
	if id == nil or LevelRewardRules.cosmetic(kind, id) == nil then
		return nil, nil
	end
	return kind, id
end

-- Saved picks: known ids only (unlocked or not: a lowered level only hides
-- them until the level is back).
function LevelRewardRules.sanitizeCosmetics(raw: unknown): Cosmetics
	local result: Cosmetics = { Trail = "", Glow = "" }
	if typeof(raw) ~= "table" then
		return result
	end
	local data = raw :: { [string]: unknown }
	local trail, glow = data.Trail, data.Glow
	if typeof(trail) == "string" and LevelRewardRules.cosmetic("Trail", trail) then
		result.Trail = trail
	end
	if typeof(glow) == "string" and LevelRewardRules.cosmetic("Glow", glow) then
		result.Glow = glow
	end
	return result
end

-- Everything reaching exactly `level` unlocks, as short lines for the UI.
function LevelRewardRules.rewardsAt(level: number): { string }
	local lines: { string } = {}
	for _, title in LevelRewardConfig.Titles do
		if title.Level == level and level > 1 then
			table.insert(lines, "Title: " .. title.Name)
		end
	end
	for _, list in { catalogue("Trail"), catalogue("Glow") } do
		for _, item in list do
			if item.Level == level then
				table.insert(lines, item.Name)
			end
		end
	end
	for _, hammer in HammerConfig.List do
		if hammer.MinLevel == level then
			table.insert(lines, hammer.DisplayName .. " in the Hammer Shop")
		end
	end
	if level == GameConfig.UpstairsMinLevel then
		table.insert(lines, "The Senior floor upstairs")
	end
	if level == GameConfig.MaxLevel then
		table.insert(lines, "A golden name tag")
	end
	return lines
end

-- The next level above `level` that unlocks something, and what (nil at max).
function LevelRewardRules.nextMilestone(level: number): (number?, { string })
	for candidate = math.floor(level) + 1, GameConfig.MaxLevel do
		local lines = LevelRewardRules.rewardsAt(candidate)
		if #lines > 0 then
			return candidate, lines
		end
	end
	return nil, {}
end

return LevelRewardRules
