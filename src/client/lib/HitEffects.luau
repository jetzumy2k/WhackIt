--!strict
--[[
	Short, soft hit effects on a boss (local visuals, from Combat.CombatFeedback):
	  * a brief white flash on the drawn monster (one Highlight per boss, reused);
	  * a small burst of golden / white sparkles where the hammer lands;
	  * a few pastel motes that float up (your own hits and defeats);
	  * a tiny impact ring that grows and fades.

	Everything is pooled per boss: the first hit builds one rig (an Attachment
	with two emitters, a Highlight and a ring billboard) and every later hit
	only calls Emit() and restarts two prebuilt tweens. Emitters are never
	Enabled, so nothing emits on its own; particles live under a second. The rig
	is parented to the boss, so it disappears with it (defeat, respawn, streaming
	out), and the pools use weak keys so nothing is kept alive.

	Hits farther than MAX_DISTANCE from the camera show nothing, which keeps
	many bosses and many players cheap.
]]

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local HitEffects = {}

export type Hit = {
	Own: boolean, -- landed by this player
	Crit: boolean,
	Defeated: boolean, -- the defeating hit
}

HitEffects.RIG_NAME = "HitFx"

local MAX_DISTANCE = 90 -- studs from the camera
local FLASH_SECONDS = 0.1
local FLASH_FILL = 0.55 -- Highlight fill transparency: a soft flash, not a white-out
local RING_SECONDS = 0.28
local RING_STUDS = 4 -- billboard size; the ring grows to fill it
local RING_COLOR = Color3.fromRGB(255, 240, 180)

-- Sparkles per hit: others' hits get a smaller burst than your own.
local SPARKLES_OWN = 6
local SPARKLES_OTHER = 3
local SPARKLES_CRIT_BONUS = 4
local SPARKLES_DEFEAT = 14
local MOTES_OWN = 2
local MOTES_DEFEAT = 8

local SPARKLE_COLORS = {
	normal = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 220, 110)),
	crit = ColorSequence.new(Color3.fromRGB(255, 240, 170), Color3.fromRGB(255, 160, 60)),
}
local MOTE_COLORS = {
	ColorSequence.new(Color3.fromRGB(255, 170, 210)),
	ColorSequence.new(Color3.fromRGB(150, 220, 255)),
	ColorSequence.new(Color3.fromRGB(255, 235, 140)),
	ColorSequence.new(Color3.fromRGB(170, 240, 180)),
}

type Rig = {
	Sparkles: ParticleEmitter,
	Motes: ParticleEmitter,
	Ring: Frame,
	RingStroke: UIStroke,
	RingGrow: Tween,
	RingFade: Tween,
}

type Flash = {
	Highlight: Highlight,
	Count: number,
}

local rigs: { [BasePart]: Rig } = setmetatable({}, { __mode = "k" }) :: any
local flashes: { [Model]: Flash } = setmetatable({}, { __mode = "k" }) :: any
local random = Random.new()

local function newEmitter(name: string, parent: Instance): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Enabled = false -- only ever Emit()ted: no continuous emission
	emitter.Rate = 0
	emitter.LightInfluence = 0
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = parent
	return emitter
end

