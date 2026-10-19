--!strict
--[[
	The Synthesis Machine (docs/SYNTHESIS.md, owner decisions 2026-10-19):
	combine several items into one better item, for a coin fee.

	Recipes (server-checked in Services/SynthesisService, rules in
	Shared/SynthesisRules):
	  * Boosts: `Count` Bag boosts of the same length -> one longer boost.
	    All the same kind: that kind, guaranteed. Kinds mixed: a random kind
	    (equal odds), or the player's choice with a Synthesis Pick. The
	    strength is never above the weakest boost put in (see SynthesisRules).
	    Fewer total minutes come out than go in (3 x 30 min -> 1 h,
	    6 x 1 h -> 5 h), so the machine never makes boost time.
	  * Eggs: 4 Common Eggs -> 1 Rare Egg. Rare -> Mythical exists but is off:
	    the Mythical egg stays Robux/admin-only (owner decision).
	  * Supply Swap: 4 identical office supplies (unplaced ones) -> 1 different
	    supply, random (equal odds) or chosen with a Synthesis Pick.
	  * Hammers: none. Shop hammers are one-time unlocks without rarities and
	    Mystery Hammers are unique paid items, so there is nothing to combine.

	Fees are coins only (coins can't be bought). The only Robux part is the
	optional Synthesis Pick (StoreConfig "synthesis_pick"), which lets a
	random recipe give the result the player chooses instead.
]]

export type Category = string -- "Boosts" | "Eggs" | "Supplies" | "Hammers"

-- "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"
export type Tier = string

export type TierInfo = { Order: number, Color: Color3 }

export type BoostRecipe = {
	Id: string,
	Category: Category, -- "Boosts"
	InputSeconds: number, -- every boost put in must last exactly this long
	Count: number,
	OutputSeconds: number, -- must match a StoreConfig boost duration
	Fee: number, -- coins
	Tier: Tier, -- how grand the reveal is (Tiers below)
	Enabled: boolean,
}

export type ItemRecipe = {
	Id: string,
	Category: Category, -- "Eggs"
	Input: string, -- Bag key (StoreConfig)
	Count: number,
	Output: string, -- Bag key (StoreConfig)
	Fee: number,
	Tier: Tier,
	Enabled: boolean,
}

export type SwapRecipe = {
	Id: string,
	Category: Category, -- "Supplies"
	Count: number,
	Fee: number,
	Tier: Tier,
	Enabled: boolean,
}

export type CategoryInfo = {
	Id: Category,
	Label: string,
	Icon: string,
	-- Shown when the category has no recipe at all (Hammers).
	Unavailable: string?,
}

local BOOST_RECIPES: { BoostRecipe } = {
	{
		Id = "boost_30m",
		Category = "Boosts",
		InputSeconds = 30 * 60,
		Count = 3,
		OutputSeconds = 60 * 60,
		Fee = 150,
		Tier = "Uncommon",
		Enabled = true,
	},
	{
		Id = "boost_1h",
		Category = "Boosts",
		InputSeconds = 60 * 60,
		Count = 6,
		OutputSeconds = 5 * 60 * 60,
		Fee = 600,
		Tier = "Epic",
		Enabled = true,
	},
}

local ITEM_RECIPES: { ItemRecipe } = {
	{
		Id = "egg_common",
		Category = "Eggs",
		Input = "egg_common",
		Count = 4,
		Output = "egg_rare",
		Fee = 300,
		Tier = "Rare",
		Enabled = true,
	},
	{
		-- Off (owner decision 2026-10-19): would be the first no-Robux way to
		-- a Mythical egg. Turn on only with the owner's approval.
		Id = "egg_rare",
		Category = "Eggs",
		Input = "egg_rare",
		Count = 4,
		Output = "egg_mythical",
		Fee = 1200,
		Tier = "Legendary",
		Enabled = false,
	},
}

local SWAP_RECIPES: { SwapRecipe } = {
	{
		Id = "supply_swap",
		Category = "Supplies",
		Count = 4,
		Fee = 200,
		Tier = "Rare",
		Enabled = true,
	},
}

local SynthesisConfig = table.freeze({
	BoostRecipes = table.freeze(BOOST_RECIPES),
	ItemRecipes = table.freeze(ITEM_RECIPES),
	SwapRecipes = table.freeze(SWAP_RECIPES),

	-- Office supplies a Supply Swap can take and give (Special furniture,
	-- Config/FurnitureConfig). Trophies and contest prizes are never here.
	SupplyPool = table.freeze({
		"paddle_rack",
		"ball_bucket",
		"desk_fan",
		"mini_fridge",
		"snack_machine",
		"neon_calm_sign",
	}),

	-- Reveal colours and strength: Common/Uncommon a simple glow, Rare/Epic
	-- more sparkle, Legendary the full show.
	Tiers = table.freeze({
		Common = table.freeze({ Order = 1, Color = Color3.fromRGB(190, 200, 215) }),
		Uncommon = table.freeze({ Order = 2, Color = Color3.fromRGB(120, 210, 130) }),
		Rare = table.freeze({ Order = 3, Color = Color3.fromRGB(100, 170, 255) }),
		Epic = table.freeze({ Order = 4, Color = Color3.fromRGB(210, 130, 255) }),
		Legendary = table.freeze({ Order = 5, Color = Color3.fromRGB(255, 200, 60) }),
	} :: { [string]: TierInfo }),

	-- The Bag item (StoreConfig) that lets a random recipe give a chosen result.
	PickKey = "synthesis_pick",

	Categories = table.freeze({
		table.freeze({ Id = "Boosts", Label = "Boosts", Icon = "✨" }),
		table.freeze({ Id = "Eggs", Label = "Eggs", Icon = "🥚" }),
		table.freeze({ Id = "Supplies", Label = "Office Supplies", Icon = "📦" }),
		table.freeze({
			Id = "Hammers",
			Label = "Hammers",
			Icon = "🔨",
			Unavailable = "No hammer recipes yet. Shop hammers are one-of-a-kind unlocks and Mystery Hammers keep their own rolled stats, so there is nothing to combine.",
		}),
	} :: { CategoryInfo }),

	-- How close (studs) a player must stand to the machine to synthesize.
	Reach = 14,
	-- Shortest time between two syntheses by one player (the reveal plays meanwhile).
	CooldownSeconds = 1.5,
	-- Most different items one request may name (a recipe takes at most 6).
	MaxSelection = 8,
})

return SynthesisConfig
