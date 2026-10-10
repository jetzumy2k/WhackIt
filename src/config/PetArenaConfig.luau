--!strict
--[[
	The Pet Arena (docs/PET_ARENA.md, recreation games 2026-10-10, owner
	choice "Pet Arena, turn-based"). Cartoon pet battles at the Recreation
	Center: nobody gets hurt, the pet that runs out of Pep just gets dizzy.

	A pet's battle stats come from its rarity and the buffs it already has
	(Shared/PetArenaRules.statsFor): Damage buffs make its Boop stronger, XP
	buffs give it more Pep, Crit Damage buffs make lucky boops likelier, and
	how it moves sets its speed (who goes first).
]]

export type Move = string -- "Boop" | "Charge" | "Guard"

export type Trainer = {
	Id: string,
	Name: string,
	Title: string,
	Species: string, -- the trainer's pet (Config/PetConfig)
	Rarity: string,
	Power: number, -- multiplies the pet's stats
	Style: string, -- how the CPU picks moves: "Random" | "Careful" | "Bold" | "Clever"
	Coins: number,
	Xp: number,
}

local PetArenaConfig = table.freeze({
	Moves = table.freeze({ "Boop", "Charge", "Guard" } :: { Move }),
	MoveText = table.freeze({
		Boop = "💥 Boop",
		Charge = "⚡ Charge",
		Guard = "🛡️ Guard",
	}),

	-- Base stats by rarity (Pep = how much booping a pet can take).
	Base = table.freeze({
		Common = table.freeze({ Pep = 100, Power = 12, Speed = 10 }),
		Rare = table.freeze({ Pep = 115, Power = 14, Speed = 12 }),
		Mythical = table.freeze({ Pep = 130, Power = 16, Speed = 14 }),
	}),
	-- How far a pet's own buffs move its stats (per buff percent).
	PowerPerDamage = 0.03, -- +3 % Power per 1 % Damage buff
	PepPerXp = 0.02, -- +2 % Pep per 1 % XP buff
	CritPerCritDamage = 0.01, -- +1 % lucky-boop chance per 1 % Crit Damage buff
	BaseCrit = 0.05,
	MaxCrit = 0.35,
	CritMultiplier = 1.5,
	-- Speed by how the pet moves.
	SpeedByMovement = table.freeze({ Flying = 3, Hopping = 2, Ground = 0, Crawling = -1 }),

	-- Moves.
	BoopSpread = 0.1, -- boops land for 90-110 % of Power
	ChargeMultiplier = 2, -- the next Boop after a Charge
	GuardTaken = 0.4, -- a guarding pet takes 40 % of a boop
	-- A battle that lasts this many rounds ends on Pep left (most wins).
	MaxRounds = 20,

	-- Turn time (seconds) in player battles; a pet whose trainer doesn't
	-- choose in time Boops.
	TurnSeconds = 15,
	-- Seconds a challenge waits for an answer.
	ChallengeSeconds = 30,

	-- The CPU ladder: beat one to unlock the next (saved).
	Trainers = table.freeze({
		table.freeze({
			Id = "intern_ivy",
			Name = "Ivy",
			Title = "Intern",
			Species = "hamster",
			Rarity = "Common",
			Power = 0.85,
			Style = "Random",
			Coins = 40,
			Xp = 120,
		}),
		table.freeze({
			Id = "barista_ben",
			Name = "Ben",
			Title = "Barista",
			Species = "frog",
			Rarity = "Common",
			Power = 1.0,
			Style = "Careful",
			Coins = 70,
			Xp = 220,
		}),
		table.freeze({
			Id = "it_ian",
			Name = "Ian",
			Title = "IT Support",
			Species = "owl",
			Rarity = "Rare",
			Power = 1.05,
			Style = "Bold",
			Coins = 110,
			Xp = 360,
		}),
		table.freeze({
			Id = "manager_mia",
			Name = "Mia",
			Title = "Manager",
			Species = "tiger",
			Rarity = "Rare",
			Power = 1.15,
			Style = "Clever",
			Coins = 160,
			Xp = 520,
		}),
		table.freeze({
			Id = "director_dee",
			Name = "Dee",
			Title = "Director",
			Species = "celestial_lion",
			Rarity = "Mythical",
			Power = 1.15,
			Style = "Clever",
			Coins = 250,
			Xp = 800,
		}),
	} :: { Trainer }),

	-- Rewards. Wins against the CPU pay up to DailyRewardedWins a day (UTC);
	-- the first win against each trainer each day pays double; beating the
	-- last trainer (first time each day) also gives an office supply.
	DailyRewardedWins = 10,
	FirstWinBonus = 2,
	TopTrainerSupply = table.freeze({
		{ Item = "trophy_gold", Weight = 1 },
		{ Item = "neon_calm_sign", Weight = 3 },
		{ Item = "mini_fridge", Weight = 3 },
		{ Item = "snack_machine", Weight = 3 },
	}),

	-- Player battles: the winner and loser get coins (rewarded a few times a
	-- day, at most twice against the same player).
	PlayerWin = table.freeze({ Coins = 90, Xp = 300 }),
	PlayerLose = table.freeze({ Coins = 30, Xp = 100 }),
	DailyPlayerBattles = 5,
	MaxPerOpponent = 2,
})

return PetArenaConfig
