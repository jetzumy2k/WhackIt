--!strict
--[[
	Builds the cartoon monster drawn on top of a boss's server hitbox. Clients
	build it locally (UI-like presentation), so it can animate freely without
	fighting replication. Built around the origin with -Z as the front; the
	caller pivots it onto the hitbox. Sized for ArenaConfig.PlaceholderBossSize
	(6 x 8 x 6, feet at Y = -4). Since V3 a rounded mascot built from
	ellipsoids (see build()).

	Every part is anchored and non-interactive: it must never collide, block
	raycasts or fire touches, because the server hitbox is the only gameplay part.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossVisualConfig = require(ReplicatedStorage.Config.BossVisualConfig)

local BossVisual = {}

-- -1 / 1 on the face and arm parts of each side (Controllers/BossVisualController).
BossVisual.SIDE_ATTRIBUTE = "Side"
-- Where each arm turns from (the shoulder joint, at scale 1), by side.
BossVisual.SHOULDER = Vector3.new(2.5, -0.2, 0)

local WHITE = Color3.fromRGB(255, 255, 255)
local INK = Color3.fromRGB(30, 25, 35)
local SIGN_COLOR = Color3.fromRGB(250, 245, 225)
local STICK_COLOR = Color3.fromRGB(150, 105, 60)

local function addPart(
	model: Model,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	cframe: CFrame,
	color: Color3
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = model
	return part
end

-- A smooth ellipsoid of `size` (a block with a built-in sphere mesh, so it
-- needs no uploaded asset and can be any proportion).
local function addOval(
	model: Model,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3
): Part
	local part = addPart(model, name, Enum.PartType.Block, size, cframe, color)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

local function addSign(model: Model, text: string): ()
	-- Held up by the right hand (the stick starts at the hand).
	local position = Vector3.new(4.3, -0.4, -0.5)
	addPart(
		model,
		"SignStick",
		Enum.PartType.Block,
		Vector3.new(0.25, 2.6, 0.25),
		CFrame.new(position),
		STICK_COLOR
	)
	local board = addPart(
		model,
		"SignBoard",
		Enum.PartType.Block,
		Vector3.new(3.2, 1.8, 0.2),
		CFrame.new(position + Vector3.new(0, 2, 0)),
		SIGN_COLOR
	)

	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.LightInfluence = 0
	surface.PixelsPerStud = 60
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.Parent = board

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = INK
	label.Text = text
	label.Parent = surface
end

-- A small gold crown on top of the head for Senior bosses.
local function addCrown(model: Model): ()
	local gold = Color3.fromRGB(255, 205, 60)
	local top = 3.55
	local band = addPart(
		model,
		"CrownBand",
		Enum.PartType.Cylinder,
		Vector3.new(0.6, 2.2, 2.2),
		CFrame.new(0, top, 0) * CFrame.Angles(0, 0, math.rad(90)),
		gold
	)
	band.Material = Enum.Material.Metal
	for index = 0, 4 do
		local angle = index * math.pi * 2 / 5
		local spike = addOval(
			model,
			"CrownSpike",
			Vector3.new(0.45, 0.8, 0.45),
			CFrame.new(math.cos(angle) * 0.9, top + 0.6, math.sin(angle) * 0.9),
			gold
		)
		spike.Material = Enum.Material.Metal
	end
end

function BossVisual.build(visual: BossVisualConfig.BossVisual): Model
	local model = Instance.new("Model")
	model.Name = "Visual"

	--[[
		A rounded mascot (visual overhaul V3, redone after owner feedback): an
		egg-shaped body with a lighter belly, a face set into its front (oval
		eyes with a shine, thin brows, an open smile with a tongue), short
		stubby arms and oval feet. Everything is an ellipsoid (addOval), so
		nothing reads as a bar or a stick. Face part names and Side
		attributes are what Controllers/BossVisualController animates
		(Shared/BossFace): only one mouth and one eye state is shown at a time.
		The body's front surface is at z = -2.8 at the middle of the face;
		face parts sit just on it.
	]]
	local BODY_Y = -0.2
	local body =
		addOval(model, "Body", Vector3.new(6, 7.4, 5.6), CFrame.new(0, BODY_Y, 0), visual.BodyColor)
	body.Reflectance = 0.04
	addOval(model, "Belly", Vector3.new(4.2, 3.8, 2), CFrame.new(0, -2, -1.75), visual.BellyColor)

	local function sided(p: Part, side: number): Part
		p:SetAttribute(BossVisual.SIDE_ATTRIBUTE, side)
		return p
	end
	for _, side in { -1, 1 } do
		local x = side * 0.95
		sided(
			addOval(model, "Eye", Vector3.new(1.35, 1.65, 0.7), CFrame.new(x, 1.25, -2.3), WHITE),
			side
		)
		sided(
			addOval(model, "Pupil", Vector3.new(0.62, 0.8, 0.25), CFrame.new(x, 1.15, -2.66), INK),
			side
		)
		sided(
			addOval(
				model,
				"Shine",
				Vector3.new(0.24, 0.28, 0.1),
				CFrame.new(x + 0.14, 1.38, -2.79),
				WHITE
			),
			side
		)
		-- Closed eyes: a happy "^" of two short strokes (hidden unless blinking).
		for _, tilt in { -1, 1 } do
			local stroke = sided(
				addOval(
					model,
					"EyeClosed",
					Vector3.new(0.75, 0.2, 0.2),
					CFrame.new(x + tilt * 0.28, 1.25, -2.62)
						* CFrame.Angles(0, 0, -tilt * math.rad(30)),
					INK
				),
				side
			)
			stroke.Transparency = 1
		end
		sided(
			addOval(model, "Brow", Vector3.new(1.0, 0.22, 0.22), CFrame.new(x, 2.2, -1.9), INK),
			side
		)
		local blush = sided(
			addOval(
				model,
				"Blush",
				Vector3.new(0.85, 0.45, 0.2),
				CFrame.new(side * 1.85, 0.35, -2.1),
				Color3.fromRGB(255, 140, 160)
			),
			side
		)
		blush.Transparency = 1
	end

	-- Mouths (one shown at a time). The smile: a dark oval with a pink tongue,
	-- its top half covered by a body-coloured oval, so it reads as a "D".
	addOval(model, "MouthSmile", Vector3.new(1.7, 0.95, 0.3), CFrame.new(0, -0.15, -2.74), INK)
	addOval(
		model,
		"MouthSmile",
		Vector3.new(0.9, 0.4, 0.2),
		CFrame.new(0, -0.42, -2.82),
		Color3.fromRGB(240, 120, 130)
	)
	addOval(
		model,
		"MouthSmile",
		Vector3.new(1.85, 0.62, 0.32),
		CFrame.new(0, 0.14, -2.79),
		visual.BodyColor
	)
	-- The "O": a round open mouth with a tongue.
	local o = addOval(model, "MouthO", Vector3.new(0.85, 1.0, 0.3), CFrame.new(0, -0.1, -2.75), INK)
	o.Transparency = 1
	local oTongue = addOval(
		model,
		"MouthO",
		Vector3.new(0.5, 0.3, 0.15),
		CFrame.new(0, -0.38, -2.86),
		Color3.fromRGB(240, 120, 130)
	)
	oTongue.Transparency = 1
	-- The wobbly mouth (dizzy): two thin strokes in a gentle zigzag.
	for _, tilt in { -1, 1 } do
		local stroke = addOval(
			model,
			"MouthWavy",
			Vector3.new(0.9, 0.2, 0.2),
			CFrame.new(tilt * 0.38, -0.1, -2.8) * CFrame.Angles(0, 0, tilt * math.rad(18)),
			INK
		)
		stroke.Transparency = 1
	end

	-- Short, stubby arms angled out and down, and oval feet.
	for _, side in { -1, 1 } do
		local arm = addOval(
			model,
			"Arm",
			Vector3.new(1.3, 2.5, 1.3),
			CFrame.new(side * 3.05, -0.9, -0.1) * CFrame.Angles(0, 0, side * math.rad(40)),
			visual.LimbColor
		)
		sided(arm, side)
		local hand = addOval(
			model,
			"Hand",
			Vector3.new(1.25, 1.25, 1.25),
			CFrame.new(side * 3.85, -1.75, -0.15),
			visual.LimbColor
		)
		sided(hand, side)
		addOval(
			model,
			"Foot",
			Vector3.new(2, 1, 2.6),
			CFrame.new(side * 1.35, -3.5, -0.5),
			visual.LimbColor
		)
	end

	addSign(model, visual.SignText)
	if visual.Crown then
		addCrown(model)
	end

	model.PrimaryPart = body
	model.WorldPivot = CFrame.identity
	return model
end

return BossVisual
