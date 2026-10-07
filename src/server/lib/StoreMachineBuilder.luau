--!strict
--[[
	The hammer vending machine in the lobby (ArenaConfig.StoreMachine): a
	walk-up way into the existing Hammers shop. It only holds a ProximityPrompt;
	the client opens the shop panel (StoreMachineController -> ShopController),
	and buying still goes through Shop.BuyHammer, checked by the server
	(ShopService). No new currency, inventory or purchase path.

	Built in the machine's own frame (front = -Z, floor at Y = 0), then turned
	into place. About 25 anchored parts plus three small display hammers drawn
	with Shared/HammerModel (the same looks as the real ones). Each display
	hammer's Handle is anchored and the rest welded to it, so the client can
	sway it gently (DISPLAY_ATTRIBUTE). Neon accents are thin strips tagged
	GLOW_ATTRIBUTE for the client's soft pulse.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local HammerModel = require(ReplicatedStorage.Shared.HammerModel)
local HammerStyleConfig = require(ReplicatedStorage.Config.HammerStyleConfig)

local StoreMachineBuilder = {}

StoreMachineBuilder.MODEL_NAME = "HammerVendingMachine"
StoreMachineBuilder.PROMPT_ATTRIBUTE = "StoreMachine"
StoreMachineBuilder.DISPLAY_ATTRIBUTE = "StoreDisplay"
StoreMachineBuilder.GLOW_ATTRIBUTE = "StoreGlow"
-- Interaction range of the prompt (studs).
StoreMachineBuilder.PROMPT_DISTANCE = 8

local BODY = Color3.fromRGB(50, 110, 210)
local TRIM = Color3.fromRGB(255, 150, 60)
local DARK = Color3.fromRGB(30, 32, 42)
local INNER = Color3.fromRGB(45, 48, 62)
local METAL = Color3.fromRGB(170, 175, 185)
local NEON = Color3.fromRGB(90, 230, 255)
local SIGN_TEXT = Color3.fromRGB(255, 235, 140)

-- Cheap to pricey, one per shelf, bottom to top.
local DISPLAY_STYLES = { "squeaky", "golden", "cosmic" }
local DISPLAY_SCALE = 0.32

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

local function text(p: BasePart, face: Enum.NormalId, content: string, color: Color3): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = content
	label.Parent = gui
	return label
end

local function glow(p: BasePart): ()
	p.Material = Enum.Material.Neon
	p.Color = NEON
	p.Transparency = 0.35
	p.CastShadow = false
	p.CanCollide = false
	p:SetAttribute(StoreMachineBuilder.GLOW_ATTRIBUTE, true)
end

local function displayHammer(parent: Instance, styleId: string, at: CFrame): ()
	local style = HammerStyleConfig.ById[styleId]
	if style == nil then
		return
	end
	local model = Instance.new("Model")
	model.Name = "Display_" .. styleId
	-- Standing on its pommel, head up, its side towards the glass (the shaft
	-- runs along Z when built, so tip it up, then turn the head's length across).
	local upright = CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(90), 0, 0)
	local built = HammerModel.build(style, model, upright, false)
	built.Handle.Anchored = true
	model.PrimaryPart = built.Handle
	model:ScaleTo(DISPLAY_SCALE)
	model:PivotTo(at)
	model:SetAttribute(StoreMachineBuilder.DISPLAY_ATTRIBUTE, true)
	model.Parent = parent
end

-- Builds the machine into `parent` at ArenaConfig.StoreMachine.
function StoreMachineBuilder.build(parent: Instance): Model
	local config = ArenaConfig.StoreMachine
	local origin = CFrame.new(config.Position) * CFrame.Angles(0, math.rad(config.Yaw), 0)
	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end

	local model = Instance.new("Model")
	model.Name = StoreMachineBuilder.MODEL_NAME
	-- Always streamed in: it sits in the lobby next to the spawn.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	-- Cabinet: back block, right control column, base and top cap. The space
	-- between them at the front-left is the display window.
	local back = part(model, "Cabinet", Vector3.new(4.4, 7.6, 2.2), at(0, 3.8, 0.4), BODY)
	part(model, "ControlColumn", Vector3.new(1.3, 7.6, 0.8), at(1.55, 3.8, -1.1), BODY)
	part(model, "Base", Vector3.new(4.4, 0.8, 0.8), at(0, 0.4, -1.1), DARK)
	part(model, "TopCap", Vector3.new(4.4, 0.9, 0.8), at(0, 7.15, -1.1), BODY)
	part(model, "SideTrimLeft", Vector3.new(0.25, 7.6, 3.05), at(-2.32, 3.8, -0.03), TRIM)
	part(model, "SideTrimRight", Vector3.new(0.25, 7.6, 3.05), at(2.32, 3.8, -0.03), TRIM)

	-- Branding on the top cap.
	local sign = part(model, "Sign", Vector3.new(4.2, 0.8, 0.1), at(0, 7.15, -1.55), DARK)
	text(sign, Enum.NormalId.Front, "HAMMER STORE", SIGN_TEXT)
	glow(part(model, "SignGlow", Vector3.new(4.2, 0.1, 0.1), at(0, 6.65, -1.56), NEON))

	-- Display window: dark back, three shelves, glass front, glowing edges.
	part(model, "DisplayBack", Vector3.new(3.1, 5.9, 0.05), at(-0.65, 3.75, -0.72), INNER)
	local shelfHeights = { 1.0, 2.75, 4.5 }
	for index, y in shelfHeights do
		part(
			model,
			"Shelf",
			Vector3.new(3.0, 0.1, 0.7),
			at(-0.65, y, -1.1),
			METAL,
			Enum.Material.Metal
		)
		displayHammer(model, DISPLAY_STYLES[index], at(-0.65, y + 0.85, -1.1))
	end
	local window = part(
		model,
		"Glass",
		Vector3.new(3.1, 5.9, 0.1),
		at(-0.65, 3.75, -1.47),
		Color3.fromRGB(190, 225, 245),
		Enum.Material.Glass
	)
	window.Transparency = 0.6
	window.CastShadow = false
	for _, x in { -2.2, 0.9 } do
		glow(part(model, "WindowGlow", Vector3.new(0.08, 5.9, 0.08), at(x, 3.75, -1.52), NEON))
	end

	-- Control column: small screen, keypad, coin slot.
	local screen = part(model, "Screen", Vector3.new(1.0, 0.75, 0.06), at(1.55, 5.9, -1.53), DARK)
	text(screen, Enum.NormalId.Front, "PRESS E\nfor hammers", Color3.fromRGB(120, 255, 170))
	local keyColors = {
		Color3.fromRGB(255, 110, 110),
		Color3.fromRGB(255, 220, 90),
		Color3.fromRGB(120, 220, 130),
		Color3.fromRGB(110, 170, 255),
		Color3.fromRGB(200, 140, 255),
		Color3.fromRGB(240, 240, 245),
	}
	for index, color in keyColors do
		local column = (index - 1) % 3
		local row = (index - 1) // 3
		local key = part(
			model,
			"Key",
			Vector3.new(0.24, 0.24, 0.08),
			at(1.25 + column * 0.3, 4.95 - row * 0.32, -1.53),
			color
		)
		key.CanCollide = false
	end
	part(model, "CoinSlot", Vector3.new(0.14, 0.5, 0.06), at(1.55, 4.05, -1.53), DARK)
	local coinLabel =
		part(model, "CoinLabel", Vector3.new(1.0, 0.3, 0.05), at(1.55, 3.6, -1.53), BODY)
	text(coinLabel, Enum.NormalId.Front, "COINS ONLY", SIGN_TEXT)
	-- Pickup tray along the base.
	local tray = part(model, "Tray", Vector3.new(2.8, 0.45, 0.08), at(-0.65, 0.4, -1.53), DARK)
	text(tray, Enum.NormalId.Front, "PUSH", Color3.fromRGB(180, 185, 200))

	-- The prompt sits in front of the machine at chest height.
	local anchor = Instance.new("Attachment")
	anchor.Name = "PromptAnchor"
	anchor.CFrame = back.CFrame:ToObjectSpace(at(0, 3.5, -2))
	anchor.Parent = back
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenHammerStore"
	prompt.ActionText = "Open Hammer Store"
	prompt.ObjectText = "Hammer Vending Machine"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = StoreMachineBuilder.PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute(StoreMachineBuilder.PROMPT_ATTRIBUTE, true)
	prompt.Parent = anchor

	model.PrimaryPart = back
	model.Parent = parent
	return model
end

return StoreMachineBuilder
