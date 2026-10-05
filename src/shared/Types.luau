--!strict
-- Shared domain and remote payload types. Data fields use PascalCase to match
-- config and saved data. Config definitions (BossDefinition, HammerDefinition)
-- are exported from their config modules.

-- Server-issued id for a spawned boss in the world (not a BossConfig id).
export type BossInstanceId = string

-- Combat.CombatFeedback (server -> client); see docs/REMOTE_CONTRACTS.md.
export type CombatFeedback = {
	BossInstanceId: BossInstanceId,
	Health: number,
	MaxHealth: number,
	Damage: number,
	HitterUserId: number,
	Defeated: boolean,
}

-- Combat.BossDefeated (server -> each contributing player).
export type BossDefeated = {
	BossInstanceId: BossInstanceId,
	BossId: string,
	Rewarded: boolean, -- false when the player's share was below MinRewardDamageShare
	ScoreAwarded: number,
	CoinsAwarded: number,
	StressRelieved: number,
	UnlockedBossIds: { string }, -- bosses this defeat newly unlocked for the player
	SharePercent: number, -- the player's share of the boss's HP, 0..100
	LastHit: boolean, -- the player landed the defeating hit (bonus included)
}

-- Mood.ZenAchieved (server -> all clients): a player reached 0 stress.
export type ZenAchieved = {
	UserId: number,
	DisplayName: string,
	ZenLevel: number,
	BonusCoins: number,
}

-- Profile.Sync (server -> one player): their own progression, for the UI only.
export type ProfileSnapshot = {
	Coins: number,
	OwnedHammerIds: { string },
	EquippedHammerId: string,
	BossDefeats: { [string]: number },
	UnlockedBossIds: { string },
	ZenLevel: number,
	Level: number, -- Player Level (Shared/LevelRules)
}

return {}
