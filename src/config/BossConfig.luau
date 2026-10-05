--!strict
-- Boss definitions. List order is the display AND unlock order; ById is for lookups.
-- DamageTakenMultiplier scales hammer damage (see docs/GAMEPLAY_RULES.md).
-- UnlockDefeats: rewarded defeats of the PREVIOUS boss in List needed to unlock
-- this one (0 for the first boss).

export type BossDefinition = {
	Id: string,
	DisplayName: string,
	Description: string,
	MaxHealth: number,
	DamageTakenMultiplier: number,
	ScoreReward: number,
	CoinReward: number,
	UnlockDefeats: number,
}

export type BossConfig = {
	List: { BossDefinition },
	ById: { [string]: BossDefinition },
}

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
		UnlockDefeats = 3,
	},

	{
		Id = "reply_all_boss",
		DisplayName = "Reply-All Boss",
		Description = "Someone replied to everyone... again.",
		MaxHealth = 80,
		DamageTakenMultiplier = 1.2,
		ScoreReward = 150,
		CoinReward = 20,
		UnlockDefeats = 3,
	},

	{
		Id = "production_bug",
		DisplayName = "Production Bug",
		Description = "It worked perfectly in development.",
		MaxHealth = 150,
		DamageTakenMultiplier = 1.5,
		ScoreReward = 200,
		CoinReward = 30,
		UnlockDefeats = 3,
	},

	{
		Id = "monday_monster",
		DisplayName = "Monday Monster",
		Description = "Monday has entered the building.",
		MaxHealth = 200,
		DamageTakenMultiplier = 2.0,
		ScoreReward = 300,
		CoinReward = 50,
		UnlockDefeats = 3,
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
