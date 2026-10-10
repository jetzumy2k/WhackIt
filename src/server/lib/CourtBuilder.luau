--!strict
--[[
	Builds the Recreation Center (docs/PICKLEBALL.md "The Recreation
	Center"): a paved area north of the office building with two pickleball
	courts side by side (Config/PickleballConfig.Center), spectator benches,
	a board per court showing its match, and a sign with a "Pickleball"
	prompt that opens the Pickleball panel (PickleballController).

	Each court: the playing surface with its lines (non-colliding paint on
	the pad), the kitchen tinted, a net between two posts, an invisible
	wall in the net's plane so nobody walks across, and a low fence around
	the run-off. About 30 anchored parts per court.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PickleballConfig = require(ReplicatedStorage.Config.PickleballConfig)

export type Court = {
	Index: number,
	Center: Vector3, -- middle of the court surface, world space
	Model: Model,
	Board: TextLabel, -- the court's match board
}

export type Center = {
	Folder: Folder,
	Courts: { Court },
	Prompt: ProximityPrompt,
}

local CourtBuilder = {}

CourtBuilder.COURT_ATTRIBUTE = "CourtIndex"
CourtBuilder.PROMPT_NAME = "PickleballPrompt"
CourtBuilder.NET_WALL_NAME = "NetWall"

local COURT = PickleballConfig.Court
local CENTER = PickleballConfig.Center
local PAD = Color3.fromRGB(150, 150, 156)
local RUN_OFF = Color3.fromRGB(70, 120, 90)
local SURFACE = Color3.fromRGB(60, 110, 170)
local KITCHEN = Color3.fromRGB(90, 140, 195)
local LINE = Color3.fromRGB(245, 245, 245)
local NET = Color3.fromRGB(30, 32, 40)
local POST = Color3.fromRGB(60, 62, 70)
local FENCE = Color3.fromRGB(40, 90, 60)
local BENCH = Color3.fromRGB(150, 105, 70)
local BOARD = Color3.fromRGB(26, 29, 41)
local BOARD_TEXT = Color3.fromRGB(255, 225, 150)

local LINE_WIDTH = 0.25
local PAINT = 0.05 -- paint thickness above the pad
local FENCE_HEIGHT = 3.5
local NET_WALL_HEIGHT = 14

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = CFrame.new(position)
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	p.Parent = parent
	return p
end

-- Flat, non-colliding paint lying on the court surface.
local function paint(
	parent: Instance,
	name: string,
	center: Vector3,
	sizeX: number,
	sizeZ: number,
	height: number,
	color: Color3
): Part
	local p = part(
		parent,
		name,
		Vector3.new(sizeX, PAINT, sizeZ),
		center + Vector3.new(0, height + PAINT / 2, 0),
		color
	)
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	return p
end

local function label(surface: BasePart, face: Enum.NormalId, text: string, color: Color3): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = surface
	local text_ = Instance.new("TextLabel")
	text_.Size = UDim2.fromScale(1, 1)
	text_.BackgroundTransparency = 1
	text_.Font = Enum.Font.FredokaOne
	text_.TextScaled = true
	text_.TextColor3 = color
	text_.Text = text
	text_.RichText = false
	text_.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.06, 0)
	padding.PaddingBottom = UDim.new(0.06, 0)
	padding.Parent = text_
	return text_
end

-- The lines: sidelines, baselines, kitchen lines and the centre lines of
-- the service courts (not through the kitchen).
local function lines(parent: Instance, center: Vector3): ()
	local halfWidth, halfLength, kitchen = COURT.Width / 2, COURT.Length / 2, COURT.Kitchen
	local h = PAINT * 2
	for _, x in { -halfWidth, halfWidth } do
		paint(parent, "Sideline", center + Vector3.new(x, 0, 0), LINE_WIDTH, COURT.Length, h, LINE)
	end
	for _, z in { -halfLength, halfLength, -kitchen, kitchen } do
		paint(parent, "Line", center + Vector3.new(0, 0, z), COURT.Width, LINE_WIDTH, h, LINE)
	end
	local serviceDepth = halfLength - kitchen
	for _, sign in { -1, 1 } do
		local z = sign * (kitchen + serviceDepth / 2)
		paint(
			parent,
			"CenterLine",
			center + Vector3.new(0, 0, z),
			LINE_WIDTH,
			serviceDepth,
			h,
			LINE
		)
	end
end

local function net(parent: Instance, center: Vector3): ()
	local span = COURT.Width + 2 * COURT.NetOverhang
	for _, sign in { -1, 1 } do
		part(
			parent,
			"NetPost",
			Vector3.new(0.4, COURT.NetHeightSide + 0.3, 0.4),
			center + Vector3.new(sign * span / 2, (COURT.NetHeightSide + 0.3) / 2, 0),
			POST,
			Enum.Material.Metal
		)
	end
	-- The mesh: drawn at the centre height (the ball's net check uses the
	-- exact shape, Shared/BallFlight.netHeightAt).
	local mesh = part(
		parent,
		"Net",
		Vector3.new(span, COURT.NetHeightCenter - 0.4, 0.08),
		center + Vector3.new(0, 0.4 + (COURT.NetHeightCenter - 0.4) / 2, 0),
		NET
	)
	mesh.Transparency = 0.45
	mesh.CanCollide = false
	mesh.CastShadow = false
	local tape = part(
		parent,
		"NetTape",
		Vector3.new(span, 0.2, 0.12),
		center + Vector3.new(0, COURT.NetHeightCenter - 0.1, 0),
		LINE
	)
	tape.CanCollide = false
	-- Nobody walks or jumps across to the other side.
	local wall = part(
		parent,
		CourtBuilder.NET_WALL_NAME,
		Vector3.new(COURT.Width + 2 * COURT.RunOff, NET_WALL_HEIGHT, 0.5),
		center + Vector3.new(0, NET_WALL_HEIGHT / 2, 0),
		NET
	)
	wall.Transparency = 1
	wall.CanQuery = false
	wall.CastShadow = false
end

-- A low fence around the run-off, open in the middle of each long side.
local function fence(parent: Instance, center: Vector3): ()
	local width = COURT.Width + 2 * COURT.RunOff
	local length = COURT.Length + 2 * COURT.RunOff
	local y = FENCE_HEIGHT / 2
	for _, sign in { -1, 1 } do
		part(
			parent,
			"Fence",
			Vector3.new(width, FENCE_HEIGHT, 0.4),
			center + Vector3.new(0, y, sign * length / 2),
			FENCE,
			Enum.Material.Fabric
		)
		-- Long sides in two pieces, leaving a gap at the net for spectators
		-- to look through (the net wall still blocks crossing).
		local piece = length / 2 - 2
		for _, half in { -1, 1 } do
			part(
				parent,
				"Fence",
				Vector3.new(0.4, FENCE_HEIGHT, piece),
				center + Vector3.new(sign * width / 2, y, half * (2 + piece / 2)),
				FENCE,
				Enum.Material.Fabric
			)
		end
	end
end

local function board(parent: Instance, center: Vector3, index: number): TextLabel
	local z = center.Z - (COURT.Length / 2 + COURT.RunOff + 1.5)
	local panel = part(
		parent,
		"Board",
		Vector3.new(14, 4, 0.4),
		Vector3.new(center.X, center.Y + 7, z),
		BOARD
	)
	for _, x in { -6, 6 } do
		part(
			parent,
			"BoardLeg",
			Vector3.new(0.4, 5, 0.4),
			Vector3.new(center.X + x, center.Y + 2.5, z),
			POST,
			Enum.Material.Metal
		)
	end
	return label(panel, Enum.NormalId.Back, string.format("Court %d\nFree", index), BOARD_TEXT)
end

local function benches(parent: Instance, center: Vector3): ()
	-- Along the outer long side of the court, facing it.
	local side = if center.X < 0 then -1 else 1
	local x = center.X + side * (COURT.Width / 2 + COURT.RunOff + 3)
	for _, z in { -12, 0, 12 } do
		part(
			parent,
			"Bench",
			Vector3.new(2, 0.4, 8),
			Vector3.new(x, center.Y + 1.6, center.Z + z),
			BENCH,
			Enum.Material.Wood
		)
		part(
			parent,
			"BenchLeg",
			Vector3.new(1.6, 1.4, 7),
			Vector3.new(x, center.Y + 0.7, center.Z + z),
			POST,
			Enum.Material.Metal
		)
	end
end

local function buildCourt(parent: Instance, index: number, center: Vector3): Court
	local model = Instance.new("Model")
	model.Name = "Court" .. index
	model:SetAttribute(CourtBuilder.COURT_ATTRIBUTE, index)
	paint(
		model,
		"RunOff",
		center,
		COURT.Width + 2 * COURT.RunOff,
		COURT.Length + 2 * COURT.RunOff,
		0,
		RUN_OFF
	)
	paint(model, "Surface", center, COURT.Width, COURT.Length, PAINT / 2, SURFACE)
	for _, sign in { -1, 1 } do
		paint(
			model,
			"Kitchen",
			center + Vector3.new(0, 0, sign * COURT.Kitchen / 2),
			COURT.Width,
			COURT.Kitchen,
			PAINT,
			KITCHEN
		)
	end
	lines(model, center)
	net(model, center)
	fence(model, center)
	benches(model, center)
	local text = board(model, center, index)
	model.Parent = parent
	return { Index = index, Center = center, Model = model, Board = text }
end

local function signpost(parent: Instance): ProximityPrompt
	local position = CENTER.BoardPosition
	local panel =
		part(parent, "Sign", Vector3.new(10, 4, 0.6), position + Vector3.new(0, 6, 0), BOARD)
	label(panel, Enum.NormalId.Back, "🏓 RECREATION CENTER\nPickleball courts", BOARD_TEXT)
	label(panel, Enum.NormalId.Front, "🏓 RECREATION CENTER", BOARD_TEXT)
	for _, x in { -4.5, 4.5 } do
		part(
			parent,
			"SignLeg",
			Vector3.new(0.5, 4, 0.5),
			position + Vector3.new(x, 2, 0),
			POST,
			Enum.Material.Metal
		)
	end
	local stand =
		part(parent, "PromptStand", Vector3.new(3, 3, 1), position + Vector3.new(0, 1.5, 2), BOARD)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = CourtBuilder.PROMPT_NAME
	prompt.ObjectText = "Recreation Center"
	prompt.ActionText = "Pickleball"
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = stand
	return prompt
end

function CourtBuilder.build(parent: Instance): Center
	local folder = Instance.new("Folder")
	folder.Name = "RecreationCenter"
	local area = CENTER.Area
	local padTop = CENTER.SurfaceY
	part(
		folder,
		"Pad",
		Vector3.new(area.MaxX - area.MinX, 1, area.MaxZ - area.MinZ),
		Vector3.new((area.MinX + area.MaxX) / 2, padTop - 0.5, (area.MinZ + area.MaxZ) / 2),
		PAD,
		Enum.Material.Concrete
	)
	local courts: { Court } = {}
	for index, center in CENTER.Courts do
		table.insert(courts, buildCourt(folder, index, center))
	end
	local prompt = signpost(folder)
	folder.Parent = parent
	return { Folder = folder, Courts = courts, Prompt = prompt }
end

-- World position of a court-local point (courts are axis-aligned).
function CourtBuilder.toWorld(center: Vector3, localPoint: Vector3): Vector3
	return center + localPoint
end

function CourtBuilder.toLocal(center: Vector3, worldPoint: Vector3): Vector3
	return worldPoint - center
end

return CourtBuilder
