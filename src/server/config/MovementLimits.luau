--!strict
-- Server-only movement sanity thresholds (kept out of ReplicatedStorage so
-- clients can't read the exact limits). See MovementGuardService.

local MovementLimits = table.freeze({
	-- How often each character's position is sampled.
	SampleInterval = 0.5,
	-- Highest believable horizontal speed in studs/s. Default walking is 16;
	-- this leaves room for jumps, slopes and network catch-up bursts.
	MaxHorizontalSpeed = 50,
	-- After a too-fast move, the player's hits are ignored for this long.
	SuspectSeconds = 5,
})

return MovementLimits
