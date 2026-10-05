--!strict
-- Where bosses spawn and how the placeholder boss looks until real art exists.
-- Positions match the Arena floor in default.project.json (floor top at Y = 0).

export type BossSpawn = {
	BossId: string, -- must exist in BossConfig
	Position: Vector3, -- centre of the boss body
}

local ArenaConfig = table.freeze({
	BossSpawns = table.freeze({
		table.freeze({
			BossId = "deadline_boss",
			Position = Vector3.new(0, 4, -20),
		}) :: BossSpawn,
	}),

	PlaceholderBossSize = Vector3.new(6, 8, 6),
	PlaceholderBossColor = Color3.fromRGB(255, 120, 60),
})

return ArenaConfig
