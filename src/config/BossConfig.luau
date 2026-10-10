--!strict
-- Boss definitions. List order is the display order; ById is for lookups.
-- DamageTakenMultiplier scales hammer damage (see docs/GAMEPLAY_RULES.md).
-- Unlocking (Shared/ProgressionRules): a boss with UnlockAfterBossId needs
-- UnlockDefeats rewarded defeats of that boss, and MinLevel Player Level if set.
-- Ground-floor bosses chain one after another; Senior bosses (upstairs) need
-- GameConfig.UpstairsMinLevel and one defeat of their ground-floor version.
--
-- Difficulty rises down the list: each boss has more MaxHealth AND more
-- effective HP (MaxHealth / DamageTakenMultiplier, i.e. hammer damage needed)
-- than the one before it. BossConfig.spec checks this, so keep it true when
-- tuning.

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
	-- Unlocks only once every other boss has been defeated at least once (the CEO).
	UnlockAfterAllBosses: boolean?,
	-- Admin-created bosses only (Shared/CustomBossRules): never in List/ById.
	Custom: boolean?,
	-- Event bosses only (Shared/EventRules): also Custom; they drop store
	-- boosts by the normal office chance, not always like custom bosses.
	Event: boolean?,
	-- Team mission bosses only (Shared/MissionRules): also Custom; they drop
	-- store boosts by the normal office chance, and only the team may hit them.
	Mission: boolean?,
	LookId: string?, -- the BossConfig boss whose model, colours and shouts it borrows
}

export type BossConfig = {
	List: { BossDefinition },
	ById: { [string]: BossDefinition },
}

-- Senior bosses live upstairs, for experienced players (GameConfig.UpstairsMinLevel):
-- all tougher than any ground-floor boss, and paying more than their ground version.
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
		MaxHealth = 140,
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
		MaxHealth = 240,
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
		MaxHealth = 360,
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
		MaxHealth = 560,
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
		MaxHealth = 600,
		DamageTakenMultiplier = 1.0,
		ScoreReward = 550,
		CoinReward = 55,
		UnlockAfterBossId = "deadline_boss",
		UnlockDefeats = 1,
		MinLevel = SENIOR_MIN_LEVEL,
	},

	{
		Id = "senior_meeting_master",
		DisplayName = "Senior Meeting Master",
		Description = "Schedules meetings about meetings.",
		MaxHealth = 640,
		DamageTakenMultiplier = 0.8,
		ScoreReward = 700,
		CoinReward = 70,
		UnlockAfterBossId = "meeting_master",
		UnlockDefeats = 1,
		MinLevel = SENIOR_MIN_LEVEL,
	},

	{
		Id = "senior_reply_all_boss",
		DisplayName = "Senior Reply-All Boss",
		Description = "CCs the entire company on every thought.",
		MaxHealth = 1080,
		DamageTakenMultiplier = 1.2,
		ScoreReward = 850,
		CoinReward = 90,
		UnlockAfterBossId = "reply_all_boss",
		UnlockDefeats = 1,
		MinLevel = SENIOR_MIN_LEVEL,
	},

	{
		Id = "senior_production_bug",
		DisplayName = "Senior Production Bug",
		Description = "Only appears on Friday at 4:59 PM.",
		MaxHealth = 1500,
		DamageTakenMultiplier = 1.5,
		ScoreReward = 1000,
		CoinReward = 120,
		UnlockAfterBossId = "production_bug",
		UnlockDefeats = 1,
		MinLevel = SENIOR_MIN_LEVEL,
	},

	{
		Id = "senior_monday_monster",
		DisplayName = "Senior Monday Monster",
		Description = "Every day is Monday now.",
		MaxHealth = 2400,
		DamageTakenMultiplier = 2.0,
		ScoreReward = 1300,
		CoinReward = 170,
		UnlockAfterBossId = "monday_monster",
		UnlockDefeats = 1,
		MinLevel = SENIOR_MIN_LEVEL,
	},
}

-- The CEO (3rd-floor raid boss): HP is CeoHealthMultiplier x the toughest
-- other boss, derived so it stays true when other bosses change. A team effort.
local toughest = 0
for _, boss in list do
	toughest = math.max(toughest, boss.MaxHealth)
end
table.insert(list, {
	Id = "the_ceo",
	DisplayName = "The CEO",
	Description = "Has never once read the whole email.",
	MaxHealth = toughest * GameConfig.CeoHealthMultiplier,
	DamageTakenMultiplier = 1.0,
	ScoreReward = 5000,
	CoinReward = 1000,
	UnlockDefeats = 0,
	MinLevel = SENIOR_MIN_LEVEL,
	UnlockAfterAllBosses = true,
})

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
