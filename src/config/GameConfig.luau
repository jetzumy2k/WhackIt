--!strict

local GameConfig = table.freeze({
	GameName = "Whack It Out!",

	-- Stress system
	MaxStress = 100,
	StartingStress = 100,

	-- Score
	StartingScore = 0,

	-- Combat
	HitCooldown = 0.25, -- seconds between accepted hits per player
	DefaultHammerId = "squeaky_hammer", -- must exist in HammerConfig
	MinHitDamage = 1, -- every accepted hit does at least this much

	-- Player
	RespawnTime = 3, -- seconds
})

return GameConfig
