--!strict
--[[
	Builds the Recreation Center (docs/PICKLEBALL.md "The Recreation
	Center"): a paved area in front of the office building (since 2026-10-10)
	under a pavilion (see pavilion()) with two pickleball courts side by side (Config/PickleballConfig.Center), spectator benches,
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
local PAD = Color3.fromRGB(118, 122, 130) -- dark paving, not a pale building-site slab
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

-- The Pet Arena kiosk (docs/PET_ARENA.md): a round battle pad with a sign,
-- west of the entrance path. Its prompt opens the Pet Arena window
-- (Controllers/PetArenaController); battles themselves are on screen.
CourtBuilder.ARENA_PROMPT_NAME = "PetArenaPrompt"
CourtBuilder.ARENA_POSITION = Vector3.new(-34, 0, 121)
local ARENA_RING = Color3.fromRGB(255, 150, 90)

local function arenaKiosk(parent: Instance): ()
	local model = Instance.new("Model")
	model.Name = "PetArena"
	local base = CourtBuilder.ARENA_POSITION + Vector3.new(0, CENTER.SurfaceY, 0)
	local pad = part(
		model,
		"ArenaPad",
		Vector3.new(0.4, 12, 12),
		base + Vector3.new(0, 0.2, 0),
		Color3.fromRGB(110, 190, 120)
	)
	pad.Shape = Enum.PartType.Cylinder
	pad.Orientation = Vector3.new(0, 0, 90)
	local rim = part(
		model,
		"ArenaRim",
		Vector3.new(0.3, 12.6, 12.6),
		base + Vector3.new(0, 0.1, 0),
		ARENA_RING
	)
	rim.Shape = Enum.PartType.Cylinder
	rim.Orientation = Vector3.new(0, 0, 90)
	local panel =
		part(model, "Sign", Vector3.new(9, 3.4, 0.6), base + Vector3.new(0, 6.5, 6.5), BOARD)
	label(panel, Enum.NormalId.Back, "🐾 PET ARENA\nBoop · Charge · Guard", BOARD_TEXT)
	label(panel, Enum.NormalId.Front, "🐾 PET ARENA", BOARD_TEXT)
	for _, x in { -4, 4 } do
		part(
			model,
			"SignLeg",
			Vector3.new(0.5, 5, 0.5),
			base + Vector3.new(x, 2.5, 6.5),
			POST,
			Enum.Material.Metal
		)
	end
	local stand =
		part(model, "PromptStand", Vector3.new(3, 3, 1), base + Vector3.new(0, 1.5, 4.5), BOARD)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = CourtBuilder.ARENA_PROMPT_NAME
	prompt.ObjectText = "Pet Arena"
	prompt.ActionText = "Battle"
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = stand
	model.Parent = parent
end

-- The Lucky Capsule Machine (docs/CAPSULE.md): a big gumball-style machine
-- east of the entrance path, across from the Pet Arena. Its prompt opens the
-- machine window (Controllers/CapsuleController), which turns the handle.
CourtBuilder.CAPSULE_PROMPT_NAME = "CapsulePrompt"
CourtBuilder.CAPSULE_POSITION = Vector3.new(34, 0, 121)
local CAPSULE_COLORS = {
	Color3.fromRGB(255, 110, 130),
	Color3.fromRGB(110, 200, 255),
	Color3.fromRGB(255, 210, 80),
	Color3.fromRGB(140, 230, 140),
	Color3.fromRGB(210, 150, 255),
	Color3.fromRGB(255, 160, 90),
}

local function capsuleMachine(parent: Instance): ()
	local model = Instance.new("Model")
	model.Name = "LuckyCapsule"
	local base = CourtBuilder.CAPSULE_POSITION + Vector3.new(0, CENTER.SurfaceY, 0)
	local red = Color3.fromRGB(215, 60, 70)
	local foot = part(
		model,
		"Foot",
		Vector3.new(1, 5, 5),
		base + Vector3.new(0, 0.5, 0),
		Color3.fromRGB(60, 62, 72),
		Enum.Material.Metal
	)
	foot.Shape = Enum.PartType.Cylinder
	foot.Orientation = Vector3.new(0, 0, 90)
	part(model, "Body", Vector3.new(4, 4, 4), base + Vector3.new(0, 3, 0), red)
	part(
		model,
		"Chute",
		Vector3.new(1.4, 1.2, 0.6),
		base + Vector3.new(0, 2, -2.2),
		Color3.fromRGB(40, 42, 50),
		Enum.Material.Metal
	)
	local handle = part(
		model,
		"CapsuleHandle",
		Vector3.new(0.3, 1.6, 0.3),
		base + Vector3.new(0, 3.6, -2.25),
		Color3.fromRGB(240, 240, 245),
		Enum.Material.Metal
	)
	handle.Orientation = Vector3.new(0, 0, 0)
	local knob = part(
		model,
		"HandleKnob",
		Vector3.new(0.6, 0.6, 0.6),
		base + Vector3.new(0, 4.4, -2.25),
		Color3.fromRGB(255, 210, 80)
	)
	knob.Shape = Enum.PartType.Ball
	local dome = part(
		model,
		"Dome",
		Vector3.new(5, 5, 5),
		base + Vector3.new(0, 7.3, 0),
		Color3.fromRGB(220, 240, 255),
		Enum.Material.Glass
	)
	dome.Shape = Enum.PartType.Ball
	dome.Transparency = 0.55
	for index, offset in
		{
			Vector3.new(-1, -1.2, -0.6),
			Vector3.new(0.9, -1.3, 0.4),
			Vector3.new(0.1, -1.4, 1.1),
			Vector3.new(-0.6, -0.4, 0.9),
			Vector3.new(0.8, -0.3, -0.8),
			Vector3.new(-1.1, 0.4, 0),
			Vector3.new(0.3, 0.5, 0.2),
			Vector3.new(1.0, 0.6, 0.6),
		}
	do
		local ball = part(
			model,
			"Capsule",
			Vector3.new(1.1, 1.1, 1.1),
			base + Vector3.new(0, 7.3, 0) + offset,
			CAPSULE_COLORS[(index - 1) % #CAPSULE_COLORS + 1]
		)
		ball.Shape = Enum.PartType.Ball
	end
	local cap = part(model, "Cap", Vector3.new(0.6, 1.6, 1.6), base + Vector3.new(0, 9.9, 0), red)
	cap.Shape = Enum.PartType.Cylinder
	cap.Orientation = Vector3.new(0, 0, 90)
	local panel = part(model, "Sign", Vector3.new(8, 3, 0.5), base + Vector3.new(0, 12.4, 0), BOARD)
	label(panel, Enum.NormalId.Back, "🎁 LUCKY CAPSULES", BOARD_TEXT)
	label(panel, Enum.NormalId.Front, "🎁 LUCKY CAPSULES", BOARD_TEXT)
	part(
		model,
		"SignPole",
		Vector3.new(0.4, 1.6, 0.4),
		base + Vector3.new(0, 10.9, 0),
		POST,
		Enum.Material.Metal
	)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = CourtBuilder.CAPSULE_PROMPT_NAME
	prompt.ObjectText = "Lucky Capsule Machine"
	prompt.ActionText = "Spin"
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = handle
	model.Parent = parent
end

-- The pavilion over the courts (visual overhaul V2): a high roof on steel
-- columns (lobs fly up to ~40 studs, so the roof is above them), a lit
-- fascia sign facing the HQ, three-tier stands down both sides, a mural
-- wall at the far end, lights under the roof and planters at the entrance.
local ROOF_Y = 42
local STEEL = Color3.fromRGB(70, 74, 86)
local ROOF = Color3.fromRGB(58, 62, 74)
local SEAT = Color3.fromRGB(60, 110, 180)

local function pavilion(parent: Instance): ()
	local area = CENTER.Area
	local pad = CENTER.SurfaceY
	local minX, maxX = area.MinX + 2, area.MaxX - 2
	local roofMinZ, roofMaxZ = area.MinZ + 12, area.MaxZ - 2
	local midZ = (roofMinZ + roofMaxZ) / 2
	local model = Instance.new("Model")
	model.Name = "Pavilion"
	model.Parent = parent

	part(
		model,
		"PavilionRoof",
		Vector3.new(maxX - minX + 2, 1.5, roofMaxZ - roofMinZ + 2),
		Vector3.new(0, pad + ROOF_Y + 0.75, midZ),
		ROOF,
		Enum.Material.Metal
	)
	-- Columns down both long sides.
	for _, x in { minX + 1, maxX - 1 } do
		for z = roofMinZ + 1, roofMaxZ - 1, (roofMaxZ - roofMinZ - 2) / 3 do
			part(
				model,
				"PavilionColumn",
				Vector3.new(1.4, ROOF_Y, 1.4),
				Vector3.new(x, pad + ROOF_Y / 2, z),
				STEEL,
				Enum.Material.Metal
			)
		end
	end
	-- The fascia over the entrance, facing the HQ (-Z), with the name.
	local fascia = part(
		model,
		"PavilionFascia",
		Vector3.new(maxX - minX + 2, 6, 1),
		Vector3.new(0, pad + ROOF_Y + 2.5, roofMinZ - 1),
		Color3.fromRGB(35, 38, 48),
		Enum.Material.Metal
	)
	local signLabel = label(fascia, Enum.NormalId.Front, "🏓  RECREATION CENTER", BOARD_TEXT)
	local gui = signLabel.Parent :: SurfaceGui
	gui.Brightness = 1.5
	-- Stands: three tiers on each long side, outside the court benches.
	for _, side in { -1, 1 } do
		for tier = 0, 2 do
			local height = 1 + tier * 1.2
			local x = side * (COURT.Width / 2 + COURT.RunOff + 24 + 5.5 + tier * 2.4)
			part(
				model,
				"Stand",
				Vector3.new(2.4, height, 52),
				Vector3.new(x, pad + height / 2, CENTER.Courts[1].Z),
				if tier % 2 == 0 then SEAT else Color3.fromRGB(80, 130, 200),
				Enum.Material.SmoothPlastic
			)
		end
	end
	-- The far wall with a mural line, facing the courts.
	local wall = part(
		model,
		"MuralWall",
		Vector3.new(maxX - minX, 12, 1),
		Vector3.new(0, pad + 6, roofMaxZ),
		Color3.fromRGB(45, 60, 90),
		Enum.Material.Concrete
	)
	label(wall, Enum.NormalId.Front, "PLAY  •  RELAX  •  REPEAT", Color3.fromRGB(255, 225, 150))
	-- Lights under the roof (dim, no shadows).
	for _, x in { -30, 0, 30 } do
		for _, z in { midZ - 18, midZ + 18 } do
			local holder = part(
				model,
				"PavilionLight",
				Vector3.new(4, 0.4, 4),
				Vector3.new(x, pad + ROOF_Y - 0.4, z),
				Color3.fromRGB(200, 200, 196)
			)
			holder.CanCollide = false
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 240, 220)
			light.Range = 50
			light.Brightness = 0.9
			light.Shadows = false
			light.Parent = holder
		end
	end
	-- Planters either side of the entrance path.
	for _, x in { -12, 12 } do
		part(
			model,
			"EntrancePlanter",
			Vector3.new(5, 2, 5),
			Vector3.new(x, pad + 1, area.MinZ + 4),
			Color3.fromRGB(72, 76, 88),
			Enum.Material.Concrete
		)
		local bush = part(
			model,
			"EntranceBush",
			Vector3.new(5, 4, 5),
			Vector3.new(x, pad + 3.5, area.MinZ + 4),
			Color3.fromRGB(70, 150, 80),
			Enum.Material.Grass
		)
		bush.Shape = Enum.PartType.Ball
	end
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
		Enum.Material.Pavement
	)
	local courts: { Court } = {}
	for index, center in CENTER.Courts do
		table.insert(courts, buildCourt(folder, index, center))
	end
	local prompt = signpost(folder)
	pavilion(folder)
	arenaKiosk(folder)
	capsuleMachine(folder)
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
