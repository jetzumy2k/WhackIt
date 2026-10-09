--!strict
--[[
	Pets, eggs and incubators (docs/PETS.md): every balance number lives here.
	The server enforces it (Shared/PetRules, Services/PetService); clients
	read it for display. Specs check that each egg's odds add up to 100, that
	every species' buffs fit its rarity, and that every world position is
	clear of walkways, props, bosses and each other.

	Buff kinds are the game's existing modifiers: "Xp" (boss XP), "Damage"
	(every hit) and "CritDamage" (extra damage on crits, like the store's Crit
	Damage boosts). Percentages are whole numbers.
]]

export type Rarity = "Common" | "Rare" | "Mythical"
export type BuffKind = "Xp" | "Damage" | "CritDamage"
export type Buff = { Kind: BuffKind, Percent: number }

-- How a pet is drawn (Shared/PetVisual).
export type Look = {
	Shape: "Quadruped" | "Bug" | "Winged",
	Primary: Color3,
	Secondary: Color3,
	Ears: ("Floppy" | "Pointy" | "Round" | "Long" | "Horns" | "None")?,
	Tail: ("Wag" | "Puff" | "Curl" | "Flame" | "None")?,
	Spots: boolean?, -- ladybug dots
	Horn: boolean?, -- unicorn
	Scale: number,
}

export type RarityInfo = { Label: string, Color: Color3, Order: number }

-- Ground: walks and runs. Hopping: moves in hops. Crawling: low, six legs.
-- Flying: flies beside the owner (hovers when they stop).
export type Movement = "Ground" | "Hopping" | "Crawling" | "Flying"

-- A pet's glitter (one small ParticleEmitter per pet, Lib/PetVisual).
export type Glitter = {
	Rate: number, -- sparkles per second (halved on phones)
	Size: number, -- studs at birth (they shrink away)
	Lifetime: number, -- seconds
	Colors: { Color3 },
	LightEmission: number, -- 0..1; kept low so pets never glow like lamps
}

