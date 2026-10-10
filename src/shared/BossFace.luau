--!strict
--[[
	Pure rules for the bosses' faces (visual overhaul V3,
	docs/VISUAL_GAP_REVIEW.md): which expression a boss wears, its blinks,
	where its pupils look and how far its arms swing. Drawn by
	Controllers/BossVisualController on the parts Shared/BossVisual builds.
	Presentation only; bosses never attack, and every expression is friendly
	or flustered, never angry.

	Expressions (highest first):
	  Defeated  eyes closed, a big relieved smile, blushing, arms up
	  Hit       eyes squeezed shut, worried brows, an "O" mouth, blushing
	  Dizzy     worried brows, a wobbly mouth, pupils rolling
	  Surprised brows up, an "O" mouth (it noticed you)
	  Idle      a friendly smile, blinking now and then
]]

export type Mouth = "Smile" | "O" | "Wavy"

export type Expression = {
	Name: string,
	Mouth: string, -- Mouth
	BrowLift: number, -- studs up from the rest position
	BrowTilt: number, -- radians; positive = inner ends up (worried)
	EyesClosed: boolean,
	Blush: boolean,
	ArmRaise: number, -- radians the arms lift from their rest angle
}

export type State = {
	Defeated: boolean,
	HitProgress: number?, -- 0..1 while the hit reaction plays
	DizzyProgress: number?, -- 0..1 while the wobble plays
	Surprised: boolean,
}

local BossFace = {}

-- How long a squeeze-shut lasts at the start of a hit (fraction of the hit).
local SQUEEZE = 0.6
local BLINK_SECONDS = 0.14
local BLINK_EVERY_MIN = 2.6
local BLINK_EVERY_SPREAD = 2.4
-- Pupils move at most this far (studs, at scale 1) inside the eye.
BossFace.PUPIL_RANGE = 0.28
BossFace.IDLE_ARM_SWING = math.rad(7)
BossFace.HIT_ARM_RAISE = math.rad(45)

local EXPRESSIONS: { [string]: Expression } = {
	Idle = {
		Name = "Idle",
		Mouth = "Smile",
		BrowLift = 0,
		BrowTilt = 0,
		EyesClosed = false,
		Blush = false,
		ArmRaise = 0,
	},
	Surprised = {
		Name = "Surprised",
		Mouth = "O",
		BrowLift = 0.35,
		BrowTilt = 0,
		EyesClosed = false,
		Blush = false,
		ArmRaise = math.rad(20),
	},
	Hit = {
		Name = "Hit",
		Mouth = "O",
		BrowLift = 0.15,
		BrowTilt = math.rad(18),
		EyesClosed = true,
		Blush = true,
		ArmRaise = math.rad(45),
	},
	Dizzy = {
		Name = "Dizzy",
		Mouth = "Wavy",
		BrowLift = 0.1,
		BrowTilt = math.rad(14),
		EyesClosed = false,
		Blush = true,
		ArmRaise = math.rad(10),
	},
	Defeated = {
		Name = "Defeated",
		Mouth = "Smile",
		BrowLift = 0.3,
		BrowTilt = 0,
		EyesClosed = true,
		Blush = true,
		ArmRaise = math.rad(70),
	},
}
for _, expression in EXPRESSIONS do
	table.freeze(expression)
end
BossFace.Expressions = table.freeze(EXPRESSIONS)

-- The expression for a boss's current state.
function BossFace.expressionFor(state: State): Expression
	if state.Defeated then
		return EXPRESSIONS.Defeated
	end
	local hit = state.HitProgress
	if hit and hit < 1 then
		-- Squeezed shut at first, then the eyes pop open in surprise.
		if hit < SQUEEZE then
			return EXPRESSIONS.Hit
		end
		return EXPRESSIONS.Surprised
	end
	local dizzy = state.DizzyProgress
	if dizzy and dizzy < 1 then
		return EXPRESSIONS.Dizzy
	end
	if state.Surprised then
		return EXPRESSIONS.Surprised
	end
	return EXPRESSIONS.Idle
end

-- Whether the eyes are mid-blink at `now`. Each boss blinks on its own
-- rhythm (`phase`, any number), every few seconds, briefly.
function BossFace.blinking(now: number, phase: number): boolean
	local period = BLINK_EVERY_MIN + (math.abs(math.sin(phase * 12.9898)) * BLINK_EVERY_SPREAD)
	local t = (now + phase * 7.3) % period
	return t < BLINK_SECONDS
end

--[[
	Where the pupils sit, as an offset (X right, Y up) inside the eye:
	toward `lookLocal` (the target in the boss's own space, -Z = forward),
	or rolling in a circle while dizzy. At most PUPIL_RANGE from centre.
]]
function BossFace.pupilOffset(lookLocal: Vector3?, dizzyProgress: number?, now: number): Vector2
	local range = BossFace.PUPIL_RANGE
	if dizzyProgress and dizzyProgress < 1 then
		local angle = now * 14
		return Vector2.new(math.cos(angle), math.sin(angle)) * range
	end
	if lookLocal == nil or lookLocal.Magnitude < 0.01 then
		return Vector2.zero
	end
	local direction = lookLocal.Unit
	-- Only looking forwards: a target behind the boss centres the pupils.
	if direction.Z > 0 then
		return Vector2.zero
	end
	local offset = Vector2.new(direction.X, direction.Y) * range * 1.4
	if offset.Magnitude > range then
		offset = offset.Unit * range
	end
	return offset
end

-- How far the arms lift from rest (radians): the expression's raise plus a
-- gentle idle swing, a flail while hit.
function BossFace.armAngle(expression: Expression, now: number, phase: number, side: number): number
	local swing = math.sin(now * 2.2 + phase + side) * BossFace.IDLE_ARM_SWING
	if expression.Name == "Hit" then
		swing = math.sin(now * 30 + side) * math.rad(12)
	end
	return expression.ArmRaise + swing
end

return BossFace
