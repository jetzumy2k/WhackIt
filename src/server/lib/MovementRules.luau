--!strict
-- Pure movement sanity checks for MovementGuardService. Only horizontal speed
-- is judged: falling can legitimately be fast, while teleporting next to a
-- boss or speed hacks show up as impossible horizontal movement.

local MovementRules = {}

function MovementRules.horizontalSpeed(from: Vector3, to: Vector3, seconds: number): number
	if seconds <= 0 then
		return 0
	end
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	return flat.Magnitude / seconds
end

function MovementRules.isTooFast(
	from: Vector3,
	to: Vector3,
	seconds: number,
	maxSpeed: number
): boolean
	return MovementRules.horizontalSpeed(from, to, seconds) > maxSpeed
end

-- Whether a player flagged at `flaggedAt` is still under suspicion at `now`.
function MovementRules.isSuspect(flaggedAt: number?, now: number, suspectSeconds: number): boolean
	return flaggedAt ~= nil and now - flaggedAt < suspectSeconds
end

return MovementRules
