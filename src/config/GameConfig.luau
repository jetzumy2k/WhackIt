--!strict

local GameConfig = table.freeze({
	GameName = "Whack It Out!",

	-- Stress system (player's own meter; whacking relieves it, see docs/GAMEPLAY_RULES.md)
	MaxStress = 100,
	StartingStress = 100,
	StressReliefPerDamage = 0.1, -- stress relieved per point of accepted damage
	DefeatStressRelief = 5, -- bonus for each reward-qualifying player when a boss is defeated

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
