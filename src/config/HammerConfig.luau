--!strict
-- Hammer definitions. Hit damage is hammer-driven (see docs/GAMEPLAY_RULES.md):
-- damage = Damage x boss DamageTakenMultiplier, computed only on the server.

export type HammerDefinition = {
	Id: string,
	DisplayName: string,
	Description: string,
	Damage: number,
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
