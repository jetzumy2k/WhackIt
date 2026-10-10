--!strict
-- Hammer definitions. Hit damage is hammer-driven (see docs/GAMEPLAY_RULES.md):
-- damage = Damage x boss DamageTakenMultiplier, computed only on the server.

export type HammerDefinition = {
	Id: string,
	DisplayName: string,
	Description: string,
	Damage: number,
	Price: number, -- coins; 0 = owned by everyone from the start
	-- Player Level needed to buy it (2026-10-09, docs/GAMEPLAY_RULES.md);
	-- players who already own it keep it.
	MinLevel: number?,
	HeadColor: Color3, -- main colours (fallback look, UI accents)
	HandleColor: Color3,
	Style: string, -- the look in Config/HammerStyleConfig
}

export type HammerConfig = {
	List: { HammerDefinition },
	ById: { [string]: HammerDefinition },
}

-- Shop order. Pricier hammers always hit harder. Coin hammers stop below the
-- Mystery Hammer (StoreConfig.Mystery: 62 base damage + its rolled bonus
-- since 2026-10-10, owner decision; it was 35 before the legendary tier).
local list: { HammerDefinition } = {
	{
		Id = "squeaky_hammer",
		DisplayName = "Squeaky Hammer",
		Description = "A trusty foam hammer. Squeaks on every whack.",
		Damage = 10,
		Price = 0,
		HeadColor = Color3.fromRGB(255, 70, 90),
		HandleColor = Color3.fromRGB(255, 210, 60),
		Style = "squeaky",
	},
	{
		Id = "office_hammer",
		DisplayName = "Classic Office Hammer",
		Description = "Straight from the supply closet. Sturdy and reliable.",
		Damage = 12,
		Price = 75,
		HeadColor = Color3.fromRGB(150, 155, 165),
		HandleColor = Color3.fromRGB(150, 100, 60),
		Style = "office",
	},
	{
		Id = "bouncy_mallet",
		DisplayName = "Bouncy Mallet",
		Description = "Boings back for the next whack.",
		Damage = 14,
		Price = 150,
		HeadColor = Color3.fromRGB(80, 200, 255),
		HandleColor = Color3.fromRGB(255, 255, 255),
		Style = "bouncy",
	},
	{
		Id = "bubble_wrap_hammer",
		DisplayName = "Bubble-Wrap Hammer",
		Description = "Every hit pops a hundred tiny worries.",
		Damage = 18,
		Price = 400,
		HeadColor = Color3.fromRGB(220, 245, 255),
		HandleColor = Color3.fromRGB(120, 200, 140),
		Style = "bubble_wrap",
	},
	{
		Id = "neon_hammer",
		DisplayName = "Neon Hammer",
		Description = "Glows like the office after hours.",
		Damage = 21,
		Price = 650,
		HeadColor = Color3.fromRGB(0, 240, 255),
		HandleColor = Color3.fromRGB(30, 30, 40),
		Style = "neon",
	},
	{
		Id = "rainbow_mega_mallet",
		DisplayName = "Rainbow Mega Mallet",
		Description = "Maximum stress relief, maximum colour.",
		Damage = 25,
		Price = 1000,
		HeadColor = Color3.fromRGB(255, 120, 220),
		HandleColor = Color3.fromRGB(255, 230, 90),
		Style = "rainbow_mega",
	},
	{
		Id = "golden_hammer",
		DisplayName = "Golden Hammer",
		Description = "Employee of the month, every month.",
		Damage = 27,
		Price = 1600,
		HeadColor = Color3.fromRGB(255, 200, 60),
		HandleColor = Color3.fromRGB(110, 45, 35),
		Style = "golden",
	},
	{
		Id = "fire_hammer",
		DisplayName = "Fire Hammer",
		Description = "For burning through the to-do list.",
		Damage = 29,
		Price = 2500,
		MinLevel = 15,
		HeadColor = Color3.fromRGB(255, 120, 30),
		HandleColor = Color3.fromRGB(50, 42, 40),
		Style = "fire",
	},
	{
		Id = "lightning_hammer",
		DisplayName = "Lightning Hammer",
		Description = "Faster than an urgent email.",
		Damage = 30,
		Price = 3500,
		MinLevel = 20,
		HeadColor = Color3.fromRGB(215, 230, 255),
		HandleColor = Color3.fromRGB(30, 40, 80),
		Style = "lightning",
	},
	{
		Id = "cosmic_hammer",
		DisplayName = "Cosmic Hammer",
		Description = "Puts every problem in perspective.",
		Damage = 31,
		Price = 5000,
		MinLevel = 30,
		HeadColor = Color3.fromRGB(170, 120, 255),
		HandleColor = Color3.fromRGB(60, 30, 110),
		Style = "cosmic",
	},
	{
		Id = "stress_crusher",
		DisplayName = "Stress Crusher",
		Description = "Heavy-duty relief for the toughest days.",
		Damage = 32,
		Price = 8000,
		MinLevel = 40,
		HeadColor = Color3.fromRGB(255, 200, 40),
		HandleColor = Color3.fromRGB(110, 115, 125),
		Style = "stress_crusher",
	},
	-- Legendary tier (2026-10-10): Lv 45-95, 35-60 damage, each with its own
	-- impact burst (HammerStyleConfig Impact). Still under the Mystery Hammer.
	{
		Id = "thunder_gavel",
		DisplayName = "Thunder Gavel",
		Description = "Order in the office! Every whack rolls thunder.",
		Damage = 35,
		Price = 12000,
		MinLevel = 45,
		HeadColor = Color3.fromRGB(70, 130, 255),
		HandleColor = Color3.fromRGB(40, 45, 70),
		Style = "thunder_gavel",
	},
	{
		Id = "frost_mallet",
		DisplayName = "Frost Mallet",
		Description = "Chills any meltdown. Leaves a frosty sparkle behind.",
		Damage = 38,
		Price = 16000,
		MinLevel = 50,
		HeadColor = Color3.fromRGB(150, 225, 255),
		HandleColor = Color3.fromRGB(230, 245, 255),
		Style = "frost",
	},
	{
		Id = "lava_breaker",
		DisplayName = "Lava Breaker",
		Description = "Molten core, cool head. Melts stress on contact.",
		Damage = 41,
		Price = 21000,
		MinLevel = 55,
		HeadColor = Color3.fromRGB(255, 90, 30),
		HandleColor = Color3.fromRGB(60, 35, 30),
		Style = "lava",
	},
	{
		Id = "crystal_smasher",
		DisplayName = "Crystal Smasher",
		Description = "A prism head that splits every hit into rainbows.",
		Damage = 44,
		Price = 27000,
		MinLevel = 60,
		HeadColor = Color3.fromRGB(210, 140, 255),
		HandleColor = Color3.fromRGB(235, 235, 245),
		Style = "crystal",
	},
	{
		Id = "plasma_pounder",
		DisplayName = "Plasma Pounder",
		Description = "Humming energy cell. Zaps deadlines into dust.",
		Damage = 47,
		Price = 34000,
		MinLevel = 65,
		HeadColor = Color3.fromRGB(60, 255, 200),
		HandleColor = Color3.fromRGB(40, 50, 60),
		Style = "plasma",
	},
	{
		Id = "jade_dragon_hammer",
		DisplayName = "Jade Dragon Hammer",
		Description = "Carved jade with a golden dragon coil. Calm and mighty.",
		Damage = 50,
		Price = 42000,
		MinLevel = 70,
		HeadColor = Color3.fromRGB(60, 190, 120),
		HandleColor = Color3.fromRGB(200, 60, 50),
		Style = "jade_dragon",
	},
	{
		Id = "solar_flare_hammer",
		DisplayName = "Solar Flare Hammer",
		Description = "A pocket sun on a stick. Bright ideas only.",
		Damage = 52,
		Price = 52000,
		MinLevel = 75,
		HeadColor = Color3.fromRGB(255, 190, 50),
		HandleColor = Color3.fromRGB(255, 245, 220),
		Style = "solar",
	},
	{
		Id = "void_crusher",
		DisplayName = "Void Crusher",
		Description = "Swallows bad vibes whole. Deep purple calm.",
		Damage = 55,
		Price = 64000,
		MinLevel = 80,
		HeadColor = Color3.fromRGB(90, 40, 160),
		HandleColor = Color3.fromRGB(20, 15, 30),
		Style = "void",
	},
	{
		Id = "galaxy_gavel",
		DisplayName = "Galaxy Gavel",
		Description = "Swirling stars and a ringed planet. Out of this world.",
		Damage = 58,
		Price = 80000,
		MinLevel = 88,
		HeadColor = Color3.fromRGB(60, 90, 220),
		HandleColor = Color3.fromRGB(25, 20, 50),
		Style = "galaxy",
	},
	{
		Id = "zen_titan_hammer",
		DisplayName = "Zen Titan Hammer",
		Description = "The legendary hammer of perfect calm. One whack, total peace.",
		Damage = 60,
		Price = 100000,
		MinLevel = 95,
		HeadColor = Color3.fromRGB(255, 255, 255),
		HandleColor = Color3.fromRGB(230, 190, 80),
		Style = "zen_titan",
	},
}

local byId: { [string]: HammerDefinition } = {}
for _, hammer in list do
	if byId[hammer.Id] then
		error(string.format("[HammerConfig] duplicate hammer id %q", hammer.Id))
	end
	byId[hammer.Id] = table.freeze(hammer)
end

local HammerConfig: HammerConfig = table.freeze({
	List = table.freeze(list),
	ById = table.freeze(byId),
})

return HammerConfig
