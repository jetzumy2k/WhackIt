--!strict
--[[
	Personal offices (docs/OFFICES.md). Every player in a server gets one
	open-plan room in the Office Wing, far above the map and out of sight of
	it; players get there and back by teleport (OfficeService).

	Room-local coordinates: X and Z in studs from the room's centre, floor at
	Y = 0. The door is in the +Z wall; the entry zone inside it stays free of
	furniture so nobody is boxed in at the spawn point.
]]

export type Privacy = "Public" | "Friends" | "Private"

local ROOM_SIZE = 40
local HALF = ROOM_SIZE / 2

local OfficeConfig = table.freeze({
	RoomSize = ROOM_SIZE, -- inside width and depth (studs)
	WallHeight = 14,
	WallThickness = 1,
	-- Furniture footprints keep this far from the walls.
	WallMargin = 1,
	DoorWidth = 8,
	-- Nothing may be placed here (room-local, inclusive bounds).
	EntryZone = table.freeze({ MinX = -5, MaxX = 5, MinZ = HALF - 7, MaxZ = HALF }),
	-- Where arriving players stand (room-local), facing into the room (-Z).
	Arrival = Vector3.new(0, 3, HALF - 3),

	MaxItems = 60,
	Rotations = table.freeze({ 0, 90, 180, 270 }),

	-- The Office Wing: rooms in a row along +X, far from the campus and high
	-- above it (the campus ends at x 130, its skyline a little further).
	WingOrigin = Vector3.new(2000, 300, 0),
	SlotSpacing = ROOM_SIZE + 20,
	-- One room per player place in the server (Players.MaxPlayers), at most this.
	MaxSlots = 50,

	PrivacyModes = table.freeze({ "Public", "Friends", "Private" } :: { Privacy }),
	DefaultPrivacy = "Public" :: Privacy,
	PrivacyText = table.freeze({
		Public = "Anyone can visit",
		Friends = "Friends only",
		Private = "Only you",
	}),

	-- Seconds between checks that visitors are still allowed in a room.
	GuardInterval = 1,
})

return OfficeConfig
