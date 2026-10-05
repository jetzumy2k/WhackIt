--!strict
--[[
	The office floor: one office per boss along a corridor, with the lobby (and
	player spawn) south of the corridor. Floor top is Y = 0; north is -Z.

	  z -52 .. -20  five offices (doors face the corridor, +Z)
	  z -20 ..   0  corridor
	  z   0 ..  34  lobby, spawn at Z = +20 (default.project.json)

	Office centres are 34 studs apart (more than twice GameConfig.HitReach plus
	its lag grace), so a swing can only ever reach one boss. The building itself
	is built from these numbers by Lib/OfficeBuilder.
]]

export type Office = {
	BossId: string, -- must exist in BossConfig
	Center: Vector3, -- centre of the office floor (Y = 0)
	CarpetColor: Color3,
	ScreenText: string, -- joke on the desk monitor
	PosterText: string, -- joke on the wall poster
}

export type BossSpawn = {
	BossId: string,
	Position: Vector3, -- centre of the boss body
}

local OFFICE_Z = -36
-- Bosses stand a little behind the room centre, leaving space to walk around them.
local BOSS_OFFSET = Vector3.new(0, 4, -2)

local function office(
	bossId: string,
	x: number,
	carpet: Color3,
	screen: string,
	poster: string
): Office
	return table.freeze({
		BossId = bossId,
		Center = Vector3.new(x, 0, OFFICE_Z),
		CarpetColor = carpet,
		ScreenText = screen,
		PosterText = poster,
	}) :: Office
end

local offices: { Office } = {
	office("deadline_boss", -68, Color3.fromRGB(196, 150, 120), "DUE: 5 MIN AGO", "Time flies!"),
	office("meeting_master", -34, Color3.fromRGB(165, 150, 196), "MEETING IN 1 MIN", "Synergy!"),
	office("reply_all_boss", 0, Color3.fromRGB(140, 170, 205), "INBOX: 9,999", "Per my last email"),
	office("production_bug", 34, Color3.fromRGB(150, 190, 140), "ERROR 500", "Works on my machine"),
	office("monday_monster", 68, Color3.fromRGB(160, 165, 180), "MON 9:00 AM", "Is it Friday yet?"),
}

local spawns: { BossSpawn } = {}
for _, entry in offices do
	table.insert(
		spawns,
		table.freeze({ BossId = entry.BossId, Position = entry.Center + BOSS_OFFSET }) :: BossSpawn
	)
end

local ArenaConfig = table.freeze({
	Offices = table.freeze(offices),
	BossSpawns = table.freeze(spawns),

	-- Each office: width (X), wall height (Y), depth (Z).
	OfficeSize = Vector3.new(32, 14, 32),
	DoorWidth = 10,
	DoorHeight = 10,

	-- Lobby spawn (matches Workspace.Arena.SpawnLocation in default.project.json).
	SpawnPosition = Vector3.new(0, 0.5, 20),

	PlaceholderBossSize = Vector3.new(6, 8, 6),
	PlaceholderBossColor = Color3.fromRGB(255, 120, 60),
})

return ArenaConfig
