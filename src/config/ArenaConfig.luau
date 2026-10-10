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
	  z  34 .. 150  outdoor campus through the lobby entrance (Campus below),
	                walled in at x +-130, z -210 .. 150
	  z -200 .. -140 the Recreation Center behind the building (pickleball,
	                Config/PickleballConfig, Lib/CourtBuilder), reached by a
	                walkway from the loop around the building

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
-- 4th floor (Department Heads, Phase 3a): on the Executive Floor's roof slab
-- (its ceiling is 14 above its floor, plus a 1-stud slab).
local DEPARTMENT_FLOOR_Y = EXECUTIVE_FLOOR_Y + 15
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

	-- 4th floor (Department Heads): Principal offices over the CEO's suite,
	-- in the same columns as the floors below.
	office(
		"principal_deadline_boss",
		-68,
		DEPARTMENT_FLOOR_Y,
		Color3.fromRGB(140, 85, 65),
		"DUE: -1 DAYS",
		"Ahead of schedule? Never."
	),
	office(
		"principal_meeting_master",
		-34,
		DEPARTMENT_FLOOR_Y,
		Color3.fromRGB(110, 90, 150),
		"MEETINGS: 24/7",
		"Per our sync"
	),
	office(
		"principal_reply_all_boss",
		0,
		DEPARTMENT_FLOOR_Y,
		Color3.fromRGB(80, 115, 165),
		"INBOX: INFINITE",
		"Looping in everyone"
	),
	office(
		"principal_production_bug",
		34,
		DEPARTMENT_FLOOR_Y,
		Color3.fromRGB(90, 135, 85),
		"UPTIME: 3%",
		"It's a feature"
	),
	office(
		"principal_monday_monster",
		68,
		DEPARTMENT_FLOOR_Y,
		Color3.fromRGB(100, 105, 130),
		"MON MON MON",
		"Weekend? Never heard of it"
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
	-- 4th floor (Department Heads): offices along the north half, the corridor
	-- south of them, both over the Executive Floor's footprint.
	DepartmentFloor = table.freeze({
		FloorY = DEPARTMENT_FLOOR_Y,
		CeilingY = DEPARTMENT_FLOOR_Y + 14,
		NorthZ = -52,
		SouthZ = 0,
	}),

	-- The tower elevator (Phase 3a, docs/TOWER.md): one shaft at the corridor's
	-- west end with a door on every floor; each door opens the floor panel
	-- (TowerService checks every ride). Floors in order, bottom first.
	Tower = table.freeze({
		DoorX = -85,
		DoorZ = -10,
		ArriveX = -78,
		-- The 2nd and 3rd floor doors keep their old names (ElevatorUpDoor,
		-- ElevatorDownDoor). Text is what the floor panel says about the floor.
		Floors = table.freeze({
			table.freeze({
				Id = "Ground",
				Number = 1,
				Name = "Lobby & Offices",
				Text = "The lobby, the Hall of Calm and 5 office bosses",
				FloorY = 0,
				DoorName = "ElevatorGroundDoor",
			}),
			table.freeze({
				Id = "Senior",
				Number = 2,
				Name = "Senior Floor",
				Text = "5 Senior bosses (Level 10+)",
				FloorY = UPPER_FLOOR_Y,
				DoorName = "ElevatorUpDoor",
			}),
			table.freeze({
				Id = "Executive",
				Number = 3,
				Name = "Executive Floor",
				Text = "The CEO's suite. Stress level: MAXIMUM",
				FloorY = EXECUTIVE_FLOOR_Y,
				DoorName = "ElevatorDownDoor",
			}),
			table.freeze({
				Id = "Department",
				Number = 4,
				Name = "Department Heads",
				Text = "5 Principal bosses (Level 30+)",
				FloorY = DEPARTMENT_FLOOR_Y,
				DoorName = "ElevatorDepartmentDoor",
			}),
		}),
	}),

	-- Straight stairs along the lobby's east wall, from the lobby floor (south
	-- end) up to the upper corridor (north end): one 1-stud step every 2 studs.
	Stairs = table.freeze({
		X = 32, -- centre line
		Width = 6,
		-- First step starts here and climbs toward -Z. Leaves open floor between the
		-- foot of the stairs and the lobby's front wall (BuildingSouthZ) to walk on.
		BottomZ = 24,
		StepDepth = 1.5,
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

	-- Hammer vending machine (Lib/StoreMachineBuilder, 2026-10-07): beside the
	-- stairs' open (west) side, facing into the lobby (-X). Clear of the
	-- landing in front of the bottom step, the walk from the spawn to it and
	-- the leaderboard on the far wall (specs).
	StoreMachine = table.freeze({
		Position = Vector3.new(26, 0, 16), -- centre of its footprint on the floor
		Yaw = 90, -- degrees; its front faces -X
	}),

	-- Outdoor campus (2026-10-07, Lib/CampusBuilder + Lib/OutdoorBuilder): reached
	-- through an entrance in the middle of the lobby's glass front. Ground is at
	-- Y = -1 (one step down from the building floor). Rectangles are XZ boxes
	-- { MinX, MaxX, MinZ, MaxZ }; walkways are kept free of every prop (specs).
	Campus = table.freeze({
		EntranceWidth = 14,
		EntranceHeight = 10,
		GroundY = -1,
		-- Invisible walls keep players on the grounds; a low hedge marks them.
		-- North edge moved from z -130 to -210 for the Recreation Center
		-- (major update decision D3, 2026-10-09).
		Boundary = table.freeze({ MinX = -130, MaxX = 130, MinZ = -210, MaxZ = 150 }),
		BoundaryHeight = 60,
		-- Decorative road just outside the south boundary.
		StreetNorthZ = 160,
		StreetSouthZ = 176,
		-- Paved plaza in front of the entrance.
		Plaza = table.freeze({ MinX = -44, MaxX = 44, MinZ = 34, MaxZ = 52 }),
		Walkways = table.freeze({
			-- Entrance straight south to the Stress-Relief Zone.
			table.freeze({ MinX = -5, MaxX = 5, MinZ = 52, MaxZ = 112 }),
			-- Cross walk from the Garden to the Coffee Corner.
			table.freeze({ MinX = -48, MaxX = 48, MinZ = 84, MaxZ = 92 }),
			-- Loop around the building (south legs meet the plaza).
			table.freeze({ MinX = -100, MaxX = 100, MinZ = -66, MaxZ = -60 }),
			table.freeze({ MinX = -100, MaxX = -94, MinZ = -66, MaxZ = 46 }),
			table.freeze({ MinX = 94, MaxX = 100, MinZ = -66, MaxZ = 46 }),
			table.freeze({ MinX = -100, MaxX = -44, MinZ = 40, MaxZ = 46 }),
			table.freeze({ MinX = 44, MaxX = 100, MinZ = 40, MaxZ = 46 }),
			-- Garden and Coffee Corner down to the cross walk's ends and the loop.
			table.freeze({ MinX = -100, MaxX = -94, MinZ = 46, MaxZ = 88 }),
			table.freeze({ MinX = 94, MaxX = 100, MinZ = 46, MaxZ = 88 }),
			-- North from the loop to the Recreation Center.
			table.freeze({ MinX = -4, MaxX = 4, MinZ = -140, MaxZ = -66 }),
		}),
		-- Round areas: centre (Y = ground) and radius.
		Garden = table.freeze({ Center = Vector3.new(-70, -1, 88), Radius = 24 }),
		CoffeeCorner = table.freeze({ Center = Vector3.new(70, -1, 88), Radius = 22 }),
		StressReliefZone = table.freeze({ Center = Vector3.new(0, -1, 126), Radius = 16 }),
	}),

	PlaceholderBossSize = Vector3.new(6, 8, 6),
	PlaceholderBossColor = Color3.fromRGB(255, 120, 60),
})

return ArenaConfig
