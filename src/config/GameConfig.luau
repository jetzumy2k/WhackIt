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
	HitCooldownGrace = 0.05, -- seconds the server forgives for network jitter on HitCooldown
	HitReach = 12, -- studs from the player's root part to the boss centre

	-- Shared bosses (docs/GAMEPLAY_RULES.md)
	MinRewardDamageShare = 0.1, -- fraction of boss MaxHealth a player must deal to be rewarded
	BossRespawnDelay = 5, -- seconds from defeat until a fresh boss appears

	-- Player
	RespawnTime = 3, -- seconds
})

return GameConfig
