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

	-- On each Player
	Stress = "Stress",
	Level = "Level", -- Player Level, derived from XP
	ZenBuffEnds = "ZenBuffEnds", -- workspace:GetServerTimeNow() when the Zen buff ends (0 = none)

	-- On each hammer Tool (server-created); marks it as a hammer
	HammerId = "HammerId",
})
