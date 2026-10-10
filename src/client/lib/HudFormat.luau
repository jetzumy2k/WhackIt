--!strict
--[[
	Pure helpers for the HUD (visual overhaul V4a, Controllers/UIController):
	number formatting, the Stress Meter's mood face and colour.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StressRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StressRules"))

local HudFormat = {}

-- 1234567 -> "1,234,567" (whole numbers; negatives keep their sign).
function HudFormat.thousands(value: number): string
	local whole = math.floor(math.abs(value) + 0.5)
	local digits = tostring(whole)
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	grouped = grouped:gsub("^,", "")
	return if value < 0 then "-" .. grouped else grouped
end

local MOOD_ICONS: { [string]: string } = {
	Zen = "🧘",
	Relaxed = "😌",
	Neutral = "🙂",
	Stressed = "😟",
	Frazzled = "😫",
}

-- The face next to the Stress Meter, from the same bands as the character's mood.
function HudFormat.moodIcon(stress: number): string
	return MOOD_ICONS[StressRules.moodFor(stress)] or "🙂"
end

local CALM = Color3.fromRGB(90, 200, 130)
local TENSE = Color3.fromRGB(240, 185, 70)
local FRAZZLED = Color3.fromRGB(230, 80, 80)

-- The Stress Meter's fill: green when calm, amber in the middle, red when frazzled.
function HudFormat.stressColor(ratio: number): Color3
	local t = math.clamp(ratio, 0, 1)
	if t < 0.5 then
		return CALM:Lerp(TENSE, t / 0.5)
	end
	return TENSE:Lerp(FRAZZLED, (t - 0.5) / 0.5)
end

return HudFormat
