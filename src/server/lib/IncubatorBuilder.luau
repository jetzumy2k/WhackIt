--!strict
--[[
	The Pet Incubation Center (docs/PETS.md) on the lawn east of the Front
	Plaza: six incubators facing the walkway in front of the building, and a
	sign. Plus Workspace.PetCenter.OutdoorEggSpawnPoints (invisible markers at
	PetConfig.WorldEggSpawnPoints, for designers to see) and an empty WorldEggs
	folder that PetService fills.

	Each incubator is a Model "Incubator<n>" with attribute IncubatorIndex and
	these parts: Base, Ring (soft neon trim, no light), Pod (glass dome), Egg
	(hidden until an egg is placed), Cap and Console (holding the "Place Egg"
	ProximityPrompt). Everything is anchored; the egg never collides. PetService
	writes the incubator's state as attributes; each client draws the display.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetConfig = require(ReplicatedStorage.Config.PetConfig)

local IncubatorBuilder = {}

IncubatorBuilder.INDEX_ATTRIBUTE = "IncubatorIndex"
IncubatorBuilder.PROMPT_NAME = "PlaceEggPrompt"

local SHELL = Color3.fromRGB(235, 240, 245)
local TRIM = Color3.fromRGB(90, 210, 200)
local GLASS = Color3.fromRGB(190, 230, 255)
local SIGN = Color3.fromRGB(60, 70, 110)
local SIGN_TEXT = Color3.fromRGB(255, 230, 150)
local POST = Color3.fromRGB(110, 115, 125)

export type Built = {
	Folder: Folder,
	Incubators: { Model },
	WorldEggs: Folder,
}

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A cylinder standing upright (Roblox cylinders run along X).
local function upright(position: Vector3): CFrame
	return CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
end

local function incubator(index: number, ground: Vector3, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Incubator" .. index
	model:SetAttribute(IncubatorBuilder.INDEX_ATTRIBUTE, index)

	local base = part(
		model,
		"Base",
		Vector3.new(1, 4.4, 4.4),
		upright(ground + Vector3.new(0, 0.5, 0)),
		SHELL
	)
	base.Shape = Enum.PartType.Cylinder
	local ring = part(
		model,
		"Ring",
		Vector3.new(0.2, 4.6, 4.6),
		upright(ground + Vector3.new(0, 1.05, 0)),
		TRIM,
		Enum.Material.Neon
	)
	ring.Shape = Enum.PartType.Cylinder
	ring.CanCollide = false
	local pod = part(
		model,
		"Pod",
		Vector3.new(3.4, 3.4, 3.4),
		CFrame.new(ground + Vector3.new(0, 2.7, 0)),
		GLASS,
		Enum.Material.Glass
	)
	pod.Shape = Enum.PartType.Ball
	pod.Transparency = 0.6
	pod.CastShadow = false
	local egg = part(
		model,
		"Egg",
		Vector3.new(1.3, 1.7, 1.3),
		CFrame.new(ground + Vector3.new(0, 2.4, 0)),
		SHELL
	)
	egg.CanCollide = false
	egg.CanQuery = false
	egg.CanTouch = false
	egg.Transparency = 1
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = egg
	local cap =
		part(model, "Cap", Vector3.new(0.5, 2, 2), upright(ground + Vector3.new(0, 4.5, 0)), TRIM)
	cap.Shape = Enum.PartType.Cylinder
	-- The console faces the walkway (-Z), where players walk up.
	local console = part(
		model,
		"Console",
		Vector3.new(1.8, 1.4, 0.5),
		CFrame.new(ground + Vector3.new(0, 1.5, -2.6)) * CFrame.Angles(math.rad(-20), 0, 0),
		SHELL
	)
	local screen = part(
		model,
		"Screen",
		Vector3.new(1.5, 1, 0.05),
		console.CFrame * CFrame.new(0, 0, -0.27),
		Color3.fromRGB(40, 60, 70),
		Enum.Material.Neon
	)
	screen.CanCollide = false
	screen.Transparency = 0.2

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = IncubatorBuilder.PROMPT_NAME
	prompt.ActionText = "Place Egg"
	prompt.ObjectText = "Incubator " .. index
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = console

	model.PrimaryPart = base
	model.Parent = parent
	return model
end

local function sign(parent: Instance): ()
	local model = Instance.new("Model")
	model.Name = "Sign"
	local ground = PetConfig.CenterSign
	for _, x in { -5.5, 5.5 } do
		part(
			model,
			"Post",
			Vector3.new(0.5, 6, 0.5),
			CFrame.new(ground + Vector3.new(x, 3, 0)),
			POST
		)
	end
	local board = part(
		model,
		"Board",
		Vector3.new(12, 3.4, 0.3),
		CFrame.new(ground + Vector3.new(0, 5, 0)),
		SIGN
	)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front -- -Z: towards the walkway
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.6
	gui.Parent = board
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = SIGN_TEXT
	text.Text =
		"🐾 PET INCUBATION CENTER\n🥚 Place your Egg into an Incubator!\n🔥 60 seconds to hatch!"
	text.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.06, 0)
	padding.PaddingBottom = UDim.new(0.06, 0)
	padding.Parent = text
	model.Parent = parent
end

function IncubatorBuilder.build(parent: Instance): Built
	local folder = Instance.new("Folder")
	folder.Name = "PetCenter"

	local incubatorFolder = Instance.new("Folder")
	incubatorFolder.Name = "Incubators"
	incubatorFolder.Parent = folder
	local incubators: { Model } = {}
	for index, ground in PetConfig.Incubators do
		table.insert(incubators, incubator(index, ground, incubatorFolder))
	end
	sign(folder)

	-- Markers only: spawning uses the same PetConfig list.
	local points = Instance.new("Folder")
	points.Name = "OutdoorEggSpawnPoints"
	points.Parent = folder
	for index, position in PetConfig.WorldEggSpawnPoints do
		local marker =
			part(points, "SpawnPoint" .. index, Vector3.new(1, 1, 1), CFrame.new(position), SIGN)
		marker.Transparency = 1
		marker.CanCollide = false
		marker.CanQuery = false
		marker.CanTouch = false
	end

	local worldEggs = Instance.new("Folder")
	worldEggs.Name = "WorldEggs"
	worldEggs.Parent = folder

	folder.Parent = parent
	return { Folder = folder, Incubators = incubators, WorldEggs = worldEggs }
end

return IncubatorBuilder
