--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BallFlight = require(ReplicatedStorage.Shared.BallFlight)
local PickleballConfig = require(ReplicatedStorage.Config.PickleballConfig)

local PHYSICS = PickleballConfig.Ball
local NET = PickleballConfig.Court
local EPSILON = 0.01

local function near(a: number, b: number): boolean
	return math.abs(a - b) < EPSILON
end

local function flightTo(launch: Vector3, target: Vector3, duration: number): BallFlight.Flight
	return {
		Launch = launch,
		Velocity = BallFlight.solve(launch, target, duration, PHYSICS.Gravity),
		T0 = 0,
	}
end

return function()
	describe("BallFlight.solve", function()
		it("lands the ball on its target after the given time", function()
			local launch = Vector3.new(3, 2.5, 20)
			local target = Vector3.new(-6, 0, -15)
			local flight = flightTo(launch, target, 1.2)
			local events = BallFlight.events(flight, PHYSICS, NET)
			expect(near(events.BounceTime, 1.2)).to.equal(true)
			expect(near(events.BouncePoint.X, -6)).to.equal(true)
			expect(near(events.BouncePoint.Z, -15)).to.equal(true)
			expect(events.BouncePoint.Y).to.equal(0)
		end)
	end)

	describe("BallFlight.events", function()
		it("clears the net on a normal rally shot", function()
			local events = BallFlight.events(
				flightTo(Vector3.new(0, 2, 18), Vector3.new(0, 0, -15), 1),
				PHYSICS,
				NET
			)
			expect(events.NetHit).to.equal(false)
			expect(events.NetTime ~= nil).to.equal(true)
			expect((events.NetPoint :: Vector3).Y > NET.NetHeightCenter).to.equal(true)
		end)

		it("hits the net when the ball is too low as it gets there", function()
			-- A flat, fast shot from low down, aimed just past the net.
			local events = BallFlight.events(
				flightTo(
					Vector3.new(0, 0.6, 10),
					Vector3.new(0, 0, -1),
					PickleballConfig.Shot.MinDuration
				),
				PHYSICS,
				NET
			)
			expect(events.NetHit).to.equal(true)
		end)

		it("has no net past the posts", function()
			expect(BallFlight.netHeightAt(NET, 0)).to.equal(NET.NetHeightCenter)
			expect(BallFlight.netHeightAt(NET, NET.Width / 2)).to.equal(NET.NetHeightSide)
			expect(BallFlight.netHeightAt(NET, -NET.Width / 2 - NET.NetOverhang)).to.equal(
				NET.NetHeightSide
			)
			expect(BallFlight.netHeightAt(NET, NET.Width / 2 + NET.NetOverhang + 0.5)).to.equal(nil)
		end)

		it("doesn't reach the net when it lands on the hitter's own side", function()
			local events = BallFlight.events(
				flightTo(Vector3.new(0, 2, 18), Vector3.new(0, 0, 8), 0.8),
				PHYSICS,
				NET
			)
			expect(events.NetTime).to.equal(nil)
			expect(events.NetHit).to.equal(false)
		end)

		it("bounces lower and slower, then lands again further on", function()
			local flight = flightTo(Vector3.new(0, 2, 18), Vector3.new(2, 0, -10), 1)
			local events = BallFlight.events(flight, PHYSICS, NET)
			local landingVy = flight.Velocity.Y - PHYSICS.Gravity * events.BounceTime
			expect(near(events.BounceVelocity.Y, -landingVy * PHYSICS.Restitution)).to.equal(true)
			expect(near(events.BounceVelocity.Z, flight.Velocity.Z * PHYSICS.Friction)).to.equal(
				true
			)
			expect(events.SecondBounceTime > events.BounceTime).to.equal(true)
			expect(events.SecondBouncePoint.Z < events.BouncePoint.Z).to.equal(true)
		end)
	end)

	describe("BallFlight.positionAt", function()
		it("follows the arc, the bounce and then rests", function()
			local flight = flightTo(Vector3.new(0, 2, 18), Vector3.new(0, 0, -10), 1)
			local events = BallFlight.events(flight, PHYSICS, NET)
			local start = BallFlight.positionAt(flight, events, PHYSICS, 0)
			expect(near(start.Z, 18) and near(start.Y, 2)).to.equal(true)
			local bounce = BallFlight.positionAt(flight, events, PHYSICS, events.BounceTime)
			expect(near(bounce.Y, 0) and near(bounce.Z, -10)).to.equal(true)
			local middle = BallFlight.positionAt(
				flight,
				events,
				PHYSICS,
				(events.BounceTime + events.SecondBounceTime) / 2
			)
			expect(middle.Y > 0).to.equal(true)
			local rest = BallFlight.positionAt(flight, events, PHYSICS, events.SecondBounceTime + 5)
			expect(rest).to.equal(events.SecondBouncePoint)
		end)

		it("drops straight down from the net after hitting it", function()
			local flight = flightTo(
				Vector3.new(0, 0.6, 10),
				Vector3.new(0, 0, -1),
				PickleballConfig.Shot.MinDuration
			)
			local events = BallFlight.events(flight, PHYSICS, NET)
			local netTime = events.NetTime :: number
			local later = BallFlight.positionAt(flight, events, PHYSICS, netTime + 0.1)
			expect(near(later.Z, 0)).to.equal(true)
			expect(later.Y < (events.NetPoint :: Vector3).Y).to.equal(true)
			local floor = BallFlight.positionAt(flight, events, PHYSICS, netTime + 10)
			expect(floor.Y).to.equal(0)
		end)
	end)
end
