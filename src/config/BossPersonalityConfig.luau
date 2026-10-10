--!strict
--[[
	How each boss behaves between whacks (Controllers/BossVisualController):
	idle motion, a personal fidget, the pitch of its sounds and the short lines
	it says to YOU (a local speech bubble) when you walk up or land a hit.
	Purely presentation: the server's hitbox, health and shouts are unchanged.

	Lines are written by us, short (<= 30 characters) and family-friendly:
	surprised, flustered or silly, never rude (spec-checked with the same
	blocked words as BossShoutConfig). Senior and Principal bosses share their junior's
	personality; admin-created bosses use the one of the boss they look like.

	Sounds are Roblox built-in files (no uploaded audio needed), pitched per
	boss so each sounds a little different. Swap in uploaded voice clips
	("Hey!", "Ouch!") by changing the ids in Sounds; keep them short.
]]

export type Fidget = "Hurry" | "Glance" | "Jitter" | "Tilt" | "Yawn" | "Puff"

export type Personality = {
	Mood: string, -- one-line description (docs only)
	BobSpeed: number,
	BobHeight: number, -- studs
	SwayDegrees: number,
	SwaySpeed: number,
	-- Small side-to-side step of the drawn monster (visual only; the hitbox stays).
	ShuffleStuds: number,
	ShuffleSpeed: number,
	-- Looking around when nobody is near.
	LookDegrees: number,
	LookSpeed: number,
	Fidget: Fidget, -- an occasional extra motion every few seconds
	Pitch: number, -- sound pitch (PlaybackSpeed)
	ApproachLines: { string },
	HitLines: { string },
}

local function personality(p: Personality): Personality
	table.freeze(p.ApproachLines)
	table.freeze(p.HitLines)
	return table.freeze(p)
end

local byType: { [string]: Personality } = {
	-- Deadline Boss: always in a hurry.
	hurry = personality({
		Mood = "Always in a hurry: quick bob, taps its feet, glances at the clock",
		BobSpeed = 3.6,
		BobHeight = 0.18,
		SwayDegrees = 3,
		SwaySpeed = 2.4,
		ShuffleStuds = 0.5,
		ShuffleSpeed = 2.6,
		LookDegrees = 35,
		LookSpeed = 1.4,
		Fidget = "Hurry",
		Pitch = 1.35,
		ApproachLines = { "Hey! Is it done yet?", "No time, no time!", "Whoa! Already?" },
		HitLines = { "Ouch!", "Not again!", "Okay, okay!", "Hurry up!" },
	}),
	-- Meeting Master: a stressed executive.
	stressed = personality({
		Mood = "Stressed executive: paces, keeps looking over its shoulder",
		BobSpeed = 2.2,
		BobHeight = 0.2,
		SwayDegrees = 4,
		SwaySpeed = 1.3,
		ShuffleStuds = 0.7,
		ShuffleSpeed = 1.2,
		LookDegrees = 50,
		LookSpeed = 0.9,
		Fidget = "Glance",
		Pitch = 1.1,
		ApproachLines = { "Oh! Do we have a meeting?", "Hey! Got a minute?", "Whoa, quick sync?" },
		HitLines = { "Ouch!", "Let's circle back!", "Okay, okay!", "Not again!" },
	}),
	-- Reply-All Boss: overwhelmed by messages.
	overwhelmed = personality({
		Mood = "Overwhelmed by email: jittery, flinches at every ping",
		BobSpeed = 2.8,
		BobHeight = 0.22,
		SwayDegrees = 5,
		SwaySpeed = 1.8,
		ShuffleStuds = 0.3,
		ShuffleSpeed = 3.2,
		LookDegrees = 40,
		LookSpeed = 1.6,
		Fidget = "Jitter",
		Pitch = 1.5,
		ApproachLines = { "Hey! Did you get my email?", "Whoa! New message!", "Oh! Reply-all?" },
		HitLines = { "Ouch!", "Inbox full!", "Whoa!", "Not again!" },
	}),
	-- Production Bug: a confused developer.
	confused = personality({
		Mood = "Confused developer: tilts its head, looks both ways, little hops",
		BobSpeed = 1.9,
		BobHeight = 0.25,
		SwayDegrees = 6,
		SwaySpeed = 1.1,
		ShuffleStuds = 0.4,
		ShuffleSpeed = 1.5,
		LookDegrees = 60,
		LookSpeed = 1.1,
		Fidget = "Tilt",
		Pitch = 1.7,
		ApproachLines = { "Huh? Who's there?", "Whoa! It works for me!", "Hey! Not a bug!" },
		HitLines = { "Ouch!", "That's a feature!", "Whoa!", "Huh?!" },
	}),
	-- Monday Monster: sleepy.
	sleepy = personality({
		Mood = "Sleepy: slow bob, big yawns, needs coffee",
		BobSpeed = 1.2,
		BobHeight = 0.28,
		SwayDegrees = 3,
		SwaySpeed = 0.7,
		ShuffleStuds = 0.2,
		ShuffleSpeed = 0.6,
		LookDegrees = 25,
		LookSpeed = 0.5,
		Fidget = "Yawn",
		Pitch = 0.9,
		ApproachLines = { "Huh? Is it Friday?", "I need coffee!", "Five more minutes..." },
		HitLines = { "Ouch!", "I need coffee!", "Okay, I'm awake!", "Not again!" },
	}),
	-- The CEO: pompous.
	pompous = personality({
		Mood = "Pompous CEO: slow, puffs itself up",
		BobSpeed = 1.5,
		BobHeight = 0.2,
		SwayDegrees = 2,
		SwaySpeed = 0.8,
		ShuffleStuds = 0.6,
		ShuffleSpeed = 0.8,
		LookDegrees = 30,
		LookSpeed = 0.6,
		Fidget = "Puff",
		Pitch = 0.75,
		ApproachLines = { "Hey! Got an appointment?", "Whoa! Who let you up here?" },
		HitLines = { "Ouch! My bonus!", "Hey! I'm the CEO!", "Okay, okay!", "Not the suit!" },
	}),
}

