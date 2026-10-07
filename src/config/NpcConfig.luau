--!strict
--[[
	Friendly office staff in the lobby lounge near the leaderboard (built by
	Lib/NpcBuilder on the server, animated by NpcController on each client).
	Pure decoration: no Humanoid, never solid, not bosses, no effect on stress,
	XP, coins or the leaderboard.

	Lines are written by us, short (<= 34 characters) and always friendly
	(spec-checked with the same blocked words as boss lines).
]]

export type Pose = "Stand" | "Sit"
-- What the NPC does while idle (NpcController):
--   Greet   looks around, waves when you walk up
--   Read    reads a book, looks up now and then
--   Chat    holds a coffee, turned to its neighbour, nods while talking
--   Coffee  sips coffee, looks around
export type Behavior = "Greet" | "Read" | "Chat" | "Coffee"

export type Npc = {
	Id: string,
	Name: string,
	Pose: Pose,
	Behavior: Behavior,
	-- Feet (standing) or seat top (sitting) centre, and facing (degrees;
	-- 0 = facing -Z/north, 90 = facing -X/west, 180 = facing +Z/south).
	Position: Vector3,
	Yaw: number,
	HeadYaw: number?, -- head turned this far (degrees) from the body, e.g. to a neighbour
	Shirt: Color3,
	Pants: Color3,
	Skin: Color3,
	Hair: Color3,
	Tie: Color3?,
	Lines: { string },
	-- Talks with this NPC (lines alternate, Chat behaviour).
	Partner: string?,
}

local function npc(entry: Npc): Npc
	table.freeze(entry.Lines)
	return table.freeze(entry)
end

local list: { Npc } = {
	npc({
		Id = "receptionist",
		Name = "Rita (Reception)",
		Pose = "Stand",
		Behavior = "Greet",
		-- Behind the reception desk, facing the lobby and the spawn.
		Position = Vector3.new(-22, 0, 8.6),
		Yaw = 180,
		Shirt = Color3.fromRGB(110, 170, 230),
		Pants = Color3.fromRGB(60, 60, 80),
		Skin = Color3.fromRGB(240, 200, 170),
		Hair = Color3.fromRGB(120, 70, 40),
		Lines = {
			"Welcome to Stress Relief Dept.!",
			"Need a stress break?",
			"The bosses are waiting!",
			"Good luck out there!",
			"Check the board for top scores!",
		},
	}),
	npc({
		Id = "reader",
		Name = "Ben (Accounting)",
		Pose = "Sit",
		Behavior = "Read",
		-- West couch, left seat, facing into the lobby.
		Position = Vector3.new(-14.2, 1.6, 30.9),
		Yaw = 0,
		HeadYaw = -15,
		Shirt = Color3.fromRGB(120, 190, 130),
		Pants = Color3.fromRGB(70, 75, 90),
		Skin = Color3.fromRGB(150, 105, 80),
		Hair = Color3.fromRGB(40, 35, 35),
		Tie = Color3.fromRGB(230, 90, 90),
		Lines = {
			"This book is called 'Relax'.",
			"Don't forget to relax!",
			"Chapter three: breathe out.",
		},
		Partner = "chatter",
	}),
	npc({
		Id = "chatter",
		Name = "Mia (Design)",
		Pose = "Sit",
		Behavior = "Chat",
		-- West couch, right seat, turned towards Ben.
		Position = Vector3.new(-10.2, 1.6, 30.9),
		Yaw = 0,
		HeadYaw = 35,
		Shirt = Color3.fromRGB(250, 170, 90),
		Pants = Color3.fromRGB(80, 70, 110),
		Skin = Color3.fromRGB(255, 220, 190),
		Hair = Color3.fromRGB(230, 190, 90),
		Lines = {
			"Did you see the leaderboard?",
			"Nice score today!",
			"Coffee makes everything better.",
		},
		Partner = "reader",
	}),
	npc({
		Id = "coffee",
		Name = "Sam (IT)",
		Pose = "Stand",
		Behavior = "Coffee",
		-- By the water cooler, out of the way of the board and the lounge.
		Position = Vector3.new(-26.5, 0, 30.2),
		Yaw = 90,
		Shirt = Color3.fromRGB(170, 130, 220),
		Pants = Color3.fromRGB(55, 60, 75),
		Skin = Color3.fromRGB(200, 150, 115),
		Hair = Color3.fromRGB(60, 45, 30),
		Tie = Color3.fromRGB(60, 120, 200),
		Lines = {
			"I need more coffee!",
			"Coffee break! Want some?",
			"Nice score!",
			"Have you tried turning stress off?",
		},
	}),
}

local byId: { [string]: Npc } = {}
for _, entry in list do
	byId[entry.Id] = entry
end

return table.freeze({
	List = table.freeze(list),
	ById = table.freeze(byId),

	-- An NPC greets you when you come this close (and not again for GreetCooldown).
	GreetStuds = 10,
	GreetCooldown = 25,
	-- Now and then one NPC near you says a line (or a couch pair chats).
	ChatterMin = 10,
	ChatterMax = 18,
	ChatterStuds = 35, -- only when you're this close, so nobody talks to an empty room
	LineSeconds = 3,
	-- How often the client checks your distance (seconds; not every frame).
	CheckInterval = 0.5,
	MaxLineLength = 34,
})
