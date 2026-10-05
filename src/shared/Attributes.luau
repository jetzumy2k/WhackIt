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

	-- On each Player
	Stress = "Stress",

	-- On each hammer Tool (server-created); marks it as a hammer
	HammerId = "HammerId",
})
