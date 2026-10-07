--!strict
--[[
	Pure motion maths for the drawn bosses (Controllers/BossVisualController):
	idle bob / sway / shuffle per personality, the occasional fidget, the
	surprised hop when a player walks up, and the dizzy wobble after a hit.
	No Instances, so specs can check every motion stays small. The server's
	hitbox never moves; these only offset the drawn monster a little.

	All angles are radians; offsets are studs.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossPersonalityConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BossPersonalityConfig"))

export type Offsets = {
	Lift: number, -- up
	Shuffle: number, -- sideways (the monster's own X)
	Yaw: number, -- extra turn
	Lean: number, -- top tips back (+) or forward (-)
	Roll: number, -- head tilt
	Scale: number, -- 1 = normal
}

local BossMotion = {}

-- How long the surprised hop and the dizzy wobble last.
BossMotion.SURPRISE_SECONDS = 0.45
BossMotion.WOBBLE_SECONDS = 0.6

local SURPRISE_HOP = 0.9
local SURPRISE_POP = 0.05
local WOBBLE_YAW = math.rad(14)

local function pulse(progress: number): number
	return math.sin(math.clamp(progress, 0, 1) * math.pi)
end

-- Idle motion at time `now` (seconds); `phase` de-syncs bosses.
function BossMotion.idle(
	personality: BossPersonalityConfig.Personality,
	now: number,
	phase: number
): Offsets
	return {
		Lift = math.sin(now * personality.BobSpeed + phase) * personality.BobHeight,
		Shuffle = math.sin(now * personality.ShuffleSpeed + phase * 0.7) * personality.ShuffleStuds,
		Yaw = math.sin(now * personality.SwaySpeed + phase) * math.rad(personality.SwayDegrees),
		Lean = 0,
		Roll = 0,
		Scale = 1,
	}
end

-- Where a boss looks when nobody is near: around its home direction.
function BossMotion.lookAround(
	personality: BossPersonalityConfig.Personality,
	homeYaw: number,
	now: number,
	phase: number
): number
	return homeYaw
		+ math.sin(now * personality.LookSpeed + phase) * math.rad(personality.LookDegrees)
end

-- A fidget `progress` (0..1) of the way through.
function BossMotion.fidget(kind: string, progress: number): Offsets
	local p = math.clamp(progress, 0, 1)
	local bump = pulse(p)
	local offsets: Offsets = { Lift = 0, Shuffle = 0, Yaw = 0, Lean = 0, Roll = 0, Scale = 1 }
	if kind == "Hurry" then
		-- Two quick foot-taps.
		offsets.Lift = math.abs(math.sin(p * 2 * math.pi)) * 0.35
	elseif kind == "Glance" then
		-- A nervous look over one shoulder and back.
		offsets.Yaw = math.sin(p * 2 * math.pi) * math.rad(30)
	elseif kind == "Jitter" then
		-- Flinches at an incoming "ping".
		offsets.Shuffle = math.sin(p * 40) * 0.08 * (1 - p)
		offsets.Scale = 1 + bump * 0.03
	elseif kind == "Tilt" then
		-- Tilts its head: "huh?"
		offsets.Roll = bump * math.rad(14)
	elseif kind == "Yawn" then
		offsets.Lean = bump * math.rad(10)
		offsets.Scale = 1 + bump * 0.06
	elseif kind == "Puff" then
		offsets.Lean = bump * math.rad(5)
		offsets.Scale = 1 + bump * 0.07
	end
	return offsets
end

-- The surprised hop when a player walks up, `progress` 0..1.
function BossMotion.surprise(progress: number): Offsets
	local bump = pulse(progress)
	return {
		Lift = bump * SURPRISE_HOP,
		Shuffle = 0,
		Yaw = 0,
		Lean = bump * math.rad(6),
		Roll = 0,
		Scale = 1 + bump * SURPRISE_POP,
	}
end

-- A dizzy little wobble after the hit hop, `progress` 0..1.
function BossMotion.wobble(progress: number): number
	local p = math.clamp(progress, 0, 1)
	return math.sin(p * math.pi * 3) * (1 - p) * WOBBLE_YAW
end

-- Adds `b` onto `a` (scales multiply).
function BossMotion.add(a: Offsets, b: Offsets): Offsets
	return {
		Lift = a.Lift + b.Lift,
		Shuffle = a.Shuffle + b.Shuffle,
		Yaw = a.Yaw + b.Yaw,
		Lean = a.Lean + b.Lean,
		Roll = a.Roll + b.Roll,
		Scale = a.Scale * b.Scale,
	}
end

return BossMotion
