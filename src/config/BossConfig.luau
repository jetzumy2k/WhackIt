--!strict

export type BossDefinition = {
	Id: string,
	DisplayName: string,
	Description: string,
	MaxHealth: number,
	HitDamage: number,
	ScoreReward: number,
}

local BossConfig: { BossDefinition } = {
	{
		Id = "deadline_boss",
		DisplayName = "Deadline Boss",
		Description = "That deadline that somehow became your problem.",
		MaxHealth = 100,
		HitDamage = 10,
		ScoreReward = 100,
	},

	{
		Id = "meeting_master",
		DisplayName = "Meeting Master",
		Description = "A meeting that could have been an email.",
		MaxHealth = 120,
		HitDamage = 8,
		ScoreReward = 120,
	},

	{
		Id = "reply_all_boss",
		DisplayName = "Reply-All Boss",
		Description = "Someone replied to everyone... again.",
		MaxHealth = 80,
		HitDamage = 12,
		ScoreReward = 150,
	},

	{
		Id = "production_bug",
		DisplayName = "Production Bug",
		Description = "It worked perfectly in development.",
		MaxHealth = 150,
		HitDamage = 15,
		ScoreReward = 200,
	},

	{
		Id = "monday_monster",
		DisplayName = "Monday Monster",
		Description = "Monday has entered the building.",
		MaxHealth = 200,
		HitDamage = 20,
		ScoreReward = 300,
	},
}

return BossConfig
