--!strict
--[[
	Interior finish for the headquarters (visual overhaul V1c,
	docs/VISUAL_GAP_REVIEW.md): built after Lib/OfficeBuilder and only where
	nothing walks through, so every existing position and spec stays as it
	was.

	  * Lobby: a stone floor finish, a reception front with a sign, a monitor
	    and a bell, a lounge rug and coffee tables between the couches,
	    pendant lights hanging in the atrium, and a floor guide by the
	    corridor showing what's on each floor and where the elevator is.
	  * Corridors: framed posters (office jokes) on the corridor walls of the
	    ground and Senior floors. Each floor's carpet colour is set in
	    OfficeBuilder.
	  * Podium rooms: a wood slat feature wall in the Break Room, acoustic
	    panels in the Meeting Room.

	Surfaces stay muted and lights dim (OfficeBuilder eye-comfort specs).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)

local InteriorBuilder = {}

local DARK = Color3.fromRGB(40, 42, 50)
local FRAME = Color3.fromRGB(35, 38, 48)
local TEXT = Color3.fromRGB(255, 210, 120)
local LIGHT_COLOR = Color3.fromRGB(255, 236, 214)
local LOBBY_HALF = 36
local CORRIDOR_SOUTH = 0 -- the corridor's south wall (z 0, 1 thick)

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
	p.Position = position
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function decor(p: Part): Part
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function signText(
	p: BasePart,
	face: Enum.NormalId,
	text: string,
	color: Color3?,
	font: Enum.Font?
): ()
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = font or Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = color or TEXT
	label.Text = text
	label.Parent = gui
end

-- Lobby ---------------------------------------------------------------------------------

local function buildLobby(parent: Instance): ()
	local lobby = Instance.new("Model")
	lobby.Name = "Lobby Finish"
	lobby.Parent = parent
	local south = ArenaConfig.BuildingSouthZ

	-- A stone floor finish over the whole lobby (thin, under everything).
	decor(
		part(
			lobby,
			"LobbyStone",
			Vector3.new(LOBBY_HALF * 2 - 1, 0.05, south - CORRIDOR_SOUTH - 1),
			Vector3.new(0, 0.025, (south + CORRIDOR_SOUTH) / 2),
			Color3.fromRGB(112, 110, 106),
			Enum.Material.Marble
		)
	)

	-- Reception: a front panel with the sign, a monitor and a bell on the desk
	-- (the desk itself is OfficeBuilder's, at x -22, z 12).
	local front = part(
		lobby,
		"ReceptionFront",
		Vector3.new(12, 2.6, 0.2),
		Vector3.new(-22, 1.75, 13.6),
		FRAME,
		Enum.Material.Metal
	)
	signText(front, Enum.NormalId.Back, "RECEPTION · Welcome to Whack It Out!")
	part(
		lobby,
		"ReceptionMonitor",
		Vector3.new(2.6, 1.6, 0.2),
		Vector3.new(-25, 4.8, 11.6),
		DARK,
		Enum.Material.Glass
	)
	local bell = part(
		lobby,
		"ReceptionBell",
		Vector3.new(0.8, 0.5, 0.8),
		Vector3.new(-18, 4.15, 12.6),
		Color3.fromRGB(200, 170, 90),
		Enum.Material.Metal
	)
	bell.Shape = Enum.PartType.Ball

	-- The lounge by the front glass: a rug and two low tables between the couches.
	decor(
		part(
			lobby,
			"LoungeRug",
			Vector3.new(34, 0.05, 6),
			Vector3.new(0, 0.08, 27),
			Color3.fromRGB(90, 70, 85),
			Enum.Material.Carpet
		)
	)
	for _, x in { -12, 12 } do
		part(
			lobby,
			"LoungeTable",
			Vector3.new(5, 1.2, 2.4),
			Vector3.new(x, 0.6, 27),
			Color3.fromRGB(95, 65, 45),
			Enum.Material.Wood
		)
	end

	-- Pendant lights hanging in the atrium.
	for _, x in { -12, 0, 12 } do
		local y = 20
		decor(
			part(
				lobby,
				"PendantCord",
				Vector3.new(0.12, ArenaConfig.RoofY - y, 0.12),
				Vector3.new(x, (ArenaConfig.RoofY + y) / 2, 16),
				DARK,
				Enum.Material.Metal
			)
		)
		local shade = decor(
			part(
				lobby,
				"PendantShade",
				Vector3.new(1.4, 3.2, 3.2),
				Vector3.new(x, y, 16),
				Color3.fromRGB(190, 150, 90),
				Enum.Material.Metal
			)
		)
		shade.Shape = Enum.PartType.Cylinder
		shade.Orientation = Vector3.new(0, 0, 90)
		local light = Instance.new("PointLight")
		light.Color = LIGHT_COLOR
		light.Range = 22
		light.Brightness = 0.8
		light.Shadows = false
		light.Parent = shade
	end

	-- The floor guide by the corridor, facing the spawn (+Z), above head height.
	local guide = decor(
		part(
			lobby,
			"FloorGuide",
			Vector3.new(12, 6, 0.3),
			Vector3.new(-26, 8.5, CORRIDOR_SOUTH + 1),
			FRAME,
			Enum.Material.Metal
		)
	)
	local lines = { "FLOOR GUIDE" }
	local floors = ArenaConfig.Tower.Floors
	for index = #floors, 1, -1 do
		local floor = floors[index]
		table.insert(lines, string.format("%d · %s", floor.Number, floor.Name))
	end
	table.insert(lines, "← Elevator: west end of the corridor")
	signText(guide, Enum.NormalId.Back, table.concat(lines, "\n"), TEXT, Enum.Font.GothamBold)
end

-- Corridors ------------------------------------------------------------------------------

local POSTERS = {
	"TEAMWORK\nBecause blame is better shared",
	"SYNERGY\nWe don't know what it means either",
	"HANG IN THERE\n(until 5 PM)",
	"INBOX ZERO\nA beautiful legend",
	"DEADLINES\nThe best ideas arrive at 4:59",
	"BREATHE\nThen reply-all. Or don't.",
	"MEETINGS\nNone of us is as dumb as all of us",
	"COFFEE\nThe real project manager",
}

local function poster(parent: Instance, x: number, y: number, text: string, accent: Color3): ()
	-- On the corridor wall's north face (it faces the offices across the corridor).
	local z = CORRIDOR_SOUTH - 0.6
	part(
		parent,
		"PosterFrame",
		Vector3.new(5, 6.4, 0.2),
		Vector3.new(x, y, z),
		FRAME,
		Enum.Material.Metal
	)
	local canvas = part(
		parent,
		"PosterCanvas",
		Vector3.new(4.4, 5.8, 0.1),
		Vector3.new(x, y, z - 0.12),
		accent
	)
	signText(canvas, Enum.NormalId.Front, text, Color3.fromRGB(250, 245, 235), Enum.Font.GothamBold)
end

local function buildCorridors(parent: Instance): ()
	local corridors = Instance.new("Model")
	corridors.Name = "Corridor Art"
	corridors.Parent = parent
	local accents = {
		Color3.fromRGB(60, 90, 130),
		Color3.fromRGB(120, 70, 90),
		Color3.fromRGB(70, 110, 90),
		Color3.fromRGB(130, 95, 55),
	}
	local index = 0
	-- Ground floor and Senior floor: the corridor walls beyond the lobby
	-- (|x| 36..86), clear of the podium-room doorways (x +-61) and the
	-- elevator (x -85).
	for _, y in { 7, ArenaConfig.UpperFloorY + 7 } do
		for _, x in { -76, -46, 46, 76 } do
			index += 1
			poster(
				corridors,
				x,
				y,
				POSTERS[(index - 1) % #POSTERS + 1],
				accents[(index - 1) % #accents + 1]
			)
		end
	end
end

-- Podium rooms -----------------------------------------------------------------------------

local function buildRoomFinish(parent: Instance): ()
	local rooms = Instance.new("Model")
	rooms.Name = "Room Finish"
	rooms.Parent = parent
	local doorX = 61
	local doorHalf = 4
	local half = ArenaConfig.BuildingHalfWidth
	local z = CORRIDOR_SOUTH + 0.6
	-- Break Room (west): wood slats on its north wall, either side of the door.
	for _, span in
		{
			{ From = -half + 0.5, To = -doorX - doorHalf },
			{ From = -doorX + doorHalf, To = -LOBBY_HALF - 0.5 },
		}
	do
		local width = span.To - span.From
		part(
			rooms,
			"WoodPaneling",
			Vector3.new(width, 13.5, 0.2),
			Vector3.new((span.From + span.To) / 2, 6.75, z),
			Color3.fromRGB(118, 84, 58),
			Enum.Material.WoodPlanks
		)
	end
	-- Meeting Room (east): acoustic panels on its north wall, either side of the door.
	local colors =
		{ Color3.fromRGB(70, 110, 120), Color3.fromRGB(150, 85, 65), Color3.fromRGB(95, 90, 130) }
	local i = 0
	for _, x in { 42, 48, 54, 68, 74, 80 } do
		i += 1
		part(
			rooms,
			"AcousticPanel",
			Vector3.new(4.5, 4.5, 0.3),
			Vector3.new(x, if i % 2 == 0 then 9 else 6, z),
			colors[(i - 1) % #colors + 1],
			Enum.Material.Fabric
		)
	end
end

function InteriorBuilder.build(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Interior Finish"
	buildLobby(folder)
	buildCorridors(folder)
	buildRoomFinish(folder)
	folder.Parent = parent
	return folder
end

return InteriorBuilder
