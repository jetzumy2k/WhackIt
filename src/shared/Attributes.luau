--!strict
-- Names of server-written attributes that replicate to clients. The server is
-- the only writer; clients read them for display. See docs/REMOTE_CONTRACTS.md.

return table.freeze({
	-- On each boss Model under Workspace.Bosses
	BossInstanceId = "BossInstanceId",
	BossId = "BossId",
	Health = "Health",
	MaxHealth = "MaxHealth",
	Defeated = "Defeated",
	ShoutText = "ShoutText", -- latest speech-bubble line
	ShoutSeq = "ShoutSeq", -- increments on every shout, so repeats still show
	-- Admin-created (custom) bosses only: not in BossConfig, so the client reads
	-- the name and the look (a BossConfig id for model and colours) from here.
	BossName = "BossName",
	BossLook = "BossLook",
	-- Event bosses only (docs/EVENTS.md): true, so the label can say so.
	EventBoss = "EventBoss",

	-- On each Player
	Stress = "Stress",
	Level = "Level", -- Player Level, derived from XP
	ZenBuffEnds = "ZenBuffEnds", -- workspace:GetServerTimeNow() when the Zen buff ends (0 = none)
	-- Admin boss-access bypass is on for this player (display only: doors,
	-- labels; the server checks its own copy, BuffService.hasBossBypass).
	AdminBypass = "AdminBypass",
	-- The equipped pet (docs/PETS.md); unset = none. Every client draws it.
	PetSpecies = "PetSpecies",
	PetRarity = "PetRarity",
	-- Level reward looks in use (docs/GAMEPLAY_RULES.md "Level rewards"):
	-- LevelRewardConfig ids, "" = the default look. Only unlocked picks.
	TrailStyle = "TrailStyle",
	GlowStyle = "GlowStyle",

	-- On each incubator Model (Workspace.PetCenter.Incubators), docs/PETS.md
	IncubatorIndex = "IncubatorIndex",
	OwnerUserId = "OwnerUserId", -- 0 = empty
	OwnerName = "OwnerName",
	EggRarity = "EggRarity",
	EndsAt = "EndsAt", -- unix seconds the egg hatches
	HatchedSpecies = "HatchedSpecies", -- set for a few seconds while it hatches
	-- On each world egg Model (Workspace.PetCenter.WorldEggs)
	WorldEggRarity = "WorldEggRarity",

	-- On each hammer Tool (server-created); marks it as a hammer
	HammerId = "HammerId",
})
