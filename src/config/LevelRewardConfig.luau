--!strict
--[[
	What levelling up gives (docs/GAMEPLAY_RULES.md "Level rewards",
	2026-10-09). Every level pays coins; every 5 levels unlocks something:
	a title (shown over your head and on the Profile page), a hammer trail
	colour or a Zen glow colour. Titles follow the level on their own; trails
	and glows are picked on the Profile page once unlocked.

	The hammer shop's level requirements live with the hammers
	(HammerConfig.MinLevel) and are listed here only as text on the reward
	track (Shared/LevelRewardRules.rewardsAt).
]]

export type Title = { Level: number, Name: string }
export type Cosmetic = { Id: string, Name: string, Level: number, Color: Color3 }

local function cosmetics(list: { Cosmetic }): ({ Cosmetic }, { [string]: Cosmetic })
	local byId: { [string]: Cosmetic } = {}
	for _, item in list do
		assert(byId[item.Id] == nil, "duplicate cosmetic id " .. item.Id)
		byId[item.Id] = table.freeze(item)
	end
	return table.freeze(list), table.freeze(byId)
end

local trails, trailsById = cosmetics({
	{ Id = "mint", Name = "Mint Trail", Level = 15, Color = Color3.fromRGB(120, 240, 190) },
	{ Id = "sunset", Name = "Sunset Trail", Level = 35, Color = Color3.fromRGB(255, 140, 90) },
	{ Id = "galaxy", Name = "Galaxy Trail", Level = 55, Color = Color3.fromRGB(150, 110, 255) },
	{ Id = "lava", Name = "Lava Trail", Level = 70, Color = Color3.fromRGB(255, 80, 40) },
	{ Id = "ice", Name = "Ice Trail", Level = 85, Color = Color3.fromRGB(170, 230, 255) },
	{ Id = "prism", Name = "Prism Trail", Level = 95, Color = Color3.fromRGB(255, 120, 230) },
})

local glows, glowsById = cosmetics({
	{ Id = "ocean", Name = "Ocean Glow", Level = 25, Color = Color3.fromRGB(90, 190, 255) },
	{ Id = "rose", Name = "Rose Glow", Level = 45, Color = Color3.fromRGB(255, 130, 180) },
	{ Id = "aurora", Name = "Aurora Glow", Level = 65, Color = Color3.fromRGB(110, 255, 170) },
	{ Id = "violet", Name = "Violet Glow", Level = 80, Color = Color3.fromRGB(180, 120, 255) },
	{ Id = "sunburst", Name = "Sunburst Glow", Level = 90, Color = Color3.fromRGB(255, 170, 60) },
})

local titles: { Title } = {
	{ Level = 1, Name = "Intern" },
	{ Level = 5, Name = "Junior Associate" },
	{ Level = 10, Name = "Associate" },
	{ Level = 20, Name = "Senior Associate" },
	{ Level = 30, Name = "Team Lead" },
	{ Level = 40, Name = "Manager" },
	{ Level = 50, Name = "Senior Manager" },
	{ Level = 60, Name = "Director" },
	{ Level = 75, Name = "Vice President" },
	{ Level = 100, Name = "Chief Calm Officer" },
}
for _, title in titles do
	table.freeze(title)
end

local LevelRewardConfig = table.freeze({
	-- Coins for reaching level L: CoinsPerLevel x L (Level 50 pays 1,000).
	CoinsPerLevel = 20,
	Titles = table.freeze(titles),
	Trails = trails,
	TrailsById = trailsById,
	Glows = glows,
	GlowsById = glowsById,
	-- The default Zen glow (MoodService) and the max-level name colour.
	DefaultGlowColor = Color3.fromRGB(255, 225, 120),
	MaxLevelColor = Color3.fromRGB(255, 200, 60),
})

return LevelRewardConfig
