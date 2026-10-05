--!strict
-- Boss definitions. List order is the display order; ById is for lookups.
-- DamageTakenMultiplier scales hammer damage (see docs/GAMEPLAY_RULES.md).
-- Unlocking (Shared/ProgressionRules): a boss with UnlockAfterBossId needs
-- UnlockDefeats rewarded defeats of that boss, and MinLevel Player Level if set.
-- Ground-floor bosses chain one after another; Senior bosses (upstairs) need
-- GameConfig.UpstairsMinLevel and one defeat of their ground-floor version.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)

export type BossDefinition = {
	Id: string,
	DisplayName: string,
	Description: string,
	MaxHealth: number,
	DamageTakenMultiplier: number,
	ScoreReward: number,
	CoinReward: number,
	UnlockAfterBossId: string?,
	UnlockDefeats: number,
	MinLevel: number?,
}

export type BossConfig = {
	List: { BossDefinition },
	ById: { [string]: BossDefinition },
}

-- Senior bosses live upstairs: three times the HP and rewards of their
-- ground-floor version, for experienced players (GameConfig.UpstairsMinLevel).
local SENIOR_MIN_LEVEL = GameConfig.UpstairsMinLevel

local list: { BossDefinition } = {
	{
		Id = "deadline_boss",
		DisplayName = "Deadline Boss",
		Description = "That deadline that somehow became your problem.",
		MaxHealth = 100,
		DamageTakenMultiplier = 1.0,
		ScoreReward = 100,
		CoinReward = 10,
		UnlockDefeats = 0,
	},

	{
		Id = "meeting_master",
		DisplayName = "Meeting Master",
		Description = "A meeting that could have been an email.",
		MaxHealth = 120,
		DamageTakenMultiplier = 0.8,
		ScoreReward = 120,
		CoinReward = 15,
		UnlockAfterBossId = "deadline_boss",
		UnlockDefeats = 1,
	},

	{
		Id = "reply_all_boss",
		DisplayName = "Reply-All Boss",
		Description = "Someone replied to everyone... again.",
		MaxHealth = 80,
		DamageTakenMultiplier = 1.2,
		ScoreReward = 150,
		CoinReward = 20,
		UnlockAfterBossId = "meeting_master",
		UnlockDefeats = 1,
	},

	{
		Id = "production_bug",
		DisplayName = "Production Bug",
		Description = "It worked perfectly in development.",
		MaxHealth = 150,
		DamageTakenMultiplier = 1.5,
		ScoreReward = 200,
		CoinReward = 30,
		UnlockAfterBossId = "reply_all_boss",
		UnlockDefeats = 1,
	},

	{
		Id = "monday_monster",
		DisplayName = "Monday Monster",
		Description = "Monday has entered the building.",
		MaxHealth = 200,
		DamageTakenMultiplier = 2.0,
		ScoreReward = 300,
		CoinReward = 50,
		UnlockAfterBossId = "production_bug",
		UnlockDefeats = 1,
	},

	{
		Id = "senior_deadline_boss",
		DisplayName = "Senior Deadline Boss",
		Description = "The deadline moved up. To yesterday.",
		MaxHealth = 300,
		DamageTakenMultiplier = 1.0,
		ScoreReward = 300,
		CoinReward = 30,
		UnlockAfterBossId = "deadline_boss",
		UnlockDefeats = 1,
		MinLevel = SENIOR_MIN_LEVEL,
	},

	{
		Id = "senior_meeting_master",
		DisplayName = "Senior Meeting Master",
		Description = "Schedules meetings about meetings.",
		MaxHealth = 360,
		DamageTakenMultiplier = 0.8,
		ScoreReward = 360,
		CoinReward = 45,
		UnlockAfterBossId = "meeting_master",
		UnlockDefeats = 1,
		MinLevel = SENIOR_MIN_LEVEL,
	},

	{
		Id = "senior_reply_all_boss",
		DisplayName = "Senior Reply-All Boss",
		Description = "CCs the entire company on every thought.",
		MaxHealth = 240,
		DamageTakenMultiplier = 1.2,
		ScoreReward = 450,
		CoinReward = 60,
		UnlockAfterBossId = "reply_all_boss",
		UnlockDefeats = 1,
		MinLevel = SENIOR_MIN_LEVEL,
	},

	{
		Id = "senior_production_bug",
		DisplayName = "Senior Production Bug",
		Description = "Only appears on Friday at 4:59 PM.",
		MaxHealth = 450,
		DamageTakenMultiplier = 1.5,
		ScoreReward = 600,
		CoinReward = 90,
		UnlockAfterBossId = "production_bug",
		UnlockDefeats = 1,
		MinLevel = SENIOR_MIN_LEVEL,
	},

	{
		Id = "senior_monday_monster",
		DisplayName = "Senior Monday Monster",
		Description = "Every day is Monday now.",
		MaxHealth = 600,
		DamageTakenMultiplier = 2.0,
		ScoreReward = 900,
		CoinReward = 150,
		UnlockAfterBossId = "monday_monster",
		UnlockDefeats = 1,
		MinLevel = SENIOR_MIN_LEVEL,
	},
}

local byId: { [string]: BossDefinition } = {}
for _, boss in list do
	if byId[boss.Id] then
		error(string.format("[BossConfig] duplicate boss id %q", boss.Id))
	end
	byId[boss.Id] = table.freeze(boss)
end

local BossConfig: BossConfig = table.freeze({
	List = table.freeze(list),
	ById = table.freeze(byId),
})

return BossConfig
