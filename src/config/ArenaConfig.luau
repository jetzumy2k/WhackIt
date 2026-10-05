--!strict
--[[
	The office building: one office per boss along a corridor, with the lobby
	(and player spawn) south of the corridor. North is -Z.

	  Ground floor (Y = 0):  five offices, corridor, lobby with the spawn
	  Upper floor (Y = 15):  five Senior offices directly above, reached by
	                         stairs along the lobby's east wall; the lobby is
	                         a double-height atrium open to the upper corridor

	  z -52 .. -20  offices (doors face the corridor, +Z)
	  z -20 ..   0  corridor
	  z   0 ..  34  lobby, spawn at Z = +20 (default.project.json)

	Office centres on a floor are 34 studs apart and floors 15 studs apart,
	more than GameConfig.HitReach plus its lag grace, so a swing can only ever
	reach one boss. Lib/OfficeBuilder builds the building from these numbers.
]]

export type Office = {
	BossId: string, -- must exist in BossConfig
	Center: Vector3, -- centre of the office floor (Y = floor top)
	CarpetColor: Color3,
	ScreenText: string, -- joke on the desk monitor
	PosterText: string, -- joke on the wall poster
}

export type BossSpawn = {
	BossId: string,
	Position: Vector3, -- centre of the boss body
}

local OFFICE_Z = -36
-- Floor top of the upper storey (ground walls are 14 tall, plus a 1-stud slab).
local UPPER_FLOOR_Y = 15
-- Bosses stand a little behind the room centre, leaving space to walk around them.
local BOSS_OFFSET = Vector3.new(0, 4, -2)

local function office(
	bossId: string,
	x: number,
	floorY: number,
	carpet: Color3,
	screen: string,
	poster: string
): Office
	return table.freeze({
		BossId = bossId,
		Center = Vector3.new(x, floorY, OFFICE_Z),
		CarpetColor = carpet,
		ScreenText = screen,
		PosterText = poster,
	}) :: Office
end

local offices: { Office } = {
	office("deadline_boss", -68, 0, Color3.fromRGB(196, 150, 120), "DUE: 5 MIN AGO", "Time flies!"),
	office("meeting_master", -34, 0, Color3.fromRGB(165, 150, 196), "MEETING IN 1 MIN", "Synergy!"),
	office(
		"reply_all_boss",
		0,
		0,
		Color3.fromRGB(140, 170, 205),
		"INBOX: 9,999",
		"Per my last email"
	),
	office(
		"production_bug",
		34,
		0,
		Color3.fromRGB(150, 190, 140),
		"ERROR 500",
		"Works on my machine"
	),
	office(
		"monday_monster",
		68,
		0,
		Color3.fromRGB(160, 165, 180),
		"MON 9:00 AM",
		"Is it Friday yet?"
	),

	-- Upper floor: Senior offices directly above their ground-floor versions.
	office(
		"senior_deadline_boss",
		-68,
		UPPER_FLOOR_Y,
		Color3.fromRGB(170, 110, 85),
		"DUE: YESTERDAY",
		"Deadlines!"
	),
	office(
		"senior_meeting_master",
		-34,
		UPPER_FLOOR_Y,
		Color3.fromRGB(130, 110, 175),
		"7 MEETINGS TODAY",
		"Let's circle back"
	),
	office(
		"senior_reply_all_boss",
		0,
		UPPER_FLOOR_Y,
		Color3.fromRGB(100, 140, 190),
		"INBOX: 99,999",
		"Reply-all forever"
	),
	office(
		"senior_production_bug",
		34,
		UPPER_FLOOR_Y,
		Color3.fromRGB(110, 160, 100),
		"PROD IS DOWN",
		"Ship it on Friday"
	),
	office(
		"senior_monday_monster",
		68,
		UPPER_FLOOR_Y,
		Color3.fromRGB(120, 125, 150),
		"MON 8:00 AM",
		"Mondays never end"
	),
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
	UpperFloorY = UPPER_FLOOR_Y,

	-- Straight stairs along the lobby's east wall, from the lobby floor (south
	-- end) up to the upper corridor (north end): one 1-stud step every 2 studs.
	Stairs = table.freeze({
		X = 32, -- centre line
		Width = 6,
		BottomZ = 32, -- first step starts here and climbs toward -Z
		StepDepth = 2,
		StepHeight = 1,
	}),

	-- Building footprint (roof, exterior and outdoor surroundings).
	BuildingHalfWidth = 86,
	BuildingNorthZ = -52,
	BuildingSouthZ = 34,
	RoofY = 29, -- underside of the roof (upper walls are 14 tall)

	-- Lobby spawn (matches Workspace.Arena.SpawnLocation in default.project.json).
	SpawnPosition = Vector3.new(0, 0.5, 20),

	PlaceholderBossSize = Vector3.new(6, 8, 6),
	PlaceholderBossColor = Color3.fromRGB(255, 120, 60),
})

return ArenaConfig
