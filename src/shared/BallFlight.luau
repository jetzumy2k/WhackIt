--!strict
--[[
	The pickleball's flight (docs/PICKLEBALL.md "The ball"). Pure and
	deterministic: the server works out where a shot goes and when it
	bounces; every client draws the same path from the same numbers, so
	nobody needs the ball replicated as a physics part.

	Court-local coordinates (Config/PickleballConfig): X across, Z along
	the court with the net at Z = 0, Y up from the court surface (the
	ball's centre). A flight has two arcs: launch to the first bounce, and
	the first bounce to the second. A ball that hits the net drops straight
	down from the net.
]]

export type Physics = {
	Gravity: number,
	Restitution: number,
	Friction: number,
}

export type NetShape = {
	Width: number,
	NetHeightSide: number,
	NetHeightCenter: number,
	NetOverhang: number,
}

export type Flight = {
	Launch: Vector3,
	Velocity: Vector3,
	T0: number, -- server time of the launch
}

export type Events = {
	NetTime: number?, -- seconds after the launch the ball reaches the net plane
	NetHit: boolean,
	NetPoint: Vector3?,
	BounceTime: number, -- first bounce (never reached if NetHit)
	BouncePoint: Vector3,
	BounceVelocity: Vector3, -- just after the first bounce
	SecondBounceTime: number,
	SecondBouncePoint: Vector3,
}

local BallFlight = {}

-- Seconds until a ball at height `y` moving up at `vy` reaches the ground.
local function timeToGround(y: number, vy: number, gravity: number): number
	local height = math.max(y, 0)
	return (vy + math.sqrt(vy * vy + 2 * gravity * height)) / gravity
end

local function arc(launch: Vector3, velocity: Vector3, gravity: number, t: number): Vector3
	return Vector3.new(
		launch.X + velocity.X * t,
		launch.Y + velocity.Y * t - 0.5 * gravity * t * t,
		launch.Z + velocity.Z * t
	)
end

-- Net height at a point across the court: the centre is a little lower
-- than the sidelines. nil past the posts (no net there).
function BallFlight.netHeightAt(net: NetShape, x: number): number?
	local half = net.Width / 2
	local distance = math.abs(x)
	if distance > half + net.NetOverhang then
		return nil
	end
	local t = math.min(distance / half, 1)
	return net.NetHeightCenter + (net.NetHeightSide - net.NetHeightCenter) * t
end

-- The launch velocity that lands a ball from `launch` on the court at
-- `target` (Y ignored) after `duration` seconds.
function BallFlight.solve(
	launch: Vector3,
	target: Vector3,
	duration: number,
	gravity: number
): Vector3
	return Vector3.new(
		(target.X - launch.X) / duration,
		(-launch.Y + 0.5 * gravity * duration * duration) / duration,
		(target.Z - launch.Z) / duration
	)
end

-- When and where the ball reaches the net, bounces and bounces again.
function BallFlight.events(flight: Flight, physics: Physics, net: NetShape): Events
	local g = physics.Gravity
	local launch, velocity = flight.Launch, flight.Velocity
	local bounceTime = timeToGround(launch.Y, velocity.Y, g)
	local bouncePoint = arc(launch, velocity, g, bounceTime)
	bouncePoint = Vector3.new(bouncePoint.X, 0, bouncePoint.Z)

	-- The net plane (Z = 0) is crossed only if the ball moves towards it
	-- and gets there before landing.
	local netTime: number? = nil
	local netHit = false
	local netPoint: Vector3? = nil
	if velocity.Z ~= 0 and launch.Z ~= 0 and math.sign(velocity.Z) ~= math.sign(launch.Z) then
		local t = -launch.Z / velocity.Z
		if t >= 0 and t <= bounceTime then
			netTime = t
			local at = arc(launch, velocity, g, t)
			netPoint = at
			local height = BallFlight.netHeightAt(net, at.X)
			netHit = height ~= nil and at.Y <= height
		end
	end

	local landingVy = velocity.Y - g * bounceTime
	local bounceVelocity = Vector3.new(
		velocity.X * physics.Friction,
		-landingVy * physics.Restitution,
		velocity.Z * physics.Friction
	)
	local secondTime = 2 * bounceVelocity.Y / g
	local secondPoint = arc(bouncePoint, bounceVelocity, g, secondTime)

	return {
		NetTime = netTime,
		NetHit = netHit,
		NetPoint = netPoint,
		BounceTime = bounceTime,
		BouncePoint = bouncePoint,
		BounceVelocity = bounceVelocity,
		SecondBounceTime = bounceTime + secondTime,
		SecondBouncePoint = Vector3.new(secondPoint.X, 0, secondPoint.Z),
	}
end

-- Where the ball is `t` seconds after the launch. After the second bounce
-- it rests where it landed (drawing only: the rally is over by then).
function BallFlight.positionAt(flight: Flight, events: Events, physics: Physics, t: number): Vector3
	local g = physics.Gravity
	local time = math.max(t, 0)
	local netTime, netPoint = events.NetTime, events.NetPoint
	if events.NetHit and netTime and netPoint then
		if time <= netTime then
			return arc(flight.Launch, flight.Velocity, g, time)
		end
		local fall = time - netTime
		return Vector3.new(netPoint.X, math.max(netPoint.Y - 0.5 * g * fall * fall, 0), netPoint.Z)
	end
	if time <= events.BounceTime then
		return arc(flight.Launch, flight.Velocity, g, time)
	end
	if time <= events.SecondBounceTime then
		return arc(events.BouncePoint, events.BounceVelocity, g, time - events.BounceTime)
	end
	return events.SecondBouncePoint
end

return BallFlight
