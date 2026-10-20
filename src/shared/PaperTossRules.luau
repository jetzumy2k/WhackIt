--!strict
--[[
	Pure rules for Paper Toss Showdown (docs/PAPER_TOSS.md): rounds, judging
	a throw, the CPU's throws, the score and the daily rewards. The server
	decides with these (Services/PaperTossService) using its own Random.

	A throw is two numbers in 0..1: where the aim marker stopped and where
	the power bar stopped. The ideal aim is the middle, pushed against the
	breeze; the ideal power depends on how far the bin is. The distance
	from the ideal throw decides Swish / In / Rim / Miss.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PaperTossConfig = require(ReplicatedStorage.Config.PaperTossConfig)

export type Round = { Distance: number, Wind: number }

export type Throw = { Aim: number, Power: number, Result: string, Points: number }

export type Game = {
	Opponent: number,
	Rounds: { Round },
	Round: number, -- the round being played (1-based); > Rounds = over
	You: number, -- points
	Cpu: number,
}

export type Record = {
	DayKey: string,
	DayWins: number,
	DayFirst: { string },
	Cleared: number, -- highest opponent beaten (0..3)
	Best: number, -- best score in one match
	TotalWins: number,
}

export type Reward = { Coins: number, Xp: number, Supply: boolean }

local PaperTossRules = {}

local MAX_COUNT = 2 ^ 40

-- A new match against opponent `index`: random distances and breezes.
function PaperTossRules.newGame(index: number, random: Random): Game
	local rounds: { Round } = {}
	for round = 1, PaperTossConfig.Rounds do
		-- Farther bins later in the match.
		local distance = math.clamp(math.floor((round - 1) / 2) + random:NextInteger(0, 1), 1, 3)
		local wind = math.floor((random:NextNumber() * 2 - 1) * 10 + 0.5) / 10
		table.insert(rounds, { Distance = distance, Wind = wind })
	end
	return { Opponent = index, Rounds = rounds, Round = 1, You = 0, Cpu = 0 }
end

function PaperTossRules.ideal(round: Round): (number, number)
	local aim = 0.5 - round.Wind * PaperTossConfig.WindAim
	local power = PaperTossConfig.IdealPower[round.Distance] or PaperTossConfig.IdealPower[2]
	return aim, power
end

-- Judges a throw on `round`.
function PaperTossRules.judge(round: Round, aim: number, power: number): Throw
	local idealAim, idealPower = PaperTossRules.ideal(round)
	local miss = math.sqrt((aim - idealAim) ^ 2 + (power - idealPower) ^ 2)
	local result = if miss <= PaperTossConfig.SwishWithin
		then "Swish"
		elseif miss <= PaperTossConfig.InWithin then "In"
		elseif miss <= PaperTossConfig.RimWithin then "Rim"
		else "Miss"
	return { Aim = aim, Power = power, Result = result, Points = PaperTossConfig.Points[result] }
end

-- A normally distributed number (mean 0, deviation 1).
local function gaussian(random: Random): number
	local u = math.max(random:NextNumber(), 1e-9)
	local v = random:NextNumber()
	return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v)
end

-- The CPU coworker's throw on `round`.
function PaperTossRules.cpuThrow(round: Round, spread: number, random: Random): Throw
	local idealAim, idealPower = PaperTossRules.ideal(round)
	local aim = math.clamp(idealAim + gaussian(random) * spread, 0, 1)
	local power = math.clamp(idealPower + gaussian(random) * spread, 0, 1)
	return PaperTossRules.judge(round, aim, power)
end

function PaperTossRules.isMeter(value: unknown): boolean
	return typeof(value) == "number" and value == value and value >= 0 and value <= 1
end

-- Plays the current round (in place): your throw, then the CPU's. Returns both.
function PaperTossRules.play(
	match: Game,
	aim: number,
	power: number,
	random: Random
): (Throw?, Throw?)
	local round = match.Rounds[match.Round]
	local opponent = PaperTossConfig.Opponents[match.Opponent]
	if round == nil or opponent == nil then
		return nil, nil
	end
	local mine = PaperTossRules.judge(round, aim, power)
	local theirs = PaperTossRules.cpuThrow(round, opponent.Spread, random)
	match.You += mine.Points
	match.Cpu += theirs.Points
	match.Round += 1
	return mine, theirs
end

function PaperTossRules.isOver(match: Game): boolean
	return match.Round > #match.Rounds
end

-- "Won", "Lost" or "Draw" once over.
function PaperTossRules.outcome(match: Game): string
	if match.You > match.Cpu then
		return "Won"
	elseif match.You < match.Cpu then
		return "Lost"
	end
	return "Draw"
end

-- Records -------------------------------------------------------------------------------

function PaperTossRules.defaultRecord(): Record
	return { DayKey = "", DayWins = 0, DayFirst = {}, Cleared = 0, Best = 0, TotalWins = 0 }
end

local function count(value: unknown, max: number): number
	if typeof(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(math.floor(value :: number), 0, max)
end

function PaperTossRules.opponentIndex(id: string): number?
	for index, opponent in PaperTossConfig.Opponents do
		if opponent.Id == id then
			return index
		end
	end
	return nil
end

function PaperTossRules.sanitizeRecord(raw: unknown): Record
	local record = PaperTossRules.defaultRecord()
	if typeof(raw) ~= "table" then
		return record
	end
	local data = raw :: { [string]: unknown }
	record.DayKey = if typeof(data.DayKey) == "string" and #(data.DayKey :: string) <= 16
		then data.DayKey :: string
		else ""
	record.DayWins = count(data.DayWins, PaperTossConfig.DailyRewardedWins)
	if typeof(data.DayFirst) == "table" then
		for _, id in data.DayFirst :: { unknown } do
			if
				typeof(id) == "string"
				and PaperTossRules.opponentIndex(id)
				and not table.find(record.DayFirst, id)
			then
				table.insert(record.DayFirst, id)
			end
		end
	end
	record.Cleared = count(data.Cleared, #PaperTossConfig.Opponents)
	record.Best = count(data.Best, PaperTossConfig.Rounds * PaperTossConfig.Points.Swish)
	record.TotalWins = count(data.TotalWins, MAX_COUNT)
	return record
end

function PaperTossRules.canPlay(record: Record, index: number): boolean
	return index >= 1 and index <= #PaperTossConfig.Opponents and index <= record.Cleared + 1
end

--[[
	A finished match (in place): best score, and for a win the next opponent
	and today's reward. Nil = no reward (not a win, or today's wins used up).
]]
function PaperTossRules.finish(record: Record, match: Game, dayKey: string): Reward?
	if record.DayKey ~= dayKey then
		record.DayKey = dayKey
		record.DayWins = 0
		record.DayFirst = {}
	end
	record.Best = math.max(record.Best, match.You)
	if PaperTossRules.outcome(match) ~= "Won" then
		return nil
	end
	local opponent = PaperTossConfig.Opponents[match.Opponent]
	record.Cleared = math.max(record.Cleared, match.Opponent)
	record.TotalWins = math.min(record.TotalWins + 1, MAX_COUNT)
	if opponent == nil or record.DayWins >= PaperTossConfig.DailyRewardedWins then
		return nil
	end
	record.DayWins += 1
	local first = not table.find(record.DayFirst, opponent.Id)
	if first then
		table.insert(record.DayFirst, opponent.Id)
	end
	local times = if first then PaperTossConfig.FirstWinBonus else 1
	return {
		Coins = opponent.Coins * times,
		Xp = opponent.Xp * times,
		Supply = first and match.Opponent == #PaperTossConfig.Opponents,
	}
end

return PaperTossRules
