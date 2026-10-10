--!strict
--[[
	Pure rules for the Lucky Capsule Machine (docs/CAPSULE.md): who may spin,
	picking a prize from a roll, the shown odds and the saved daily state.
	The server rolls (Services/CapsuleService); the client shows the odds and
	the prize it's told about.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CapsuleConfig = require(ReplicatedStorage.Config.CapsuleConfig)

export type State = {
	DayKey: string,
	Spins: number, -- spins today
	TotalSpins: number,
}

export type Odds = { Prize: CapsuleConfig.Prize, Percent: number }

local CapsuleRules = {}

local MAX_COUNT = 2 ^ 40

function CapsuleRules.defaultState(): State
	return { DayKey = "", Spins = 0, TotalSpins = 0 }
end

local function count(value: unknown, max: number): number
	if typeof(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(math.floor(value :: number), 0, max)
end

function CapsuleRules.sanitizeState(raw: unknown): State
	local state = CapsuleRules.defaultState()
	if typeof(raw) ~= "table" then
		return state
	end
	local data = raw :: { [string]: unknown }
	state.DayKey = if typeof(data.DayKey) == "string" and #(data.DayKey :: string) <= 16
		then data.DayKey :: string
		else ""
	state.Spins = count(data.Spins, CapsuleConfig.DailySpins)
	state.TotalSpins = count(data.TotalSpins, MAX_COUNT)
	return state
end

function CapsuleRules.spinsLeft(state: State, dayKey: string): number
	if state.DayKey ~= dayKey then
		return CapsuleConfig.DailySpins
	end
	return math.max(0, CapsuleConfig.DailySpins - state.Spins)
end

-- Is the next spin today the guaranteed lucky one (the last of the day)?
function CapsuleRules.nextIsLucky(state: State, dayKey: string): boolean
	return CapsuleRules.spinsLeft(state, dayKey) == 1
end

function CapsuleRules.canSpin(
	level: number,
	coins: number,
	state: State,
	dayKey: string
): (boolean, string?)
	if level < CapsuleConfig.MinLevel then
		return false,
			string.format("Reach Level %d to use the Capsule Machine.", CapsuleConfig.MinLevel)
	end
	if CapsuleRules.spinsLeft(state, dayKey) <= 0 then
		return false, "No spins left today. Come back tomorrow!"
	end
	if coins < CapsuleConfig.Cost then
		return false, string.format("A spin costs %d coins.", CapsuleConfig.Cost)
	end
	return true, nil
end

-- Counts a spin (in place), starting a new day when it changed.
function CapsuleRules.noteSpin(state: State, dayKey: string): ()
	if state.DayKey ~= dayKey then
		state.DayKey = dayKey
		state.Spins = 0
	end
	state.Spins += 1
	state.TotalSpins = math.min(state.TotalSpins + 1, MAX_COUNT)
end

-- The prizes a spin can give (only the lucky tiers on the lucky spin).
function CapsuleRules.pool(lucky: boolean): { CapsuleConfig.Prize }
	local pool: { CapsuleConfig.Prize } = {}
	for _, prize in CapsuleConfig.Prizes do
		if not lucky or table.find(CapsuleConfig.LuckyTiers, prize.Tier) then
			table.insert(pool, prize)
		end
	end
	return pool
end

-- The prize for `roll` in [0, 1).
function CapsuleRules.pick(roll: number, lucky: boolean): CapsuleConfig.Prize
	local pool = CapsuleRules.pool(lucky)
	local total = 0
	for _, prize in pool do
		total += prize.Weight
	end
	local target = math.clamp(roll, 0, 0.999999) * total
	for _, prize in pool do
		target -= prize.Weight
		if target < 0 then
			return prize
		end
	end
	return pool[#pool]
end

-- Each prize's chance in percent (shown before spinning), normal or lucky spin.
function CapsuleRules.odds(lucky: boolean): { Odds }
	local pool = CapsuleRules.pool(lucky)
	local total = 0
	for _, prize in pool do
		total += prize.Weight
	end
	local list: { Odds } = {}
	for _, prize in pool do
		table.insert(list, { Prize = prize, Percent = prize.Weight / total * 100 })
	end
	return list
end

return CapsuleRules
