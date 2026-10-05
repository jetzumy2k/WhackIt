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

return {}
