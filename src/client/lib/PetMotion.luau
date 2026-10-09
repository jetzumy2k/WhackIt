--!strict
--[[
	How a pet follows its owner (docs/PETS.md "Looks and movement"). Pure: it
	is given the owner's position, facing and speed and the ground height,
	and returns where the pet stands and how it poses (Lib/PetVisual). No
	Instances, so the behaviour is unit-tested.

	Following ("arrive"): the pet keeps to a slot beside and behind its owner
	(PetConfig Follow, bigger for bigger pets). It speeds up with the owner
	and a little more when it falls behind, slows as it arrives, and stops.
	It turns toward where it's going at a limited rate and only moves as fast
	as it faces its way, so it never walks sideways or backwards, spins or
	jitters. Legs cycle with the distance actually covered, so feet don't
	slide; the stride blends from standing (0) to walking (1) to running (2).
	A pet further than SNAP_DISTANCE from its owner (teleport, respawn, lag)
	is put back in its slot once.

	Kinds of movement (PetConfig Movement):
	  Ground   walks / runs, leans a little into a run
	  Hopping  moves in hops (lift and lean follow the gait cycle)
	  Crawling low and quick little steps
	  Flying   flies at FlyHeight over the ground under it with a gentle bob,
	           banks into turns, hovers when the owner stops; a butterfly
	           also drifts a little around its slot

	Standing still, a pet breathes and, now and then, does one small thing:
	looks around, looks at its owner, sits (dogs, cats and friends), hops
	(rabbit), flutters (butterfly) or beats its wings (big flyers). A boss hit
	by its owner makes it briefly excited (react()).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local PetConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("PetConfig"))

local PetVisual = require(script.Parent.PetVisual)

local PetMotion = {}

PetMotion.SNAP_DISTANCE = 40
PetMotion.ARRIVE_RADIUS = 0.5
-- Fast enough to keep up with a sprinting owner and catch up.
PetMotion.MAX_SPEED = GameConfig.SprintSpeed * 1.25

local ACCELERATION = 34
local BRAKING = 46
local TURN_RATE = 5 -- radians per second
local RUN_TURN_RATE = 7
local CATCH_UP = 2.4 -- extra speed per stud behind
local SIT_AFTER = 6 -- seconds standing before a sitter may sit
local SITTERS: { [string]: boolean } =
	{ dog = true, cat = true, monkey = true, bear = true, unicorn = true }

export type Input = {
	OwnerPosition: Vector3, -- the owner's root
	OwnerYaw: number, -- radians, the way the owner faces
	OwnerSpeed: number, -- studs per second, horizontal
	GroundY: number, -- ground height under the pet
	Time: number, -- os.clock()
	Dt: number,
}

export type State = {
	Species: string,
	Movement: string,
	Follow: Vector2,
	FlyHeight: number,
	FlapRate: number,
	Scale: number,
	Placed: boolean,
	Position: Vector3, -- feet centre (walkers) or body centre (flyers)
	Yaw: number,
	Speed: number, -- along its facing
	GroundSpeed: number, -- what it actually covered last step
	Phase: number,
	Stride: number,
	Lean: number,
	Bank: number,
	HeadYaw: number,
	Sit: number,
	Excite: number,
	Flap: number,
	StillFor: number,
	Idle: string, -- "", "LookAround", "LookAtOwner", "Sit", "Hop", "Flutter", "Flap"
	IdleSince: number,
	NextIdleAt: number,
	HopAt: number, -- time of the last little hop (idle or reaction)
	Born: number,
	Random: Random,
	StateName: string, -- "Idle" | "Walk" | "Run" | "Hover" | "Fly"
}

local function angleDiff(from: number, to: number): number
	local diff = (to - from) % (2 * math.pi)
	if diff > math.pi then
		diff -= 2 * math.pi
	end
	return diff
end

-- The yaw (radians) that faces `direction` (-Z is forward).
function PetMotion.yawOf(direction: Vector3): number
	return math.atan2(-direction.X, -direction.Z)
end

local function approach(current: number, target: number, rate: number): number
	if current < target then
		return math.min(target, current + rate)
	end
	return math.max(target, current - rate)
end

local function smooth(current: number, target: number, sharpness: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-sharpness * dt))
end

function PetMotion.new(speciesId: string, born: number, seed: number?): State
	local species = PetConfig.ById[speciesId]
	return {
		Species = speciesId,
		Movement = if species then species.Movement else "Ground",
		Follow = if species then species.Follow else Vector2.new(2.6, 3.2),
		FlyHeight = if species then species.FlyHeight or 3.5 else 3.5,
		FlapRate = if species then species.FlapRate or 3 else 3,
		Scale = if species then species.Look.Scale else 1,
		Placed = false,
		Position = Vector3.zero,
		Yaw = 0,
		Speed = 0,
		GroundSpeed = 0,
		Phase = 0,
		Stride = 0,
		Lean = 0,
		Bank = 0,
		HeadYaw = 0,
		Sit = 0,
		Excite = 0,
		Flap = 0,
		StillFor = 0,
		Idle = "",
		IdleSince = born,
		NextIdleAt = born + 2,
		HopAt = -100,
		Born = born,
		Random = Random.new(seed or math.floor(born * 1000) % 100000),
		StateName = "Idle",
	}
