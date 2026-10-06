--!strict
-- Limits for bosses created in the Admin panel (docs/ADMIN.md). The server
-- enforces them (Shared/CustomBossRules); the panel shows them as hints.

local CustomBossConfig = table.freeze({
	-- Custom boss ids are "custom_<n>"; BossConfig ids must never use this prefix.
	IdPrefix = "custom_",
	MaxBosses = 20, -- across all servers

	NameMaxLength = 30,
	MinHealth = 10,
	MaxHealth = 1000000,
	MaxScoreReward = 10000,
	MaxCoinReward = 2000,

	-- Looks an admin can pick: the boss whose model, colours and shouts it
	-- borrows. The CEO is left out because its model is scaled up for the suite.
	LookIds = table.freeze({
		"deadline_boss",
		"meeting_master",
		"reply_all_boss",
		"production_bug",
		"monday_monster",
		"senior_deadline_boss",
		"senior_meeting_master",
		"senior_reply_all_boss",
		"senior_production_bug",
		"senior_monday_monster",
	}),

	-- Server hitbox, same as an office boss.
	Size = Vector3.new(6, 8, 6),
	-- A new boss must be at least this far from every other boss, so one swing
	-- can only ever reach one boss (GameConfig.HitReach + HitReachGrace = 10.5).
	MinSpacing = 14,

	-- Each reward-qualifying player gets one random 30-minute store boost.
	BuffDropSeconds = 30 * 60,
})

return CustomBossConfig
