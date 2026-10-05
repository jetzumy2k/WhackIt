--!strict
-- Hammer definitions. Hit damage is hammer-driven (see docs/GAMEPLAY_RULES.md):
-- damage = Damage x boss DamageTakenMultiplier, computed only on the server.

export type HammerDefinition = {
	Id: string,
	DisplayName: string,
	Description: string,
	Damage: number,
	Price: number, -- coins; 0 = owned by everyone from the start
	HeadColor: Color3,
	HandleColor: Color3,
}

export type HammerConfig = {
	List: { HammerDefinition },
	ById: { [string]: HammerDefinition },
}

local list: { HammerDefinition } = {
	{
		Id = "squeaky_hammer",
		DisplayName = "Squeaky Hammer",
		Description = "A trusty foam hammer. Squeaks on every whack.",
		Damage = 10,
		Price = 0,
		HeadColor = Color3.fromRGB(255, 70, 90),
		HandleColor = Color3.fromRGB(255, 210, 60),
	},
	{
		Id = "bouncy_mallet",
		DisplayName = "Bouncy Mallet",
		Description = "Boings back for the next whack.",
		Damage = 14,
		Price = 150,
		HeadColor = Color3.fromRGB(80, 200, 255),
		HandleColor = Color3.fromRGB(255, 255, 255),
	},
	{
		Id = "bubble_wrap_hammer",
		DisplayName = "Bubble-Wrap Hammer",
		Description = "Every hit pops a hundred tiny worries.",
		Damage = 18,
		Price = 400,
		HeadColor = Color3.fromRGB(220, 245, 255),
		HandleColor = Color3.fromRGB(120, 200, 140),
	},
	{
		Id = "rainbow_mega_mallet",
		DisplayName = "Rainbow Mega Mallet",
		Description = "Maximum stress relief, maximum colour.",
		Damage = 25,
		Price = 1000,
		HeadColor = Color3.fromRGB(255, 120, 220),
		HandleColor = Color3.fromRGB(255, 230, 90),
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
