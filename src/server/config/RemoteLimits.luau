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

	-- At most one rejection warning per player every 5 seconds, so a flooding
	-- client can't flood the server log too.
	RejectLog = table.freeze({
		Capacity = 1,
		RefillPerSecond = 0.2,
	}),
})

return RemoteLimits
