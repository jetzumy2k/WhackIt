--!strict
--[[
	The Lucky Capsule Machine (docs/CAPSULE.md, recreation games 2026-10-10,
	owner choice "Lucky Capsule Machine"). Not a bet: a spin costs a fixed
	coin price and EVERY spin wins a prize. Coins only (never Robux; coins
	can't be bought). Odds are shown before spinning, there is a daily spin
	limit, and the last spin of the day is guaranteed Rare or better.

	Prize weights are in thousandths and add up to 1000 (spec-checked).
]]

export type Tier = string -- "Common" | "Uncommon" | "Rare" | "Epic" | "Jackpot"
export type Kind = string -- "Coins" | "Xp" | "Bag" | "Supply"

export type Prize = {
	Id: string,
	Tier: Tier,
	Kind: Kind,
	Amount: number, -- coins or XP (Coins / Xp); how many (Bag / Supply)
	Key: string?, -- Bag item key (StoreConfig) for Kind "Bag"
	Label: string,
	Icon: string,
	Weight: number, -- out of 1000
}

local CapsuleConfig = table.freeze({
	Cost = 200,
	MinLevel = 5,
	DailySpins = 10,
	-- The last spin of the day only picks from these tiers.
	LuckyTiers = table.freeze({ "Rare", "Epic", "Jackpot" }),

	Tiers = table.freeze({
		Common = table.freeze({ Order = 1, Color = Color3.fromRGB(190, 200, 215) }),
		Uncommon = table.freeze({ Order = 2, Color = Color3.fromRGB(120, 210, 130) }),
		Rare = table.freeze({ Order = 3, Color = Color3.fromRGB(100, 170, 255) }),
		Epic = table.freeze({ Order = 4, Color = Color3.fromRGB(210, 130, 255) }),
		Jackpot = table.freeze({ Order = 5, Color = Color3.fromRGB(255, 200, 60) }),
	}),

	Prizes = table.freeze({
		table.freeze({
			Id = "coins_100",
			Tier = "Common",
			Kind = "Coins",
			Amount = 100,
			Label = "100 coins",
			Icon = "💰",
			Weight = 260,
		}),
		table.freeze({
			Id = "coins_250",
			Tier = "Common",
			Kind = "Coins",
			Amount = 250,
			Label = "250 coins",
			Icon = "💰",
			Weight = 180,
		}),
		table.freeze({
			Id = "xp_400",
			Tier = "Common",
			Kind = "Xp",
			Amount = 400,
			Label = "400 XP",
			Icon = "✨",
			Weight = 160,
		}),
		table.freeze({
			Id = "boost_xp",
			Tier = "Uncommon",
			Kind = "Bag",
			Amount = 1,
			Key = "xp_10_30m",
			Label = "+10% XP boost (30 min)",
			Icon = "✨",
			Weight = 90,
		}),
		table.freeze({
			Id = "boost_dmg",
			Tier = "Uncommon",
			Kind = "Bag",
			Amount = 1,
			Key = "dmg_5_30m",
			Label = "+5% Damage boost (30 min)",
			Icon = "💥",
			Weight = 80,
		}),
		table.freeze({
			Id = "boost_crit",
			Tier = "Uncommon",
			Kind = "Bag",
			Amount = 1,
			Key = "crit_5_30m",
			Label = "+5% Crit Damage boost (30 min)",
			Icon = "🎯",
			Weight = 70,
		}),
		table.freeze({
			Id = "coins_500",
			Tier = "Rare",
			Kind = "Coins",
			Amount = 500,
			Label = "500 coins",
			Icon = "💰",
			Weight = 60,
		}),
		table.freeze({
			Id = "supply",
			Tier = "Rare",
			Kind = "Supply",
			Amount = 1,
			Label = "An office supply",
			Icon = "📦",
			Weight = 60,
		}),
		table.freeze({
			Id = "egg_common",
			Tier = "Epic",
			Kind = "Bag",
			Amount = 1,
			Key = "egg_common",
			Label = "A Common Egg",
			Icon = "🥚",
			Weight = 25,
		}),
		table.freeze({
			Id = "egg_rare",
			Tier = "Epic",
			Kind = "Bag",
			Amount = 1,
			Key = "egg_rare",
			Label = "A Rare Egg",
			Icon = "🥚",
			Weight = 8,
		}),
		table.freeze({
			Id = "jackpot",
			Tier = "Jackpot",
			Kind = "Coins",
			Amount = 3000,
			Label = "JACKPOT! 3,000 coins",
			Icon = "🎉",
			Weight = 7,
		}),
	} :: { Prize }),

	-- Office supplies the "supply" prize picks from (Special furniture).
	SupplyPool = table.freeze({
		{ Item = "paddle_rack", Weight = 20 },
		{ Item = "ball_bucket", Weight = 20 },
		{ Item = "desk_fan", Weight = 20 },
		{ Item = "mini_fridge", Weight = 15 },
		{ Item = "bonsai_zen", Weight = 10 },
		{ Item = "snack_machine", Weight = 8 },
		{ Item = "neon_calm_sign", Weight = 7 },
	}),
})

return CapsuleConfig
