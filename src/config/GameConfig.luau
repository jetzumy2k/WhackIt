--!strict

local GameConfig = {
	GameName = "Whack It Out!",
	Version = "0.1.0",

	-- Stress system
	MaxStress = 100,
	StartingStress = 100,

	-- Score
	StartingScore = 0,

	-- Combat
	HitCooldown = 0.25,
	DefaultHitDamage = 10,

	-- Round
	RoundDuration = 60,

	-- Player
	RespawnTime = 3,
}

return GameConfig
