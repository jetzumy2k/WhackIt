--!strict
-- Server-only abuse limits for client->server remotes. Kept out of ReplicatedStorage
-- so clients can't read the exact thresholds (see docs/REMOTE_CONTRACTS.md).

local RemoteLimits = table.freeze({
	-- Longest server-issued id a client may send back.
	MaxIdLength = 64,

	-- Per-remote token buckets. These are flood guards, deliberately looser than
	-- gameplay rules (e.g. GameConfig.HitCooldown = 0.45 s allows ~2 accepted hits/s).
	RequestHammerHit = table.freeze({
		Capacity = 10,
		RefillPerSecond = 8,
	}),

	-- Shop buy/equip: a few quick clicks are fine; sustained spam is not.
	Shop = table.freeze({
		Capacity = 5,
		RefillPerSecond = 2,
	}),

	-- Admin panel: a few clicks in a row are fine; these are rare actions.
	Admin = table.freeze({
		Capacity = 5,
		RefillPerSecond = 1,
	}),

	-- Settings switches: a few quick toggles are fine; sustained spam is not.
	Settings = table.freeze({
		Capacity = 5,
		RefillPerSecond = 1,
	}),

	-- Office furniture edits (place, move, remove): quick rearranging is fine.
	Office = table.freeze({
		Capacity = 8,
		RefillPerSecond = 3,
	}),

	-- Office travel and privacy (teleports, friend look-ups): rare actions.
	OfficeTravel = table.freeze({
		Capacity = 3,
		RefillPerSecond = 0.5,
	}),

	-- Pickleball challenges, accepts, cancels and forfeits: rare actions.
	Rec = table.freeze({
		Capacity = 4,
		RefillPerSecond = 0.5,
	}),

	-- Team missions: open, join, leave, begin. Rare actions.
	Mission = table.freeze({
		Capacity = 4,
		RefillPerSecond = 0.5,
	}),

	-- Tower elevator rides: a few in a row are fine (picking a floor).
	Tower = table.freeze({
		Capacity = 3,
		RefillPerSecond = 0.5,
	}),

	-- Office Showcase: gallery pages, visits, likes, reports, publishing and
	-- admin moderation. Each may touch a DataStore, so keep them slow.
	Showcase = table.freeze({
		Capacity = 4,
		RefillPerSecond = 0.5,
	}),

	-- Design contests: info, entering, ballots and votes. Votes need
	-- ContestConfig.MinViewSeconds in each entry anyway; this stops floods.
	Contest = table.freeze({
		Capacity = 4,
		RefillPerSecond = 0.5,
	}),

	-- Pet Arena: starting battles, moves, challenges. One move a round, so
	-- a little burst is plenty.
	PetArena = table.freeze({
		Capacity = 5,
		RefillPerSecond = 1,
	}),

	-- Lucky Capsule spins: the reveal takes a moment anyway.
	Capsule = table.freeze({
		Capacity = 2,
		RefillPerSecond = 0.5,
	}),

	-- Paper Toss: starting, throwing, quitting (throws also wait
	-- PaperTossConfig.MinThrowSeconds).
	PaperToss = table.freeze({
		Capacity = 4,
		RefillPerSecond = 1,
	}),

	-- Quest claims and rerolls: a few taps in a row are fine.
	Quests = table.freeze({
		Capacity = 6,
		RefillPerSecond = 2,
	}),

	-- Pickleball swings: PickleballConfig.Shot.SwingCooldown (0.5 s) is the
	-- gameplay limit; this only stops floods.
	RecSwing = table.freeze({
		Capacity = 6,
		RefillPerSecond = 4,
	}),

	-- At most one rejection warning per player every 5 seconds, so a flooding
	-- client can't flood the server log too.
	RejectLog = table.freeze({
		Capacity = 1,
		RefillPerSecond = 0.2,
	}),
})

return RemoteLimits