end

-- Where the pet wants to be: beside and behind the owner.
function PetMotion.slot(state: State, input: Input): Vector3
	local facing = CFrame.Angles(0, input.OwnerYaw, 0)
	local offset = Vector3.new(state.Follow.X, 0, state.Follow.Y)
	if state.Species == "butterfly" then
		-- A light, wandering drift around its spot.
		offset += Vector3.new(math.sin(input.Time * 0.8) * 0.8, 0, math.cos(input.Time * 0.6) * 0.5)
	end
	local flat = input.OwnerPosition + facing:VectorToWorldSpace(offset)
	return Vector3.new(flat.X, input.GroundY, flat.Z)
end

local function flyY(state: State, input: Input): number
	local bob = math.sin(input.Time * 1.6) * 0.22 * state.Scale
	if state.Species == "butterfly" then
		bob += math.cos(input.Time * 2.3) * 0.25
	end
	return input.GroundY + state.FlyHeight + bob
end

-- Puts the pet straight in its slot (equip, respawn, too far away).
function PetMotion.place(state: State, input: Input): ()
	local slot = PetMotion.slot(state, input)
	state.Position = if state.Movement == "Flying"
		then Vector3.new(slot.X, flyY(state, input), slot.Z)
		else slot
	state.Yaw = input.OwnerYaw
	state.Speed = 0
	state.GroundSpeed = 0
	state.Stride = 0
	state.Sit = 0
	state.Placed = true
end

-- A short happy reaction (the owner hit a boss).
function PetMotion.react(state: State, time: number): ()
	state.Excite = 1
	if state.Movement ~= "Flying" and time - state.HopAt > 0.6 then
		state.HopAt = time
	end
end

