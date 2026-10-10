--!strict
--[[
	Pure rules for the Pet Arena (docs/PET_ARENA.md): a pet's battle stats,
	resolving a round, the CPU trainers' choices and the daily rewards. The
	server decides with these (Services/PetArenaService) using its own
	Random; the client only shows what the server sends.

	A round: both sides pick a move at the same time. Guards hold for the
	whole round; then the faster pet acts first. A Boop takes Pep (more after
	a Charge, a lucky boop x1.5, a guarding target takes 40 %). A pet at 0
	Pep is dizzy and loses. After MaxRounds the pet with the bigger share of
	its Pep left wins.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetArenaConfig = require(ReplicatedStorage.Config.PetArenaConfig)
local PetConfig = require(ReplicatedStorage.Config.PetConfig)

export type Move = PetArenaConfig.Move
export type Side = string -- "A" | "B"

export type Stats = { MaxPep: number, Power: number, Speed: number, Crit: number }

export type Fighter = {
	Name: string,
	Species: string,
	Rarity: string,
	Stats: Stats,
	Pep: number,
	Charged: boolean,
	LastMove: string, -- "" before the first round
	Guards: number, -- guards in a row (the clever CPU notices)
}

export type Battle = {
	A: Fighter,
	B: Fighter,
	Round: number,
	Winner: string, -- "" while it goes on, "A", "B" or "Draw"
}

export type Event = {
	Side: Side,
	Move: Move,
	Damage: number,
	Lucky: boolean,
	Guarded: boolean,
}

export type Record = {
	DayKey: string,
	DayWins: number, -- rewarded CPU wins today
	DayFirst: { string }, -- trainers beaten today (first win pays more)
	Cleared: number, -- highest trainer index ever beaten (0 = none)
	PlayerDay: number, -- rewarded player battles today
	Opponents: { [string]: number }, -- today's rewarded battles per opponent UserId
	TotalWins: number,
}

local PetArenaRules = {}

local MAX_COUNT = 2 ^ 40

local function count(value: unknown, max: number): number
	if typeof(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(math.floor(value :: number), 0, max)
end

-- Stats -------------------------------------------------------------------------------

function PetArenaRules.statsFor(
	speciesId: string,
	rarity: string,
	buffs: { PetConfig.Buff },
	power: number?
): Stats
	local base = PetArenaConfig.Base[rarity] or PetArenaConfig.Base.Common
	local damage, xp, crit = 0, 0, 0
	for _, buff in buffs do
		if buff.Kind == "Damage" then
			damage += buff.Percent
		elseif buff.Kind == "Xp" then
			xp += buff.Percent
		elseif buff.Kind == "CritDamage" then
			crit += buff.Percent
		end
	end
	local species = PetConfig.ById[speciesId]
	local speedBonus = if species then PetArenaConfig.SpeedByMovement[species.Movement] or 0 else 0
	local scale = power or 1
	return {
		MaxPep = math.floor(base.Pep * (1 + xp * PetArenaConfig.PepPerXp) * scale + 0.5),
		Power = base.Power * (1 + damage * PetArenaConfig.PowerPerDamage) * scale,
		Speed = base.Speed + speedBonus,
		Crit = math.min(
			PetArenaConfig.MaxCrit,
			PetArenaConfig.BaseCrit + crit * PetArenaConfig.CritPerCritDamage
		),
	}
end

function PetArenaRules.fighter(
	name: string,
	speciesId: string,
	rarity: string,
	buffs: { PetConfig.Buff },
	power: number?
): Fighter
	local stats = PetArenaRules.statsFor(speciesId, rarity, buffs, power)
	return {
		Name = name,
		Species = speciesId,
		Rarity = rarity,
		Stats = stats,
		Pep = stats.MaxPep,
		Charged = false,
		LastMove = "",
		Guards = 0,
	}
end

-- A trainer's fighter: their species' own buffs, scaled by their Power.
function PetArenaRules.trainerFighter(trainer: PetArenaConfig.Trainer): Fighter
	local species = PetConfig.ById[trainer.Species]
	local buffs = if species then species.Buffs else {}
	return PetArenaRules.fighter(
		trainer.Title .. " " .. trainer.Name,
		trainer.Species,
		trainer.Rarity,
		buffs,
		trainer.Power
	)
end

function PetArenaRules.newBattle(a: Fighter, b: Fighter): Battle
	return { A = a, B = b, Round = 0, Winner = "" }
end

function PetArenaRules.isMove(value: unknown): boolean
	return typeof(value) == "string" and table.find(PetArenaConfig.Moves, value :: any) ~= nil
end

-- Rounds ------------------------------------------------------------------------------

local function other(side: Side): Side
	return if side == "A" then "B" else "A"
end

local function fighterOf(battle: Battle, side: Side): Fighter
	return if side == "A" then battle.A else battle.B
end

--[[
	Plays one round (in place) and returns what happened, in order.
	`random:NextNumber()` decides boop spread, lucky boops and speed ties.
]]
function PetArenaRules.resolve(battle: Battle, moveA: Move, moveB: Move, random: Random): { Event }
	local events: { Event } = {}
	if battle.Winner ~= "" then
		return events
	end
	local moves: { [Side]: Move } = { A = moveA, B = moveB }
	local order: { Side } = { "A", "B" }
	local speedA, speedB = battle.A.Stats.Speed, battle.B.Stats.Speed
	if speedB > speedA or (speedB == speedA and random:NextNumber() < 0.5) then
		order = { "B", "A" }
	end
	for _, side in order do
		local me = fighterOf(battle, side)
		local target = fighterOf(battle, other(side))
		local move = moves[side]
		if me.Pep <= 0 then
			continue -- dizzy pets don't act
		end
		local event: Event =
			{ Side = side, Move = move, Damage = 0, Lucky = false, Guarded = false }
		if move == "Boop" then
			local spread = 1 + (random:NextNumber() * 2 - 1) * PetArenaConfig.BoopSpread
			local damage = me.Stats.Power * spread
			if me.Charged then
				damage *= PetArenaConfig.ChargeMultiplier
			end
			if random:NextNumber() < me.Stats.Crit then
				damage *= PetArenaConfig.CritMultiplier
				event.Lucky = true
			end
			if moves[other(side)] == "Guard" then
				damage *= PetArenaConfig.GuardTaken
				event.Guarded = true
			end
			local dealt = math.max(1, math.floor(damage + 0.5))
			target.Pep = math.max(0, target.Pep - dealt)
			event.Damage = dealt
			me.Charged = false
		elseif move == "Charge" then
			me.Charged = true
		end
		table.insert(events, event)
	end
	for _, side in { "A", "B" } :: { Side } do
		local me = fighterOf(battle, side)
		me.LastMove = moves[side]
		me.Guards = if moves[side] == "Guard" then me.Guards + 1 else 0
	end
	battle.Round += 1
	local aDown, bDown = battle.A.Pep <= 0, battle.B.Pep <= 0
	if aDown and bDown then
		battle.Winner = "Draw"
	elseif aDown then
		battle.Winner = "B"
	elseif bDown then
		battle.Winner = "A"
	elseif battle.Round >= PetArenaConfig.MaxRounds then
		local shareA = battle.A.Pep / battle.A.Stats.MaxPep
		local shareB = battle.B.Pep / battle.B.Stats.MaxPep
		battle.Winner = if shareA > shareB then "A" elseif shareB > shareA then "B" else "Draw"
	end
	return events
end

-- CPU ------------------------------------------------------------------------------------

local function weighted(random: Random, boop: number, charge: number, guard: number): Move
	local roll = random:NextNumber() * (boop + charge + guard)
	if roll < boop then
		return "Boop"
	elseif roll < boop + charge then
		return "Charge"
	end
	return "Guard"
end

-- What a CPU trainer's pet (on `side`) does this round.
function PetArenaRules.cpuMove(battle: Battle, side: Side, style: string, random: Random): Move
	local me = fighterOf(battle, side)
	local them = fighterOf(battle, other(side))
	if style == "Bold" then
		-- Charges up, then boops; never guards.
		if me.Charged then
			return "Boop"
		end
		return weighted(random, 55, 45, 0)
	elseif style == "Careful" then
		if me.Pep < me.Stats.MaxPep * 0.4 then
			return weighted(random, 50, 10, 40)
		end
		return weighted(random, 70, 15, 15)
	elseif style == "Clever" then
		if them.Charged then
			return "Guard" -- a charged boop is coming
		end
		if me.Charged then
			return "Boop"
		end
		if them.Guards >= 2 then
			return "Charge" -- they keep guarding: power up
		end
		return weighted(random, 60, 25, 15)
	end
	return weighted(random, 1, 1, 1)
end

-- Rewards ----------------------------------------------------------------------------------

function PetArenaRules.defaultRecord(): Record
	return {
		DayKey = "",
		DayWins = 0,
		DayFirst = {},
		Cleared = 0,
		PlayerDay = 0,
		Opponents = {},
		TotalWins = 0,
	}
end

function PetArenaRules.sanitizeRecord(raw: unknown): Record
	local record = PetArenaRules.defaultRecord()
	if typeof(raw) ~= "table" then
		return record
	end
	local data = raw :: { [string]: unknown }
	record.DayKey = if typeof(data.DayKey) == "string" and #(data.DayKey :: string) <= 16
		then data.DayKey :: string
		else ""
	record.DayWins = count(data.DayWins, PetArenaConfig.DailyRewardedWins)
	if typeof(data.DayFirst) == "table" then
		for _, id in data.DayFirst :: { unknown } do
			if
				typeof(id) == "string"
				and PetArenaRules.trainerIndex(id)
				and not table.find(record.DayFirst, id)
			then
				table.insert(record.DayFirst, id)
			end
		end
	end
	record.Cleared = count(data.Cleared, #PetArenaConfig.Trainers)
	record.PlayerDay = count(data.PlayerDay, PetArenaConfig.DailyPlayerBattles)
	if typeof(data.Opponents) == "table" then
		for key, value in data.Opponents :: { [unknown]: unknown } do
			if typeof(key) == "string" and #key <= 24 then
				record.Opponents[key] = count(value, PetArenaConfig.MaxPerOpponent)
			end
		end
	end
	record.TotalWins = count(data.TotalWins, MAX_COUNT)
	return record
end

-- Starts a new day's counters (in place) when the UTC day changed.
function PetArenaRules.rollDay(record: Record, dayKey: string): ()
	if record.DayKey ~= dayKey then
		record.DayKey = dayKey
		record.DayWins = 0
		record.DayFirst = {}
		record.PlayerDay = 0
		record.Opponents = {}
	end
end

function PetArenaRules.trainerIndex(id: string): number?
	for index, trainer in PetArenaConfig.Trainers do
		if trainer.Id == id then
			return index
		end
	end
	return nil
end

-- May this player fight trainer `index`? (Beat the one before first.)
function PetArenaRules.canFight(record: Record, index: number): boolean
	return index >= 1 and index <= #PetArenaConfig.Trainers and index <= record.Cleared + 1
end

export type Reward = { Coins: number, Xp: number, Supply: boolean, First: boolean }

--[[
	A CPU win against trainer `index` (in place): unlocks the next trainer
	and pays if today's rewarded wins aren't used up. Nil = no reward today.
]]
function PetArenaRules.cpuWin(record: Record, index: number, dayKey: string): Reward?
	PetArenaRules.rollDay(record, dayKey)
	local trainer = PetArenaConfig.Trainers[index]
	if trainer == nil then
		return nil
	end
	record.Cleared = math.max(record.Cleared, index)
	record.TotalWins = math.min(record.TotalWins + 1, MAX_COUNT)
	if record.DayWins >= PetArenaConfig.DailyRewardedWins then
		return nil
	end
	record.DayWins += 1
	local first = not table.find(record.DayFirst, trainer.Id)
	if first then
		table.insert(record.DayFirst, trainer.Id)
	end
	local times = if first then PetArenaConfig.FirstWinBonus else 1
	return {
		Coins = trainer.Coins * times,
		Xp = trainer.Xp * times,
		Supply = first and index == #PetArenaConfig.Trainers,
		First = first,
	}
end

-- A finished player battle (in place). Nil = no reward (daily or per-opponent cap).
function PetArenaRules.playerResult(
	record: Record,
	opponentId: number,
	won: boolean,
	dayKey: string
): Reward?
	PetArenaRules.rollDay(record, dayKey)
	if won then
		record.TotalWins = math.min(record.TotalWins + 1, MAX_COUNT)
	end
	local key = tostring(opponentId)
	if
		record.PlayerDay >= PetArenaConfig.DailyPlayerBattles
		or (record.Opponents[key] or 0) >= PetArenaConfig.MaxPerOpponent
	then
		return nil
	end
	record.PlayerDay += 1
	record.Opponents[key] = (record.Opponents[key] or 0) + 1
	local pay = if won then PetArenaConfig.PlayerWin else PetArenaConfig.PlayerLose
	return { Coins = pay.Coins, Xp = pay.Xp, Supply = false, First = false }
end

return PetArenaRules
