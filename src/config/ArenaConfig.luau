--!strict
--[[
	The office building: one office per boss along a corridor, with the lobby
	(and player spawn) south of the corridor. North is -Z.

	  Ground floor (Y = 0):  five offices, corridor, lobby with the spawn
	  Upper floor (Y = 15):  five Senior offices directly above, reached by
	                         stairs along the lobby's east wall; the lobby is
	                         a double-height atrium open to the upper corridor
	  Executive floor (Y = 30): the CEO's suite over the offices and corridor,
	                         reached only by the Executive Elevator at the west
	                         end of the upper corridor (server-checked access)

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
	Size: Vector3, -- server hitbox size
	FloorY: number, -- top of the floor the boss stands on
}

local BossVisualConfig = require(script.Parent.BossVisualConfig)

local OFFICE_Z = -36
local BASE_BOSS_SIZE = Vector3.new(6, 8, 6)
-- Top of the executive (3rd) floor: the old roof slab now carries it.
local EXECUTIVE_FLOOR_Y = 30
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

-- A boss's hitbox grows with its visual Scale, and it stands on its floor.
local function bossSpawn(bossId: string, floorCenter: Vector3, offset: Vector3): BossSpawn
	local look = BossVisualConfig[bossId]
	local scale = if look then look.Scale else 1
	local size = BASE_BOSS_SIZE * scale
	return table.freeze({
		BossId = bossId,
		Position = floorCenter + Vector3.new(offset.X, size.Y / 2, offset.Z),
		Size = size,
		FloorY = floorCenter.Y,
	}) :: BossSpawn
end

local spawns: { BossSpawn } = {}
for _, entry in offices do
	table.insert(spawns, bossSpawn(entry.BossId, entry.Center, BOSS_OFFSET))
end
-- The CEO stands in the middle of the executive floor.
local CEO_FLOOR_CENTER = Vector3.new(0, EXECUTIVE_FLOOR_Y, -26)
table.insert(spawns, bossSpawn("the_ceo", CEO_FLOOR_CENTER, Vector3.zero))

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
	RoofY = 29, -- underside of the 2nd-floor ceiling (upper walls are 14 tall)

	-- Executive (3rd) floor: the CEO's suite over the offices and corridor.
	Executive = table.freeze({
		FloorY = EXECUTIVE_FLOOR_Y,
		CeilingY = EXECUTIVE_FLOOR_Y + 14,
		NorthZ = -52,
		SouthZ = 0,
		CeoBossId = "the_ceo",
		CeoFloorCenter = CEO_FLOOR_CENTER,
		-- Elevator doors in the west end wall, one per floor, and where riders step out.
		ElevatorUpDoor = Vector3.new(-85, UPPER_FLOOR_Y + 4, -10),
		ElevatorDownDoor = Vector3.new(-85, EXECUTIVE_FLOOR_Y + 4, -10),
		ArriveUp = Vector3.new(-78, EXECUTIVE_FLOOR_Y + 3, -10),
		ArriveDown = Vector3.new(-78, UPPER_FLOOR_Y + 3, -10),
	}),

	-- Lobby spawn (matches Workspace.Arena.SpawnLocation in default.project.json).
	SpawnPosition = Vector3.new(0, 0.5, 20),

	PlaceholderBossSize = Vector3.new(6, 8, 6),
	PlaceholderBossColor = Color3.fromRGB(255, 120, 60),
})

return ArenaConfig