export type Species = {
	Id: string,
	Name: string,
	Emoji: string,
	Rarity: Rarity,
	-- Common: 1, Rare: 1 (plus one random buff when hatched), Mythical: 2.
	Buffs: { Buff },
	Flies: boolean, -- hovers beside the owner instead of walking
	-- How it moves (Controllers/PetController, docs/PETS.md "Movement").
	Movement: Movement,
	-- Where it keeps to: studs to the owner's right (X) and behind them (Y),
	-- bigger for bigger pets so a Dragon never sits where a Butterfly would.
	Follow: Vector2,
	FlyHeight: number?, -- flyers: studs above the ground under them
	FlapRate: number?, -- flyers: wing beats per second when hovering
	Look: Look,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local SPECIES: { Species } = {
	-- Common: small, friendly garden creatures. One buff each.
	{
		Id = "dog",
		Name = "Dog",
		Emoji = "🐶",
		Rarity = "Common",
		Buffs = { { Kind = "Xp", Percent = 3 } },
		Flies = false,
		Movement = "Ground",
		Follow = Vector2.new(2.6, 3.4),
		Look = {
			Shape = "Quadruped",
			Primary = rgb(205, 150, 95),
			Secondary = rgb(250, 235, 210),
			Ears = "Floppy",
			Tail = "Wag",
			Scale = 1,
		},
	},
	{
		Id = "cat",
		Name = "Cat",
		Emoji = "🐱",
		Rarity = "Common",
		Buffs = { { Kind = "Damage", Percent = 3 } },
		Flies = false,
		Movement = "Ground",
		Follow = Vector2.new(2.4, 3.2),
		Look = {
			Shape = "Quadruped",
			Primary = rgb(150, 150, 160),
			Secondary = rgb(245, 245, 245),
			Ears = "Pointy",
			Tail = "Curl",
			Scale = 0.9,
		},
	},
	{
		Id = "butterfly",
		Name = "Butterfly",
		Emoji = "🦋",
		Rarity = "Common",
		Buffs = { { Kind = "CritDamage", Percent = 5 } },
		Flies = true,
		Movement = "Flying",
		Follow = Vector2.new(2.2, 2.4),
		FlyHeight = 3.2,
		FlapRate = 9,
		Look = {
			Shape = "Winged",
			Primary = rgb(90, 70, 60),
			Secondary = rgb(120, 190, 255),
			Ears = "None",
			Tail = "None",
			Scale = 0.8,
		},
	},
	{
		Id = "beetle",
		Name = "Beetle",
		Emoji = "🪲",
		Rarity = "Common",
		Buffs = { { Kind = "Damage", Percent = 3 } },
		Flies = false,
		Movement = "Crawling",
		Follow = Vector2.new(2.2, 2.8),
		Look = {
			Shape = "Bug",
			Primary = rgb(60, 140, 110),
			Secondary = rgb(35, 40, 45),
			Scale = 0.9,
		},
	},
	{
		Id = "ladybug",
		Name = "Ladybug",
		Emoji = "🐞",
		Rarity = "Common",
		Buffs = { { Kind = "CritDamage", Percent = 5 } },
		Flies = false,
		Movement = "Crawling",
		Follow = Vector2.new(2.0, 2.6),
		Look = {
			Shape = "Bug",
			Primary = rgb(220, 50, 50),
			Secondary = rgb(30, 30, 35),
			Spots = true,
			Scale = 0.8,
		},
	},
	-- Rare: friendly animals. One buff of their own plus one random buff.
	{
		Id = "rabbit",
		Name = "Rabbit",
		Emoji = "🐰",
		Rarity = "Rare",
		Buffs = { { Kind = "Xp", Percent = 6 } },
		Flies = false,
		Movement = "Hopping",
		Follow = Vector2.new(2.4, 3.2),
		Look = {
			Shape = "Quadruped",
			Primary = rgb(240, 240, 240),
			Secondary = rgb(255, 190, 200),
			Ears = "Long",
			Tail = "Puff",
			Scale = 1,
		},
	},
	{
		Id = "bear",
		Name = "Bear",
		Emoji = "🐻",
		Rarity = "Rare",
		Buffs = { { Kind = "Damage", Percent = 6 } },
		Flies = false,
		Movement = "Ground",
		Follow = Vector2.new(3.2, 4.2),
		Look = {
			Shape = "Quadruped",
			Primary = rgb(130, 85, 55),
			Secondary = rgb(200, 160, 120),
			Ears = "Round",
			Tail = "None",
			Scale = 1.25,
		},
	},
	{
		Id = "monkey",
		Name = "Monkey",
		Emoji = "🐵",
		Rarity = "Rare",
		Buffs = { { Kind = "CritDamage", Percent = 10 } },
		Flies = false,
		Movement = "Ground",
		Follow = Vector2.new(2.6, 3.4),
		Look = {
			Shape = "Quadruped",
			Primary = rgb(150, 100, 60),
			Secondary = rgb(235, 200, 160),
			Ears = "Round",
			Tail = "Curl",
			Scale = 1,
		},
	},
	{
		Id = "toucan",
		Name = "Toucan",
		Emoji = "🦜",
		Rarity = "Rare",
		Buffs = { { Kind = "Damage", Percent = 6 } },
		Flies = true,
		Movement = "Flying",
		Follow = Vector2.new(2.6, 2.8),
		FlyHeight = 3.6,
		FlapRate = 4.5,
		Look = {
			Shape = "Winged",
			Primary = rgb(30, 30, 40),
			Secondary = rgb(255, 160, 40),
			Ears = "None",
			Tail = "None",
			Scale = 1,
		},
	},
	-- Mythical: two buffs of their own. Store-only (and admin eggs).
	{
		Id = "dragon",
		Name = "Dragon",
		Emoji = "🐉",
		Rarity = "Mythical",
		Buffs = { { Kind = "Damage", Percent = 10 }, { Kind = "CritDamage", Percent = 10 } },
		Flies = true,
		Movement = "Flying",
		Follow = Vector2.new(3.6, 4.4),
		FlyHeight = 4.4,
		FlapRate = 1.8,
		Look = {
			Shape = "Winged",
			Primary = rgb(70, 170, 110),
			Secondary = rgb(250, 210, 90),
			Ears = "Horns",
			Tail = "Wag",
			Scale = 1.5,
		},
	},
	{
		Id = "phoenix",
		Name = "Phoenix",
		Emoji = "🔥",
		Rarity = "Mythical",
		Buffs = { { Kind = "Xp", Percent = 10 }, { Kind = "Damage", Percent = 6 } },
		Flies = true,
		Movement = "Flying",
		Follow = Vector2.new(3.4, 4.0),
		FlyHeight = 4.0,
		FlapRate = 2.2,
		Look = {
			Shape = "Winged",
			Primary = rgb(255, 120, 40),
			Secondary = rgb(255, 220, 90),
			Ears = "None",
			Tail = "Flame",
			Scale = 1.4,
		},
	},
	{
		Id = "unicorn",
		Name = "Unicorn",
		Emoji = "🦄",
		Rarity = "Mythical",
		Buffs = { { Kind = "Xp", Percent = 8 }, { Kind = "CritDamage", Percent = 12 } },
		Flies = false,
		Movement = "Ground",
		Follow = Vector2.new(3.2, 4.4),
		Look = {
			Shape = "Quadruped",
			Primary = rgb(250, 245, 255),
			Secondary = rgb(200, 150, 255),
			Ears = "Pointy",
			Tail = "Puff",
			Horn = true,
			Scale = 1.4,
		},
	},
}

local byId: { [string]: Species } = {}
for _, species in SPECIES do
	table.freeze(species.Look)
	for _, buff in species.Buffs do
		table.freeze(buff)
	end
	table.freeze(species.Buffs)
	byId[species.Id] = table.freeze(species)
end

local PetConfig = table.freeze({
	Species = table.freeze(SPECIES),
	ById = table.freeze(byId),
	Rarities = table.freeze({ "Common", "Rare", "Mythical" } :: { Rarity }),
	RarityInfo = table.freeze({
		Common = table.freeze({ Label = "COMMON", Color = rgb(150, 210, 140), Order = 1 }),
		Rare = table.freeze({ Label = "RARE", Color = rgb(110, 170, 255), Order = 2 }),
		Mythical = table.freeze({ Label = "MYTHICAL", Color = rgb(230, 150, 255), Order = 3 }),
	} :: { [string]: RarityInfo }),

	-- Glitter by rarity: always small and sparse, a little more for rarer pets.
	Glitter = table.freeze({
		Common = table.freeze({
			Rate = 1,
			Size = 0.14,
			Lifetime = 0.7,
			Colors = table.freeze({ rgb(255, 255, 255), rgb(255, 225, 140) }),
			LightEmission = 0.2,
		}),
		Rare = table.freeze({
			Rate = 1.8,
			Size = 0.18,
			Lifetime = 0.8,
			Colors = table.freeze({ rgb(170, 210, 255), rgb(255, 255, 255) }),
			LightEmission = 0.3,
		}),
		Mythical = table.freeze({
			Rate = 3,
			Size = 0.22,
			Lifetime = 0.9,
			Colors = table.freeze({ rgb(255, 220, 120), rgb(230, 170, 255), rgb(255, 255, 255) }),
			LightEmission = 0.45,
		}),
	} :: { [string]: Glitter }),

	-- What hatches from each egg: species id -> weight (whole percent, sums to 100).
	EggOdds = table.freeze({
		Common = table.freeze({ dog = 25, cat = 25, butterfly = 20, beetle = 15, ladybug = 15 }),
		Rare = table.freeze({ rabbit = 35, bear = 25, monkey = 25, toucan = 15 }),
		Mythical = table.freeze({ dragon = 40, phoenix = 40, unicorn = 20 }),
	} :: { [string]: { [string]: number } }),

	-- A Rare pet's extra buff: a different kind from its own, whole percent in
	-- the kind's range, rolled once when it hatches and saved with it.
	RareRandomBuff = table.freeze({
		Xp = table.freeze({ Min = 2, Max = 5 }),
		Damage = table.freeze({ Min = 2, Max = 5 }),
		CritDamage = table.freeze({ Min = 3, Max = 8 }),
	} :: { [string]: { Min: number, Max: number } }),
	-- Saved buffs are clamped to this (never trust saved data).
	MaxBuffPercent = 25,

	-- Store products for each egg (Config/StoreConfig, Kind "Egg").
	EggKeys = table.freeze({
		Common = "egg_common",
		Rare = "egg_rare",
		Mythical = "egg_mythical",
	} :: { [string]: string }),

	-- Pets a player can own; hatching is refused when full.
	MaxPets = 100,

	IncubationSeconds = 60,
	-- How close (studs) a player must be to use an incubator from the Bag.
	IncubatorReach = 14,

	-- World eggs: one spawns every WorldEggIntervalSeconds, on the UTC clock
	-- (00:00, 02:00, ...), so every server spawns at the same times. Only
	-- these rarities (weights) spawn on their own; admins can place any.
	WorldEggIntervalSeconds = 2 * 60 * 60,
	WorldEggRarities = table.freeze({ Common = 80, Rare = 20 } :: { [string]: number }),
	-- How a world egg looks: its size, and how far above the ground under it
	-- it floats (the server finds the real ground when it spawns, so it never
	-- ends up inside the terrain), plus how far away its 🥚 marker shows.
	WorldEggSize = Vector3.new(2, 2.6, 2),
	WorldEggHover = 1,
	WorldEggMarkerDistance = 60,
	-- At most this many unclaimed eggs at once (the schedule waits while one
	-- is still out there; admins can add a few more).
	MaxWorldEggs = 3,
	-- Safe spots on walkways (kept free of props, ArenaConfig.Campus), away
	-- from the building, event boss slots and the incubators. Only X and Z
	-- matter: the egg is set on the real ground there (PetService).
	WorldEggSpawnPoints = table.freeze({
		Vector3.new(-97, 0, 20),
		Vector3.new(97, 0, 20),
		Vector3.new(-97, 0, -30),
		Vector3.new(97, 0, -30),
		Vector3.new(-60, 0, -63),
		Vector3.new(60, 0, -63),
		Vector3.new(-70, 0, 43),
		Vector3.new(0, 0, 110),
		Vector3.new(-97, 0, 80),
		Vector3.new(97, 0, 80),
	}),

	-- Pet Incubation Center: the lawn east of the Front Plaza, facing the
	-- walkway in front of the building (-Z).
	Incubators = table.freeze({
		Vector3.new(54, -1, 56),
		Vector3.new(60.5, -1, 56),
		Vector3.new(67, -1, 56),
		Vector3.new(73.5, -1, 56),
		Vector3.new(80, -1, 56),
		Vector3.new(86.5, -1, 56),
	}),
	CenterSign = Vector3.new(70.25, -1, 62),
})

return PetConfig
