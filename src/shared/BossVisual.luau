--!strict
--[[
	Builds the cartoon monster drawn on top of a boss's server hitbox. Clients
	build it locally (UI-like presentation), so it can animate freely without
	fighting replication. Built around the origin with -Z as the front; the
	caller pivots it onto the hitbox. Sized for ArenaConfig.PlaceholderBossSize
	(6 x 8 x 6, feet at Y = -4).

	Every part is anchored and non-interactive: it must never collide, block
	raycasts or fire touches, because the server hitbox is the only gameplay part.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossVisualConfig = require(ReplicatedStorage.Config.BossVisualConfig)

local BossVisual = {}

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

local function addSign(model: Model, text: string): ()
	local position = Vector3.new(4.7, 0, -0.4)
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
	local band = addPart(
		model,
		"CrownBand",
		Enum.PartType.Cylinder,
		Vector3.new(0.8, 2.6, 2.6),
		CFrame.new(0, 2.7, 0) * CFrame.Angles(0, 0, math.rad(90)),
		gold
	)
	band.Material = Enum.Material.Metal
	for index = 0, 4 do
		local angle = index * math.pi * 2 / 5
		local spike = addPart(
			model,
			"CrownSpike",
			Enum.PartType.Block,
			Vector3.new(0.4, 0.8, 0.4),
			CFrame.new(math.cos(angle) * 1.1, 3.4, math.sin(angle) * 1.1),
			gold
		)
		spike.Material = Enum.Material.Metal
	end
end

function BossVisual.build(visual: BossVisualConfig.BossVisual): Model
	local model = Instance.new("Model")
	model.Name = "Visual"

	-- Round body with a lighter belly.
	local body = addPart(
		model,
		"Body",
		Enum.PartType.Ball,
		Vector3.new(6, 6, 6),
		CFrame.new(0, -0.5, 0),
		visual.BodyColor
	)
	addPart(
		model,
		"Belly",
		Enum.PartType.Ball,
		Vector3.new(4.2, 4.2, 4.2),
		CFrame.new(0, -0.9, -1.3),
		visual.BellyColor
	)

	-- Eyes, pupils and angry brows (inner ends lower).
	for _, side in { -1, 1 } do
		addPart(
			model,
			"Eye",
			Enum.PartType.Ball,
			Vector3.new(1.5, 1.5, 1.5),
			CFrame.new(side * 1.1, 1.3, -2.3),
			WHITE
		)
		addPart(
			model,
			"Pupil",
			Enum.PartType.Ball,
			Vector3.new(0.6, 0.6, 0.6),
			CFrame.new(side * 1.1, 1.25, -3.0),
			INK
		)
		addPart(
			model,
			"Brow",
			Enum.PartType.Block,
			Vector3.new(1.6, 0.35, 0.35),
			CFrame.new(side * 1.1, 2.2, -2.5) * CFrame.Angles(0, 0, side * math.rad(20)),
			INK
		)
	end

	-- Grumpy mouth with two teeth.
	addPart(
		model,
		"Mouth",
		Enum.PartType.Block,
		Vector3.new(2.6, 0.6, 0.4),
		CFrame.new(0, 0.1, -2.85),
		INK
	)
	for _, side in { -1, 1 } do
		addPart(
			model,
			"Tooth",
			Enum.PartType.Block,
			Vector3.new(0.45, 0.35, 0.2),
			CFrame.new(side * 0.6, 0.27, -3.08),
			WHITE
		)
	end

	-- Stubby arms angled down, round hands, flat feet.
	for _, side in { -1, 1 } do
		local tilt = CFrame.Angles(0, 0, -side * math.rad(25))
		local shoulder = CFrame.new(side * 3.3, -0.6, 0) * tilt
		addPart(
			model,
			"Arm",
			Enum.PartType.Cylinder,
			Vector3.new(3, 0.9, 0.9),
			shoulder,
			visual.LimbColor
		)
		addPart(
			model,
			"Hand",
			Enum.PartType.Ball,
			Vector3.new(1.3, 1.3, 1.3),
			shoulder * CFrame.new(side * 1.5, 0, 0),
			visual.LimbColor
		)
		addPart(
			model,
			"Foot",
			Enum.PartType.Ball,
			Vector3.new(2, 2, 2),
			CFrame.new(side * 1.4, -3.7, -0.4),
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
