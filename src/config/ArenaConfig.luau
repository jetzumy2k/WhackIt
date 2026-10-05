--!strict
-- Boss stations and the server hitbox size. Positions match the Arena floor in
-- default.project.json (floor top at Y = 0); the player spawn is at Z = +10.
-- Stations are 20 studs apart, more than twice GameConfig.HitReach, so a swing
-- can only ever reach one boss.

export type BossSpawn = {
	BossId: string, -- must exist in BossConfig
	Position: Vector3, -- centre of the boss body
}

local function station(bossId: string, x: number, z: number): BossSpawn
	return table.freeze({ BossId = bossId, Position = Vector3.new(x, 4, z) }) :: BossSpawn
end

local ArenaConfig = table.freeze({
	-- A shallow arc facing the spawn, in unlock order from left to right.
	BossSpawns = table.freeze({
		station("deadline_boss", -40, -24),
		station("meeting_master", -20, -30),
		station("reply_all_boss", 0, -32),
		station("production_bug", 20, -30),
		station("monday_monster", 40, -24),
	}),

	PlaceholderBossSize = Vector3.new(6, 8, 6),
	PlaceholderBossColor = Color3.fromRGB(255, 120, 60),
})

return ArenaConfig
