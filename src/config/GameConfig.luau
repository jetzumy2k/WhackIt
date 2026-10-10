--!strict

local GameConfig = table.freeze({
	GameName = "Whack It Out!",

	-- Stress system (player's own meter; whacking relieves it, see docs/GAMEPLAY_RULES.md)
	MaxStress = 100,
	StartingStress = 100,
	-- Stress relieved per boss hit (rebalanced 2026-10-08): the equipped
	-- hammer's own damage x StressReliefPerDamage, at most StressReliefMaxPerHit.
	-- Crits, boosts, pets, events and level bonuses don't change it, so
	-- stronger characters no longer drain stress in a few seconds. Squeaky
	-- Hammer 1 per hit (~45 s from full to Zen of steady hitting); the best
	-- hammers 2.5 (~18 s).
	StressReliefPerDamage = 0.1,
	StressReliefMaxPerHit = 2.5,
	DefeatStressRelief = 5, -- bonus for each reward-qualifying player when a boss is defeated
	-- Stress creeps back when a player stops landing hits (docs/GAMEPLAY_RULES.md).
	-- Only a server-accepted boss hit restarts the grace period; walking, running,
	-- menus or swings that miss never do. Hit at 0 s -> rises at 20, 25, 30 s...
	StressIdleDelay = 15, -- grace: seconds after an accepted hit with no passive rise
	StressRegenInterval = 5, -- seconds between rises (the first comes one interval after the grace)
	StressRegenStep = 5, -- stress added per rise (clamped to MaxStress)
	-- Mood (face) bands: Zen at 0, then up to each threshold (inclusive).
	MoodRelaxedMax = 25,
	MoodNeutralMax = 50,
	MoodStressedMax = 75,

	-- Critical hits (rolled on the server for every accepted hit)
	BaseCritChance = 0.05, -- 5 % of hits are crits...
	BaseCritDamage = 0.5, -- ...and a crit does +50 % damage (more with hammer/boost bonuses)

	-- Zen buff: reaching 0 stress also powers you up for a while
	ZenBuffSeconds = 180,
	ZenBuffFlatDamage = 10, -- added to every hit
	ZenBuffCritChance = 0.05, -- added to crit chance

	-- Zen: reaching 0 stress
	ZenBonusCoins = 100,
	ZenCoinBonusPerLevel = 0.05, -- +5% boss coins per Zen Level...
	ZenCoinBonusMaxLevel = 10, -- ...counting at most this many levels (+50%)
	ZenRearmStress = 50, -- stress must climb back to this before the next Zen pays out

	-- Score and coins
	StartingScore = 0,
	StartingCoins = 0,

	-- Player Level (Shared/LevelRules, docs/GAMEPLAY_RULES.md "Player Level").
	-- Going from level L to L + 1 costs LevelScoreFactor x (2L - 1) XP, the old
	-- square curve; from LevelCurveStartsAt on, that cost is also multiplied by
	-- 1 + LevelCurveGrowth x (L - LevelCurveStartsAt + 1), so later levels are
	-- real goals (2026-10-09). Levels stop at MaxLevel; XP keeps counting.
	LevelScoreFactor = 600,
	LevelCurveStartsAt = 10,
	LevelCurveGrowth = 0.2,
	MaxLevel = 100,
	-- Character progression (docs/GAMEPLAY_RULES.md "Level bonuses"): every
	-- level above 1 adds LevelDamagePerLevel base damage up to
	-- LevelDamageSlowsAt, then LevelDamagePerLevelAfter per level (so hammers
	-- stay worth buying), plus LevelCritChancePerLevel crit CHANCE (0.0005 =
	-- 0.05 percentage points). Derived from the level, never stored.
	LevelDamagePerLevel = 3,
	LevelDamageSlowsAt = 10,
	LevelDamagePerLevelAfter = 1,
	LevelCritChancePerLevel = 0.0005,
	-- Senior bosses upstairs need at least this Player Level.
	UpstairsMinLevel = 10,
	-- Principal bosses (4th floor, Department Heads) and the floor itself need
	-- at least this Player Level (Phase 3a, decision D16).
	PrincipalMinLevel = 30,
	-- The CEO (3rd floor) has this many times the HP of the toughest other boss
	-- (37.5 x 2,400 = 90,000 HP).
	CeoHealthMultiplier = 37.5,
	-- XP earned per point of boss Score (before XP store boosts). Score itself,
	-- and so the leaderboard, is not affected.
	XpRewardMultiplier = 1.2,

	-- Movement (client-applied; the server's MovementGuard still caps speed).
	WalkSpeed = 16, -- Roblox default
	SprintSpeed = 26, -- hold Shift / L3 / the Sprint button
	SprintFieldOfView = 78, -- slight zoom-out while sprinting (default 70)

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
	-- Office boss buff drop chances: Config/DropRateConfig.

	-- Boss shouts (speech bubbles, BossShoutConfig)
	ShoutIdleMin = 8, -- seconds between a boss's idle shouts, at least...
	ShoutIdleMax = 15, -- ...and at most
	ShoutHitChance = 0.2, -- chance a hit makes the boss shout back
	ShoutCooldown = 4, -- seconds a boss stays quiet after any shout

	-- Player
	RespawnTime = 3, -- seconds
})

return GameConfig
