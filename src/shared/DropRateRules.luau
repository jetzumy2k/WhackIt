--!strict
--[[
	Pure rules for office boss buff drop chances (Config/DropRateConfig):
	validating admin input and saved settings, the Lucky window, and the chance
	for one roll. No Instances or services, so every path is unit-tested.
	Shared so the Admin panel can show the same Lucky window the server uses.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DropRateConfig = require(ReplicatedStorage.Config.DropRateConfig)
local Validate = require(script.Parent.Validate)

export type Settings = {
	NormalMin: number,
	NormalMax: number,
	LuckyMin: number,
	LuckyMax: number,
	LuckyEveryMinutes: number,
	LuckyLastsMinutes: number,
}

local DropRateRules = {}

function DropRateRules.default(): Settings
	local default = DropRateConfig.Default
	return {
		NormalMin = default.NormalMin,
		NormalMax = default.NormalMax,
		LuckyMin = default.LuckyMin,
		LuckyMax = default.LuckyMax,
		LuckyEveryMinutes = default.LuckyEveryMinutes,
		LuckyLastsMinutes = default.LuckyLastsMinutes,
	}
end

-- Validates admin input or saved settings. Returns them, or nil and a reason
-- the admin can read.
function DropRateRules.parse(raw: unknown): (Settings?, string?)
	if typeof(raw) ~= "table" then
		return nil, "bad request"
	end
	local data = raw :: { [string]: unknown }

	local normalMin = Validate.number(data.NormalMin, 0, 1)
	local normalMax = Validate.number(data.NormalMax, 0, 1)
	local luckyMin = Validate.number(data.LuckyMin, 0, 1)
	local luckyMax = Validate.number(data.LuckyMax, 0, 1)
	if normalMin == nil or normalMax == nil or luckyMin == nil or luckyMax == nil then
		return nil, "Chances must be numbers from 0 to 1 (0.30 = 30%)."
	end
	if normalMin > normalMax or luckyMin > luckyMax then
		return nil, "Each range's min can't be above its max."
	end

	local every = Validate.integer(
		data.LuckyEveryMinutes,
		DropRateConfig.MinEveryMinutes,
		DropRateConfig.MaxEveryMinutes
	)
	if every == nil then
		return nil,
			string.format(
				"Lucky window 'every' must be %d to %d minutes.",
				DropRateConfig.MinEveryMinutes,
				DropRateConfig.MaxEveryMinutes
			)
	end
	local lasts =
		Validate.integer(data.LuckyLastsMinutes, DropRateConfig.MinLastsMinutes, every - 1)
	if lasts == nil then
		return nil,
			string.format(
				"Lucky window must last %d to %d minutes (shorter than 'every').",
				DropRateConfig.MinLastsMinutes,
				every - 1
			)
	end

	return {
		NormalMin = normalMin,
		NormalMax = normalMax,
		LuckyMin = luckyMin,
		LuckyMax = luckyMax,
		LuckyEveryMinutes = every,
		LuckyLastsMinutes = lasts,
	},
		nil
end

-- Seconds into the current Lucky cycle, for a Unix time.
local function phase(settings: Settings, now: number): number
	return math.floor(now) % (settings.LuckyEveryMinutes * 60)
end

function DropRateRules.isLucky(settings: Settings, now: number): boolean
	return phase(settings, now) < settings.LuckyLastsMinutes * 60
end

-- Seconds until the Lucky window starts (outside it) or ends (inside it).
function DropRateRules.secondsUntilChange(settings: Settings, now: number): number
	local into = phase(settings, now)
	local lasts = settings.LuckyLastsMinutes * 60
	if into < lasts then
		return lasts - into
	end
	return settings.LuckyEveryMinutes * 60 - into
end

-- The drop chance for one roll in [0, 1): a point in the range in effect.
function DropRateRules.chanceFor(settings: Settings, now: number, roll: number): number
	local low, high = settings.NormalMin, settings.NormalMax
	if DropRateRules.isLucky(settings, now) then
		low, high = settings.LuckyMin, settings.LuckyMax
	end
	return low + (high - low) * math.clamp(roll, 0, 1)
end

return DropRateRules
