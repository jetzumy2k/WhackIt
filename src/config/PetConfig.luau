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
	Ears: ("Floppy" | "Pointy" | "Round" | "Long" | "Horns" | "Tufts" | "None")?,
	Tail: ("Wag" | "Puff" | "Curl" | "Flame" | "Bushy" | "None")?,
	Spots: boolean?, -- ladybug dots
	Horn: boolean?, -- unicorn
	-- Since 2026-10-10 (Shared look features, Lib/PetVisual):
	Insect: boolean?, -- flyers: a tiny insect body with antennae (butterfly, bee, firefly)
	Stripes: boolean?, -- dark bands across the body (bee, tiger)
	Glow: boolean?, -- a softly glowing tail light (firefly)
	Beak: ("Long" | "Short")?, -- flyers: toucan / owl, griffin
	Dragon: boolean?, -- flyers: big wings, a long tail and claws
	Mane: boolean?, -- a fluffy mane round the head (lion, griffin)
	Wings: boolean?, -- walkers with wings (pegasus)
	Spikes: boolean?, -- hedgehog prickles
	Patches: boolean?, -- panda eye patches
	Antlers: boolean?, -- deer
	Cheeks: boolean?, -- hamster cheek pouches
	BigEyes: boolean?, -- frog eyes on top of the head
	Tails: number?, -- bushy tails fanned out (kitsune: 3)
	Aura: Color3?, -- Mythical: a soft spinning ring of light under the pet
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
			Insect = true,
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
	-- New Common pets (2026-10-10) ----------------------------------------------
	{
		Id = "hamster",
		Name = "Hamster",
		Emoji = "🐹",
		Rarity = "Common",
		Buffs = { { Kind = "Xp", Percent = 4 } },
		Flies = false,
		Movement = "Ground",
		Follow = Vector2.new(2.0, 2.6),
		Look = {
			Shape = "Quadruped",
			Primary = rgb(235, 175, 110),
			Secondary = rgb(255, 245, 230),
			Ears = "Round",
			Tail = "Puff",
			Cheeks = true,
			Scale = 0.7,
		},
	},
	{
		Id = "frog",
		Name = "Frog",
		Emoji = "🐸",
		Rarity = "Common",
		Buffs = { { Kind = "Damage", Percent = 4 } },
		Flies = false,
		Movement = "Hopping",
		Follow = Vector2.new(2.2, 2.8),
		Look = {
			Shape = "Quadruped",
			Primary = rgb(90, 200, 90),
			Secondary = rgb(220, 250, 170),
			Ears = "None",
			Tail = "None",
			BigEyes = true,
			Scale = 0.8,
		},
	},
	{
		Id = "bee",
		Name = "Bee",
		Emoji = "🐝",
		Rarity = "Common",
		Buffs = { { Kind = "CritDamage", Percent = 5 } },
		Flies = true,
		Movement = "Flying",
		Follow = Vector2.new(2.2, 2.4),
		FlyHeight = 3.0,
		FlapRate = 14,
		Look = {
			Shape = "Winged",
			Primary = rgb(255, 200, 40),
			Secondary = rgb(35, 30, 30),
			Insect = true,
			Stripes = true,
			Scale = 0.8,
		},
	},
	{
		Id = "firefly",
		Name = "Firefly",
		Emoji = "✨",
		Rarity = "Common",
		Buffs = { { Kind = "Xp", Percent = 5 } },
		Flies = true,
		Movement = "Flying",
		Follow = Vector2.new(2.0, 2.4),
		FlyHeight = 3.4,
		FlapRate = 11,
		Look = {
			Shape = "Winged",
			Primary = rgb(70, 60, 50),
			Secondary = rgb(200, 255, 120),
			Insect = true,
			Glow = true,
			Scale = 0.75,
		},
	},
	{
		Id = "hedgehog",
		Name = "Hedgehog",
		Emoji = "🦔",
		Rarity = "Common",
		Buffs = { { Kind = "Damage", Percent = 4 } },
		Flies = false,
		Movement = "Ground",
		Follow = Vector2.new(2.0, 2.8),
		Look = {
			Shape = "Quadruped",
			Primary = rgb(160, 120, 90),
			Secondary = rgb(240, 220, 195),
			Ears = "Round",
			Tail = "None",
			Spikes = true,
			Scale = 0.75,
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
			Beak = "Long",
			Scale = 1,
		},
	},
	-- New Rare pets (2026-10-10) ------------------------------------------------
	{
		Id = "fox",
		Name = "Fox",
		Emoji = "🦊",
		Rarity = "Rare",
		Buffs = { { Kind = "CritDamage", Percent = 10 } },
		Flies = false,
		Movement = "Ground",
		Follow = Vector2.new(2.6, 3.4),
		Look = {
			Shape = "Quadruped",
			Primary = rgb(240, 120, 40),
			Secondary = rgb(255, 245, 235),
			Ears = "Pointy",
			Tail = "Bushy",
			Scale = 1,
		},
	},
	{
		Id = "panda",
		Name = "Panda",
		Emoji = "🐼",
		Rarity = "Rare",
		Buffs = { { Kind = "Xp", Percent = 8 } },
		Flies = false,
		Movement = "Ground",
		Follow = Vector2.new(3.0, 4.0),
		Look = {
			Shape = "Quadruped",
			Primary = rgb(250, 250, 250),
			Secondary = rgb(35, 35, 40),
			Ears = "Round",
			Tail = "Puff",
			Patches = true,
			Scale = 1.2,
		},
	},
	{
		Id = "owl",
		Name = "Owl",
		Emoji = "🦉",
		Rarity = "Rare",
		Buffs = { { Kind = "Xp", Percent = 9 } },
		Flies = true,
		Movement = "Flying",
		Follow = Vector2.new(2.6, 2.8),
		FlyHeight = 3.8,
		FlapRate = 3.5,
		Look = {
			Shape = "Winged",
			Primary = rgb(150, 110, 75),
			Secondary = rgb(240, 215, 170),
			Ears = "Tufts",
			Beak = "Short",
			Scale = 1,
		},
	},
	{
		Id = "tiger",
		Name = "Tiger",
		Emoji = "🐯",
		Rarity = "Rare",
		Buffs = { { Kind = "Damage", Percent = 8 } },
		Flies = false,
		Movement = "Ground",
		Follow = Vector2.new(3.0, 4.0),
		Look = {
			Shape = "Quadruped",
			Primary = rgb(245, 150, 40),
			Secondary = rgb(35, 30, 30),
			Ears = "Round",
			Tail = "Curl",
			Stripes = true,
			Scale = 1.2,
		},
	},
	{
		Id = "deer",
		Name = "Deer",
		Emoji = "🦌",
		Rarity = "Rare",
		Buffs = { { Kind = "CritDamage", Percent = 9 } },
		Flies = false,
		Movement = "Ground",
		Follow = Vector2.new(3.0, 4.0),
		Look = {
			Shape = "Quadruped",
			Primary = rgb(180, 120, 70),
			Secondary = rgb(250, 235, 210),
			Ears = "Pointy",
			Tail = "Puff",
			Antlers = true,
			Scale = 1.2,
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
			Dragon = true,
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
	-- New Mythical pets (2026-10-10): each with a soft spinning aura ring.
	{
		Id = "griffin",
		Name = "Griffin",
		Emoji = "🦅",
		Rarity = "Mythical",
		Buffs = { { Kind = "Damage", Percent = 10 }, { Kind = "CritDamage", Percent = 12 } },
		Flies = true,
		Movement = "Flying",
		Follow = Vector2.new(3.6, 4.4),
		FlyHeight = 4.4,
		FlapRate = 2.0,
		Look = {
			Shape = "Winged",
			Primary = rgb(200, 160, 90),
			Secondary = rgb(250, 250, 245),
			Beak = "Short",
			Mane = true,
			Dragon = true,
			Aura = rgb(255, 210, 110),
			Scale = 1.5,
		},
	},
	{
		Id = "pegasus",
		Name = "Pegasus",
		Emoji = "🐴",
		Rarity = "Mythical",
		Buffs = { { Kind = "Xp", Percent = 12 }, { Kind = "CritDamage", Percent = 10 } },
		Flies = false,
		Movement = "Ground",
		Follow = Vector2.new(3.4, 4.6),
		Look = {
			Shape = "Quadruped",
			Primary = rgb(250, 250, 255),
			Secondary = rgb(170, 210, 255),
			Ears = "Pointy",
			Tail = "Puff",
			Wings = true,
			Aura = rgb(170, 210, 255),
			Scale = 1.4,
		},
	},
	{
		Id = "kitsune",
		Name = "Kitsune",
		Emoji = "🌸",
		Rarity = "Mythical",
		Buffs = { { Kind = "CritDamage", Percent = 15 }, { Kind = "Xp", Percent = 8 } },
		Flies = false,
		Movement = "Ground",
		Follow = Vector2.new(3.0, 4.2),
		Look = {
			Shape = "Quadruped",
			Primary = rgb(250, 245, 255),
			Secondary = rgb(255, 120, 190),
			Ears = "Pointy",
			Tail = "Bushy",
			Tails = 3,
			Aura = rgb(255, 140, 210),
			Scale = 1.2,
		},
	},
	{
		Id = "ice_dragon",
		Name = "Ice Dragon",
		Emoji = "🐲",
		Rarity = "Mythical",
		Buffs = { { Kind = "Damage", Percent = 10 }, { Kind = "Xp", Percent = 10 } },
		Flies = true,
		Movement = "Flying",
		Follow = Vector2.new(3.6, 4.4),
		FlyHeight = 4.4,
		FlapRate = 1.8,
		Look = {
			Shape = "Winged",
			Primary = rgb(170, 220, 255),
			Secondary = rgb(240, 250, 255),
			Ears = "Horns",
			Tail = "Wag",
			Dragon = true,
			Aura = rgb(150, 220, 255),
			Scale = 1.5,
		},
	},
	{
		Id = "celestial_lion",
		Name = "Celestial Lion",
		Emoji = "🦁",
		Rarity = "Mythical",
		Buffs = { { Kind = "Damage", Percent = 10 }, { Kind = "CritDamage", Percent = 14 } },
		Flies = false,
		Movement = "Ground",
		Follow = Vector2.new(3.4, 4.6),
		Look = {
			Shape = "Quadruped",
			Primary = rgb(250, 215, 120),
			Secondary = rgb(255, 160, 60),
			Ears = "Round",
			Tail = "Curl",
			Mane = true,
			Aura = rgb(255, 230, 140),
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
		-- 2026-10-10: 15 new species shared the odds (5 per egg).
		Common = table.freeze({
			dog = 12,
			cat = 12,
			butterfly = 10,
			beetle = 9,
			ladybug = 9,
			hamster = 11,
			frog = 10,
			bee = 10,
			firefly = 8,
			hedgehog = 9,
		}),
		Rare = table.freeze({
			rabbit = 14,
			bear = 12,
			monkey = 12,
			toucan = 9,
			fox = 12,
			panda = 11,
			owl = 11,
			tiger = 9,
			deer = 10,
		}),
		Mythical = table.freeze({
			dragon = 15,
			phoenix = 15,
			unicorn = 12,
			griffin = 13,
			pegasus = 13,
			kitsune = 11,
			ice_dragon = 11,
			celestial_lion = 10,
		}),
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
