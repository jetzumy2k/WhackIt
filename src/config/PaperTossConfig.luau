--!strict
--[[
	Paper Toss Showdown (docs/PAPER_TOSS.md, recreation games 3/3, owner
	choice). Office basketball against a CPU coworker: five rounds, each
	with a bin at some distance and a desk-fan breeze; you stop an aim
	marker, then a power bar; the closer to the ideal throw, the better.
]]

export type Opponent = {
	Id: string,
	Name: string,
	Title: string,
	Icon: string,
	-- How far the CPU's throws stray from the ideal one (standard deviation).
	Spread: number,
	Coins: number,
	Xp: number,
}

local PaperTossConfig = table.freeze({
	Rounds = 5,
	-- Bin distances (1 near, 2 mid, 3 far) and the ideal power for each.
	IdealPower = table.freeze({ 0.35, 0.55, 0.75 }),
	-- A breeze of 1 (full, to the right) moves the ideal aim this much left.
	WindAim = 0.25,
	-- Throw error (distance from the ideal aim/power) -> result.
	SwishWithin = 0.05,
	InWithin = 0.11,
	RimWithin = 0.15,
	Points = table.freeze({ Swish = 3, In = 2, Rim = 0, Miss = 0 }),
	-- Seconds the server waits between two throws (no spamming).
	MinThrowSeconds = 1.2,
	-- How fast the meters sweep (seconds for one way across).
	AimSweepSeconds = 0.9,
	PowerSweepSeconds = 0.8,

	Opponents = table.freeze({
		table.freeze({
			Id = "intern_izzy",
			Name = "Izzy",
			Title = "Intern",
			Icon = "🧑‍💼",
			Spread = 0.09,
			Coins = 40,
			Xp = 120,
		}),
		table.freeze({
			Id = "manager_max",
			Name = "Max",
			Title = "Manager",
			Icon = "👔",
			Spread = 0.065,
			Coins = 80,
			Xp = 260,
		}),
		table.freeze({
			Id = "ceo_cora",
			Name = "Cora",
			Title = "CEO",
			Icon = "👑",
			Spread = 0.045,
			Coins = 150,
			Xp = 500,
		}),
	} :: { Opponent }),

	-- Up to this many rewarded wins a day (UTC); the first win against each
	-- opponent each day pays double; the first CEO win each day also gives
	-- an office supply.
	DailyRewardedWins = 10,
	FirstWinBonus = 2,
	CeoSupply = table.freeze({
		{ Item = "desk_fan", Weight = 4 },
		{ Item = "mini_fridge", Weight = 3 },
		{ Item = "snack_machine", Weight = 2 },
		{ Item = "trophy_gold", Weight = 1 },
	}),
})

return PaperTossConfig
