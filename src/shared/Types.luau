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
	Crit: boolean, -- a critical hit (bigger damage number)
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
	BossName: string, -- display name (custom bosses aren't in BossConfig)
	BuffDropText: string?, -- custom bosses: the store boost this player got
	AdminDamage: boolean, -- the player hit with admin-set damage, so got no reward
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
	Level: number, -- Player Level (Shared/LevelRules), from Xp
	Xp: number,
	-- Active store buffs: kind ("Xp" | "Damage" | "CritDamage") -> percent and play-time left.
	Buffs: { [string]: { Percent: number, SecondsLeft: number } },
	-- Owned Mystery Hammers with their rolled stats.
	MysteryHammers: { { Id: string, Damage: number, CritDamagePercent: number } },
	-- Bosses an admin unlocked for this player.
	AdminUnlocks: { string },
	-- Unused store items by product key (Shared/BagRules).
	Bag: { [string]: number },
}

return {}
