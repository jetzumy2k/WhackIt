--!strict
-- Server-only abuse limits for client->server remotes. Kept out of ReplicatedStorage
-- so clients can't read the exact thresholds (see docs/REMOTE_CONTRACTS.md).

local RemoteLimits = table.freeze({
	-- Longest server-issued id a client may send back.
	MaxIdLength = 64,

	-- Per-remote token buckets. These are flood guards, deliberately looser than
	-- gameplay rules (e.g. GameConfig.HitCooldown = 0.25 s allows 4 accepted hits/s).
	RequestHammerHit = table.freeze({
		Capacity = 10,
		RefillPerSecond = 8,
	}),

	-- At most one rejection warning per player every 5 seconds, so a flooding
	-- client can't flood the server log too.
	RejectLog = table.freeze({
		Capacity = 1,
		RefillPerSecond = 0.2,
	}),
})

return RemoteLimits