local function buildRig(body: BasePart): Rig
	local attachment = Instance.new("Attachment")
	attachment.Name = HitEffects.RIG_NAME
	-- Roughly where the hammer meets the monster.
	attachment.Position = Vector3.new(0, body.Size.Y / 4, 0)
	attachment.Parent = body

	local sparkles = newEmitter("Sparkles", attachment)
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.4, 0.28),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Transparency = NumberSequence.new(0, 1)
	sparkles.Lifetime = NumberRange.new(0.25, 0.45)
	sparkles.Speed = NumberRange.new(4, 8)
	sparkles.Drag = 5 -- shoot out, then hang for a moment
	sparkles.Rotation = NumberRange.new(0, 360)
	sparkles.RotSpeed = NumberRange.new(-180, 180)
	sparkles.LightEmission = 0.35
	sparkles.Color = SPARKLE_COLORS.normal

	local motes = newEmitter("Motes", attachment)
	motes.Size = NumberSequence.new(0.16, 0)
	motes.Transparency = NumberSequence.new(0.1, 1)
	motes.Lifetime = NumberRange.new(0.6, 0.9)
	motes.Speed = NumberRange.new(1, 2.5)
	motes.Acceleration = Vector3.new(0, 3, 0)
	motes.Drag = 2
	motes.LightEmission = 0.2

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ImpactRing"
	billboard.Adornee = attachment
	billboard.Size = UDim2.fromScale(RING_STUDS, RING_STUDS) -- studs
	billboard.LightInfluence = 0
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = MAX_DISTANCE
	billboard.Parent = attachment
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(0, 0)
	ring.BackgroundTransparency = 1
	ring.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = RING_COLOR
	stroke.Thickness = 3
	stroke.Transparency = 1
	stroke.Parent = ring

	local info = TweenInfo.new(RING_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	return {
		Sparkles = sparkles,
		Motes = motes,
		Ring = ring,
		RingStroke = stroke,
		-- Built once; Play() restarts them from the values reset before each hit.
		RingGrow = TweenService:Create(ring, info, { Size = UDim2.fromScale(1, 1) }),
		RingFade = TweenService:Create(stroke, info, { Transparency = 1 }),
	}
end

local function rigFor(body: BasePart): Rig
	local rig = rigs[body]
	if rig == nil then
		rig = buildRig(body)
		rigs[body] = rig
	end
	return rig :: Rig
end

-- One Highlight per drawn monster, switched on briefly per hit. A disabled
-- Highlight costs nothing and doesn't count toward Roblox's Highlight limit.
local function flashModel(visual: Model): ()
	local entry = flashes[visual]
	if entry == nil then
		local highlight = Instance.new("Highlight")
		highlight.Name = "HitFlash"
		highlight.FillColor = Color3.new(1, 1, 1)
		highlight.FillTransparency = FLASH_FILL
		highlight.OutlineTransparency = 1
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Enabled = false
		highlight.Parent = visual
		entry = { Highlight = highlight, Count = 0 }
		flashes[visual] = entry
	end
	local flash = entry :: Flash
	flash.Count += 1
	local count = flash.Count
	flash.Highlight.Enabled = true
	task.delay(FLASH_SECONDS, function()
		if flash.Count == count and flash.Highlight.Parent ~= nil then
			flash.Highlight.Enabled = false
		end
	end)
end

-- How many sparkles and motes a hit gets.
function HitEffects.counts(hit: Hit): (number, number)
	if hit.Defeated then
		return SPARKLES_DEFEAT, MOTES_DEFEAT
	end
	local sparkles = if hit.Own then SPARKLES_OWN else SPARKLES_OTHER
	if hit.Crit then
		sparkles += SPARKLES_CRIT_BONUS
	end
	return sparkles, if hit.Own then MOTES_OWN else 0
end

local function inRange(body: BasePart): boolean
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return true
	end
	return (camera.CFrame.Position - body.Position).Magnitude <= MAX_DISTANCE
end

-- Plays the hit on `body` (the boss hitbox) and flashes `visual` (the drawn
-- monster; the hitbox itself is invisible and a Highlight would show it).
function HitEffects.play(body: BasePart, visual: Model?, hit: Hit): ()
	if body.Parent == nil or not inRange(body) then
		return
	end
	if visual then
		flashModel(visual)
	end

	local rig = rigFor(body)
	local sparkles, motes = HitEffects.counts(hit)
	rig.Sparkles.Color = if hit.Crit then SPARKLE_COLORS.crit else SPARKLE_COLORS.normal
	rig.Sparkles:Emit(sparkles)
	if motes > 0 then
		rig.Motes.Color = MOTE_COLORS[random:NextInteger(1, #MOTE_COLORS)]
		rig.Motes:Emit(motes)
	end

	-- Ring: reset, then grow and fade (softer for other players' hits).
	rig.Ring.Size = UDim2.fromScale(0.15, 0.15)
	rig.RingStroke.Transparency = if hit.Own then 0.15 else 0.5
	rig.RingGrow:Play()
	rig.RingFade:Play()
end

return HitEffects