local function pickIdle(state: State): string
	local options = { "LookAround", "LookAtOwner" }
	if state.Movement == "Hopping" then
		table.insert(options, "Hop")
	elseif state.Species == "butterfly" then
		table.insert(options, "Flutter")
	elseif state.Movement == "Flying" then
		table.insert(options, "Flap")
	end
	if SITTERS[state.Species] and state.StillFor > SIT_AFTER then
		table.insert(options, "Sit")
	end
	return options[state.Random:NextInteger(1, #options)]
end

-- One frame: moves the pet and returns its pivot and pose.
function PetMotion.step(state: State, input: Input): (CFrame, PetVisual.PoseState)
	local dt = math.min(input.Dt, 0.2)
	local t = input.Time
	if not state.Placed then
		PetMotion.place(state, input)
	end
	local flat = Vector3.new(1, 0, 1)
	local ownerFlat = input.OwnerPosition * flat
	if ((state.Position * flat) - ownerFlat).Magnitude > PetMotion.SNAP_DISTANCE then
		PetMotion.place(state, input) -- teleport recovery, only when truly far
	end

	-- Steering: arrive at the slot, turn first, never sideways.
	local slot = PetMotion.slot(state, input)
	local toSlot = (slot - state.Position) * flat
	local distance = toSlot.Magnitude
	local settled = distance < PetMotion.ARRIVE_RADIUS and input.OwnerSpeed < 0.5
	local desired = if settled
		then 0
		else math.min(
			PetMotion.MAX_SPEED,
			input.OwnerSpeed + math.max(0, distance - PetMotion.ARRIVE_RADIUS) * CATCH_UP
		)
	-- Ease in as it arrives so it never overshoots (keeps pace while the owner moves).
	desired = math.min(desired, input.OwnerSpeed + distance * 6)
	state.Speed = approach(
		state.Speed,
		desired,
		(if desired > state.Speed then ACCELERATION else BRAKING) * dt
	)

	local targetYaw = if distance > 0.3 and state.Speed > 0.2
		then PetMotion.yawOf(toSlot)
		else input.OwnerYaw
	local diff = angleDiff(state.Yaw, targetYaw)
	local rate = (if state.Stride > 1 then RUN_TURN_RATE else TURN_RATE) * dt
	local turn = math.clamp(diff, -rate, rate)
	state.Yaw += turn
	local facing = CFrame.Angles(0, state.Yaw, 0)
	local alignment = math.max(
		0,
		facing.LookVector:Dot(if distance > 0.01 then toSlot.Unit else facing.LookVector)
	)
	local step = math.min(state.Speed * alignment * alignment * dt, distance)
	state.Position += facing.LookVector * step
	state.GroundSpeed = if dt > 0 then step / dt else 0

	-- Gait: 0 standing, 1 walking, 2 running, cycling with the distance covered.
	local walkSpeed = GameConfig.WalkSpeed
	local strideTarget = math.clamp(state.GroundSpeed / walkSpeed, 0, 1)
		+ math.clamp((state.GroundSpeed - walkSpeed) / (GameConfig.SprintSpeed - walkSpeed), 0, 1)
	state.Stride = smooth(state.Stride, strideTarget, 8, dt)
	local strideLength = (
		if state.Movement == "Crawling"
			then 0.45
			elseif state.Movement == "Hopping" then 1.6
			else 1.1
	) * state.Scale
	state.Phase += (state.GroundSpeed / strideLength) * math.pi * dt

	local moving = state.GroundSpeed > 0.3
	local name = if state.Movement == "Flying"
		then (if moving then "Fly" else "Hover")
		elseif state.Stride < 0.08 then "Idle"
		elseif state.Stride < 1.05 then "Walk"
		else "Run"
	if name ~= state.StateName then
		state.StateName = name
	end

	-- Idle: breathe, and now and then do one small thing. Small drifts (a
	-- butterfly wandering round its spot) don't count as moving.
	local busy = input.OwnerSpeed > 0.5 or state.GroundSpeed > 1.5
	if busy then
		state.StillFor = 0
		state.Idle = ""
		state.NextIdleAt = t + state.Random:NextNumber(1.5, 3)
	else
		state.StillFor += dt
		if state.Idle ~= "" and state.Idle ~= "Sit" and t - state.IdleSince > 2.5 then
			state.Idle = ""
			state.NextIdleAt = t + state.Random:NextNumber(3, 7)
		end
		if state.Idle == "" and t >= state.NextIdleAt then
			local idle = pickIdle(state)
			state.Idle = idle
			state.IdleSince = t
			if idle == "Hop" then
				state.HopAt = t
			elseif idle == "Flutter" or idle == "Flap" then
				state.Excite = math.max(state.Excite, 0.6)
			end
		end
	end
	state.Sit = smooth(
		state.Sit,
		if state.Idle == "Sit" then 1 else 0,
		if state.Idle == "Sit" then 2 else 10,
		dt
	)
	state.Excite = math.max(0, state.Excite - dt * 1.2)

	-- Head: into turns while moving; around, or at the owner, when idle.
	local headTarget = 0
	if busy then
		headTarget = math.clamp(diff * 0.5, -0.5, 0.5)
	elseif state.Idle == "LookAround" then
		headTarget = math.sin((t - state.IdleSince) * 1.8) * 0.6
	elseif state.Idle == "LookAtOwner" or state.Idle == "Sit" then
		local toOwner = (ownerFlat - state.Position * flat)
		if toOwner.Magnitude > 0.1 then
			headTarget = math.clamp(angleDiff(state.Yaw, PetMotion.yawOf(toOwner)), -0.7, 0.7)
		end
	end
	state.HeadYaw = smooth(state.HeadYaw, headTarget, 6, dt)

	-- Height, lift and lean by kind of movement.
	local lift = 0
	local leanTarget = 0
	local hop = t - state.HopAt
	if hop >= 0 and hop < 0.4 then
		lift += math.sin(hop / 0.4 * math.pi) * (if state.Movement == "Crawling" then 0.2 else 0.45) * state.Scale
	end
	local y = input.GroundY
	if state.Movement == "Flying" then
		y = smooth(state.Position.Y, flyY(state, input), 3, dt)
		state.Bank =
			smooth(state.Bank, math.clamp(-turn / math.max(dt, 1e-3) * 0.08, -0.35, 0.35), 4, dt)
		leanTarget = 0.15 * math.min(state.GroundSpeed / walkSpeed, 1)
		local beats = state.FlapRate
			* (1 + 0.5 * math.min(state.GroundSpeed / walkSpeed, 1))
			* (1 + state.Excite)
		state.Flap += beats * 2 * math.pi * dt
	else
		if state.Movement == "Hopping" and moving then
			lift += math.max(0, math.sin(state.Phase)) * 0.55 * state.Scale
			leanTarget = math.cos(state.Phase) * 0.2
		elseif state.Movement == "Ground" then
			leanTarget = math.clamp(state.Stride - 1, 0, 1) * 0.12
		end
		state.Bank = 0
	end
	state.Lean = smooth(state.Lean, leanTarget, 10, dt)
	state.Position = Vector3.new(state.Position.X, y, state.Position.Z)

	local pivot = CFrame.new(state.Position) * facing
	local pose: PetVisual.PoseState = {
		Time = t - state.Born,
		Phase = state.Phase,
		Stride = state.Stride,
		Lift = lift,
		Lean = state.Lean,
		Bank = state.Bank,
		HeadYaw = state.HeadYaw,
		HeadPitch = if state.Idle == "LookAtOwner" then -0.12 else 0,
		Sit = state.Sit,
		Excite = state.Excite,
		Flap = state.Flap,
	}
	return pivot, pose
end

return PetMotion