local typeOf: { [string]: string } = {
	deadline_boss = "hurry",
	senior_deadline_boss = "hurry",
	meeting_master = "stressed",
	senior_meeting_master = "stressed",
	reply_all_boss = "overwhelmed",
	senior_reply_all_boss = "overwhelmed",
	production_bug = "confused",
	senior_production_bug = "confused",
	monday_monster = "sleepy",
	senior_monday_monster = "sleepy",
	principal_deadline_boss = "hurry",
	principal_meeting_master = "stressed",
	principal_reply_all_boss = "overwhelmed",
	principal_production_bug = "confused",
	principal_monday_monster = "sleepy",
	the_ceo = "pompous",
}

local byBossId: { [string]: Personality } = {}
for bossId, kind in typeOf do
	byBossId[bossId] = byType[kind]
end

return table.freeze({
	ByBossId = table.freeze(byBossId),
	Types = table.freeze(byType),
	-- For a boss without its own (none today), so nothing breaks.
	Default = byType.stressed,

	-- Lines said to locked bosses' visitors, whatever their personality.
	LockedLines = table.freeze({ "Not so fast! Come back later.", "Hey! You're not ready yet!" }),

	-- Walk within ApproachStuds (same floor) after being farther than
	-- LeaveStuds away and the boss notices you: a hop, a sound, a line.
	ApproachStuds = 14,
	LeaveStuds = 24,
	ApproachCooldown = 12, -- seconds per boss
	-- Bosses face you within FaceStuds; farther away they look around.
	FaceStuds = 30,
	SameFloorStuds = 6, -- height difference still counted as the same floor

	-- Hit sounds at most this often per boss, however many players hit it.
	HitSoundCooldown = 0.7,
	-- Your own hits get a line (local bubble) at most this often per boss...
	HitLineCooldown = 3,
	-- ...and only on some hits.
	HitLineChance = 0.4,
	-- Sounds are heard up to this far (and not played beyond it).
	SoundMaxDistance = 60,
	SoundVolume = 0.5,

	-- Fidgets come every FidgetMin..FidgetMax seconds and last FidgetSeconds.
	FidgetMin = 4,
	FidgetMax = 8,
	FidgetSeconds = 0.9,

	-- Built-in sounds: a "boing" on hits (pitched down on defeat), a "ping"
	-- when a boss notices you.
	Sounds = table.freeze({
		Hit = "rbxasset://sounds/action_jump.mp3",
		Notice = "rbxasset://sounds/electronicpingshort.wav",
	}),

	-- Limits the spec holds every personality to (small, readable motion).
	MaxShuffleStuds = 0.8,
	MaxLookDegrees = 60,
	MaxLineLength = 30,
})
