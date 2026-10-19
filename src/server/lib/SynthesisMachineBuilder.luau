--!strict
--[[
	The Synthesis Machine in the lobby (ArenaConfig.SynthesisMachine,
	docs/SYNTHESIS.md): a chrome-and-glass machine beside the hammer vending
	machine. Its prompt only opens the window on the client
	(SynthesisController); every synthesis goes through Synthesis.Synthesize
	and SynthesisService's checks.

	Built in the machine's own frame (front = -Z, floor at Y = 0), then turned
	into place. From the bottom up: a plinth, the OUTPUT window (an orb the
	client lights in the result's colour), a ledge with four input sockets,
	the glass synthesis chamber with a glowing core and two energy rings
	around it, and a crown with the sign. About 50 parts; one soft light and
	two small particle emitters in the core (one idles at a trickle, one only
	bursts when a synthesis plays).

	Animation is all on the client (SynthesisMachineController): each ring is
	an anchored root with its segments welded to it, so one repeating tween
	turns it; parts tagged GLOW_ATTRIBUTE pulse softly. The server bumps the
	model's PLAY_ATTRIBUTE (with the tier in TIER_ATTRIBUTE) after every
	synthesis, so everyone nearby sees the machine work.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)

local SynthesisMachineBuilder = {}

SynthesisMachineBuilder.MODEL_NAME = "SynthesisMachine"
SynthesisMachineBuilder.PROMPT_NAME = "SynthesisPrompt"
SynthesisMachineBuilder.PROMPT_ATTRIBUTE = "SynthesisMachine"
SynthesisMachineBuilder.GLOW_ATTRIBUTE = "SynthesisGlow"
SynthesisMachineBuilder.RING_ATTRIBUTE = "SynthesisRing" -- 1 or -1: spin direction
SynthesisMachineBuilder.SLOT_ATTRIBUTE = "SynthesisSlot" -- 1..4, left to right
SynthesisMachineBuilder.PLAY_ATTRIBUTE = "SynthesisPlays"
SynthesisMachineBuilder.TIER_ATTRIBUTE = "SynthesisTier"
-- Interaction range of the prompt (studs).
SynthesisMachineBuilder.PROMPT_DISTANCE = 8
SynthesisMachineBuilder.SLOT_COUNT = 4

local BODY = Color3.fromRGB(196, 202, 214)
local DARK = Color3.fromRGB(32, 36, 50)
local INNER = Color3.fromRGB(46, 52, 72)
local ACCENT = Color3.fromRGB(150, 110, 255)
local ENERGY = Color3.fromRGB(110, 235, 255)
local SIGN_TEXT = Color3.fromRGB(220, 245, 255)

local CHAMBER_Z = -0.25
local CORE_Y = 5.2

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	at: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = at
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Thin decorative bits nobody should bump into.
local function decor(p: Part): Part
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	return p
end

local function glow(p: Part, color: Color3): Part
	p.Material = Enum.Material.Neon
	p.Color = color
	p:SetAttribute(SynthesisMachineBuilder.GLOW_ATTRIBUTE, true)
	return decor(p)
end

local function surfaceText(p: BasePart, content: string, color: Color3, font: Enum.Font): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = font
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = content
	label.Parent = gui
	return label
end

-- A ring of glowing segments around the chamber, welded to an invisible
-- anchored root so the client can turn the whole ring with one tween.
local function energyRing(
	parent: Instance,
	name: string,
	center: CFrame,
	radius: number,
	direction: number
): Model
	local ring = Instance.new("Model")
	ring.Name = name
	local root = decor(part(ring, "RingRoot", Vector3.new(0.2, 0.2, 0.2), center, ENERGY))
	root.Transparency = 1
	ring.PrimaryPart = root
	local segments = 8
	for index = 1, segments do
		local angle = (index - 1) / segments * math.pi * 2
		-- Each segment lies along the ring's tangent.
		local at = center * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -radius)
		local segment = decor(part(ring, "Segment", Vector3.new(0.85, 0.12, 0.22), at, ENERGY))
		segment.Material = Enum.Material.Neon
		segment.Transparency = 0.15
		segment.Anchored = false
		segment.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = segment
		weld.Parent = segment
	end
	ring:SetAttribute(SynthesisMachineBuilder.RING_ATTRIBUTE, direction)
	ring.Parent = parent
	return ring
end

local function billboard(adornee: BasePart): ()
	local gui = Instance.new("BillboardGui")
	gui.Name = "Nameplate"
	gui.Adornee = adornee
	gui.Size = UDim2.fromScale(9, 2.2)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.Parent = adornee
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.62)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = SIGN_TEXT
	title.TextStrokeColor3 = DARK
	title.TextStrokeTransparency = 0.2
	title.Text = "⚗️ SYNTHESIS MACHINE"
	title.Parent = gui
	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromScale(0, 0.62)
	subtitle.Size = UDim2.fromScale(1, 0.38)
	subtitle.Font = Enum.Font.GothamBold
	subtitle.TextScaled = true
	subtitle.TextColor3 = ENERGY
	subtitle.TextStrokeColor3 = DARK
	subtitle.TextStrokeTransparency = 0.3
	subtitle.Text = "Combine items into something better"
	subtitle.Parent = gui
