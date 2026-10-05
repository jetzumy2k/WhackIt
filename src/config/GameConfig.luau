--!strict

local GameConfig = table.freeze({
	GameName = "Whack It Out!",

	-- Stress system (player's own meter; whacking relieves it, see docs/GAMEPLAY_RULES.md)
	MaxStress = 100,
	StartingStress = 100,
	StressReliefPerDamage = 0.1, -- stress relieved per point of accepted damage
	DefeatStressRelief = 5, -- bonus for each reward-qualifying player when a boss is defeated
	-- Stress creeps back when a player stops landing hits (docs/GAMEPLAY_RULES.md).
	StressIdleDelay = 120, -- seconds without an accepted hit before stress starts rising
	StressRegenInterval = 5, -- seconds between rises once idle
	StressRegenStep = 5, -- stress added per rise
	-- Mood (face) bands: Zen at 0, then up to each threshold (inclusive).
	MoodRelaxedMax = 25,
	MoodNeutralMax = 50,
	MoodStressedMax = 75,

	-- Zen: reaching 0 stress
	ZenBonusCoins = 100,
	ZenCoinBonusPerLevel = 0.05, -- +5% boss coins per Zen Level...
	ZenCoinBonusMaxLevel = 10, -- ...counting at most this many levels (+50%)
	ZenRearmStress = 50, -- stress must climb back to this before the next Zen pays out

	-- Score and coins
	StartingScore = 0,
	StartingCoins = 0,

	-- Player Level (Shared/LevelRules): level = floor(sqrt(score / factor)) + 1
	LevelScoreFactor = 600,
	-- Senior bosses upstairs need at least this Player Level.
	UpstairsMinLevel = 10,

	-- Combat
	HitCooldown = 0.45, -- seconds per hammer swing = minimum time between accepted hits
	DefaultHammerId = "squeaky_hammer", -- must exist in HammerConfig
	MinHitDamage = 1, -- every accepted hit does at least this much
	HitCooldownGrace = 0.05, -- seconds the server forgives for network jitter on HitCooldown
	-- Studs from the player's root part to the boss centre. Matches how far the swung
	-- hammer visibly reaches (arm + handle ~5 studs past a 3-stud boss radius).
	HitReach = 9,
	-- Extra studs the server allows on reach for network lag; the client uses HitReach exactly.
	HitReachGrace = 1.5,

	-- Shared bosses (docs/GAMEPLAY_RULES.md)
	-- Score and coins are split by each player's share of the boss's HP; this share is
	-- needed for the defeat to count (unlocks) and for the stress bonus.
	MinRewardDamageShare = 0.1,
	LastHitBonusShare = 0.05, -- extra fraction of the boss's reward for the defeating hit
	BossRespawnDelay = 5, -- seconds from defeat until a fresh boss appears

	-- Player
	RespawnTime = 3, -- seconds
})

return GameConfig