end

-- Builds the machine into `parent` at ArenaConfig.SynthesisMachine.
function SynthesisMachineBuilder.build(parent: Instance): Model
	local config = ArenaConfig.SynthesisMachine
	local origin = CFrame.new(config.Position) * CFrame.Angles(0, math.rad(config.Yaw), 0)
	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end
	-- A cylinder standing up (Roblox cylinders run along X).
	local function upright(x: number, y: number, z: number): CFrame
		return at(x, y, z) * CFrame.Angles(0, 0, math.rad(90))
	end

	local model = Instance.new("Model")
	model.Name = SynthesisMachineBuilder.MODEL_NAME
	-- Always streamed in: it sits in the lobby next to the spawn.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model:SetAttribute(SynthesisMachineBuilder.PLAY_ATTRIBUTE, 0)
	model:SetAttribute(SynthesisMachineBuilder.TIER_ATTRIBUTE, "")

	-- Plinth with a glowing edge.
	local base = part(
		model,
		"Plinth",
		Vector3.new(5.2, 0.6, 3.2),
		at(0, 0.3, 0),
		DARK,
		Enum.Material.DiamondPlate
	)
	glow(part(model, "PlinthGlow", Vector3.new(4.8, 0.1, 0.1), at(0, 0.62, -1.62), ACCENT), ACCENT)

	-- Frame: two chrome pillars with energy strips, a dark back panel.
	for _, side in { -1, 1 } do
		part(
			model,
			"Pillar",
			Vector3.new(0.9, 8, 2.6),
			at(side * 2.15, 4.6, 0.2),
			BODY,
			Enum.Material.Metal
		)
		glow(
			part(model, "PillarGlow", Vector3.new(0.1, 7, 0.1), at(side * 2.15, 4.6, -1.12), ENERGY),
			ENERGY
		)
		-- Feed pipes from the pillars into the chamber's lower collar.
		part(
			model,
			"FeedPipe",
			Vector3.new(0.9, 0.35, 0.35),
			at(side * 1.45, 3.1, CHAMBER_Z),
			INNER,
			Enum.Material.Metal
		)
	end
	part(model, "BackPanel", Vector3.new(3.4, 8, 0.3), at(0, 4.6, 1.45), INNER, Enum.Material.Metal)

	-- Lower body with the OUTPUT window: a recess, glass and the result orb.
	part(model, "LowerBody", Vector3.new(3.4, 1.6, 2.2), at(0, 1.4, 0.4), BODY, Enum.Material.Metal)
	part(model, "OutputRecess", Vector3.new(1.8, 1.3, 0.05), at(0, 1.4, -0.72), DARK)
	local outputGlass = part(
		model,
		"OutputGlass",
		Vector3.new(1.8, 1.3, 0.8),
		at(0, 1.4, -1.15),
		Color3.fromRGB(190, 225, 245),
		Enum.Material.Glass
	)
	outputGlass.Transparency = 0.7
	outputGlass.CastShadow = false
	local orb =
		decor(part(model, "OutputOrb", Vector3.new(0.7, 0.7, 0.7), at(0, 1.4, -1.15), ENERGY))
	orb.Shape = Enum.PartType.Ball
	orb.Material = Enum.Material.Neon
	orb.Transparency = 1 -- the client shows it with the result's colour
	local outputLabel =
		decor(part(model, "OutputLabel", Vector3.new(1.8, 0.28, 0.05), at(0, 0.8, -1.58), DARK))
	surfaceText(outputLabel, "OUTPUT", SIGN_TEXT, Enum.Font.GothamBold)

	-- Input ledge with four sockets (they light up as items go in).
	part(
		model,
		"InputLedge",
		Vector3.new(3.4, 0.5, 1.0),
		at(0, 2.45, -1.2),
		INNER,
		Enum.Material.Metal
	)
	for index = 1, SynthesisMachineBuilder.SLOT_COUNT do
		local x = -1.2 + (index - 1) * 0.8
		local slot =
			decor(part(model, "InputSlot", Vector3.new(0.55, 0.1, 0.55), at(x, 2.75, -1.2), ENERGY))
		slot.Material = Enum.Material.Neon
		slot.Transparency = 0.7
		slot:SetAttribute(SynthesisMachineBuilder.SLOT_ATTRIBUTE, index)
	end

	-- The synthesis chamber: collars, glass, core and two energy rings.
	part(
		model,
		"ChamberCollar",
		Vector3.new(0.4, 2.8, 2.8),
		upright(0, 3.1, CHAMBER_Z),
		BODY,
		Enum.Material.Metal
	).Shape =
		Enum.PartType.Cylinder
	part(
		model,
		"ChamberCap",
		Vector3.new(0.4, 2.8, 2.8),
		upright(0, 7.3, CHAMBER_Z),
		BODY,
		Enum.Material.Metal
	).Shape =
		Enum.PartType.Cylinder
	local glass = part(
		model,
		"ChamberGlass",
		Vector3.new(3.8, 2.4, 2.4),
		upright(0, CORE_Y, CHAMBER_Z),
		Color3.fromRGB(200, 230, 255),
		Enum.Material.Glass
	)
	glass.Shape = Enum.PartType.Cylinder
	glass.Transparency = 0.65
	glass.CastShadow = false
	local core = decor(part(model, "Core", Vector3.new(1, 1, 1), at(0, CORE_Y, CHAMBER_Z), ENERGY))
	core.Shape = Enum.PartType.Ball
	core.Material = Enum.Material.Neon
	core.Transparency = 0.1
	local light = Instance.new("PointLight")
	light.Name = "CoreLight"
	light.Color = ENERGY
	light.Range = 12
	light.Brightness = 1.2
	light.Shadows = false
	light.Parent = core
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "CoreSparks"
	sparks.Color = ColorSequence.new(ENERGY, ACCENT)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.14, 0)
	sparks.Lifetime = NumberRange.new(0.8, 1.4)
	sparks.Speed = NumberRange.new(0.4, 1)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Rate = 3
	sparks.Parent = core
	local burst = Instance.new("ParticleEmitter")
	burst.Name = "Burst"
	burst.Color = ColorSequence.new(ENERGY)
	burst.LightEmission = 1
	burst.Size = NumberSequence.new(0.3, 0)
	burst.Lifetime = NumberRange.new(0.5, 0.9)
	burst.Speed = NumberRange.new(3, 6)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Rate = 0 -- only :Emit() from the client
	burst.Parent = core
	energyRing(model, "EnergyRingLow", at(0, 4.3, CHAMBER_Z), 1.4, 1)
	energyRing(model, "EnergyRingHigh", at(0, 6.1, CHAMBER_Z), 1.4, -1)
	part(
		model,
		"Conduit",
		Vector3.new(1.2, 0.6, 0.6),
		upright(0, 8.1, CHAMBER_Z),
		INNER,
		Enum.Material.Metal
	).Shape =
		Enum.PartType.Cylinder

	-- Crown with the sign, and a nameplate that reads from across the lobby.
	local crown =
		part(model, "Crown", Vector3.new(5.6, 1.2, 3.4), at(0, 9.2, 0), BODY, Enum.Material.Metal)
	local sign = part(model, "Sign", Vector3.new(5.0, 0.9, 0.1), at(0, 9.2, -1.72), DARK)
	surfaceText(sign, "SYNTHESIS MACHINE", SIGN_TEXT, Enum.Font.FredokaOne)
	glow(part(model, "CrownGlow", Vector3.new(5.0, 0.1, 0.1), at(0, 8.55, -1.62), ACCENT), ACCENT)
	billboard(crown)

	-- The prompt sits in front of the machine at chest height.
	local anchor = Instance.new("Attachment")
	anchor.Name = "PromptAnchor"
	anchor.CFrame = base.CFrame:ToObjectSpace(at(0, 3.5, -2.4))
	anchor.Parent = base
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = SynthesisMachineBuilder.PROMPT_NAME
	prompt.ActionText = "Synthesize"
	prompt.ObjectText = "Synthesis Machine"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = SynthesisMachineBuilder.PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute(SynthesisMachineBuilder.PROMPT_ATTRIBUTE, true)
	prompt.Parent = anchor

	model.PrimaryPart = base
	model.Parent = parent
	return model
end

-- Where the server measures a player's reach from (the prompt's spot).
function SynthesisMachineBuilder.promptPosition(): Vector3
	local config = ArenaConfig.SynthesisMachine
	local origin = CFrame.new(config.Position) * CFrame.Angles(0, math.rad(config.Yaw), 0)
	return (origin * CFrame.new(0, 3.5, -2.4)).Position
end

return SynthesisMachineBuilder
