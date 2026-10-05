--!strict
--[[
	Draws a cartoon face for a mood (Shared/StressRules.moodFor) on a character's
	Head with a SurfaceGui made of plain shapes, so no image assets are needed.
	Built on the server, so every player sees everyone's mood.

	The head's original face decal (classic heads) is hidden while the mood face
	is shown. Newer animated (mesh) heads have their face baked in, so on those
	the mood face is drawn on top and the original may show through a little.

	Shapes use scale coordinates on the head's front face (0..1).
]]

local MoodFace = {}

MoodFace.GUI_NAME = "MoodFace"

local INK = Color3.fromRGB(35, 30, 40)
local BLUSH = Color3.fromRGB(255, 140, 160)
local SWEAT = Color3.fromRGB(120, 200, 255)
local LINE = 0.05 -- stroke thickness, as a fraction of the face

local function shape(
	parent: Instance,
	name: string,
	position: UDim2,
	size: UDim2,
	color: Color3,
	round: boolean?
): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Parent = parent
	if round then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = frame
	end
	return frame
end

-- Half of a ring, drawn by clipping a circle outline: "Smile" shows the bottom
-- half (a U), "Frown" the top half. Used for mouths and happy closed eyes.
local function arc(parent: Instance, name: string, center: UDim2, width: number, smile: boolean): ()
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = center
	holder.Size = UDim2.fromScale(width, width / 2)
	holder.BackgroundTransparency = 1
	holder.ClipsDescendants = true
	holder.Parent = parent

	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.Size = UDim2.fromScale(1, 2)
	ring.Position = if smile then UDim2.fromScale(0, -1) else UDim2.fromScale(0, 0)
	ring.BackgroundTransparency = 1
	ring.Parent = holder
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = ring
end

local function eyes(face: Instance): ()
	for _, x in { 0.32, 0.68 } do
		shape(face, "Eye", UDim2.fromScale(x, 0.4), UDim2.fromScale(0.13, 0.16), INK, true)
	end
end

-- Angry brows: inner ends lower than outer ends.
local function brows(face: Instance): ()
	local left = shape(face, "Brow", UDim2.fromScale(0.32, 0.24), UDim2.fromScale(0.22, LINE), INK)
	left.Rotation = 18
	local right = shape(face, "Brow", UDim2.fromScale(0.68, 0.24), UDim2.fromScale(0.22, LINE), INK)
	right.Rotation = -18
end

-- `mood` is a StressRules.Mood; typed as string because Luau widens that
-- singleton union on refinement. Unknown values draw the Frazzled face.
local function draw(face: Instance, mood: string): ()
	if mood == "Zen" then
		-- Happy closed eyes, big smile, blush.
		arc(face, "EyeLeft", UDim2.fromScale(0.32, 0.4), 0.18, false)
		arc(face, "EyeRight", UDim2.fromScale(0.68, 0.4), 0.18, false)
		arc(face, "Mouth", UDim2.fromScale(0.5, 0.68), 0.46, true)
		for _, x in { 0.2, 0.8 } do
			local cheek = shape(
				face,
				"Blush",
				UDim2.fromScale(x, 0.58),
				UDim2.fromScale(0.14, 0.08),
				BLUSH,
				true
			)
			cheek.BackgroundTransparency = 0.3
		end
	elseif mood == "Relaxed" then
		eyes(face)
		arc(face, "Mouth", UDim2.fromScale(0.5, 0.66), 0.34, true)
	elseif mood == "Neutral" then
		eyes(face)
		shape(face, "Mouth", UDim2.fromScale(0.5, 0.7), UDim2.fromScale(0.3, LINE), INK)
	elseif mood == "Stressed" then
		eyes(face)
		brows(face)
		arc(face, "Mouth", UDim2.fromScale(0.5, 0.74), 0.3, false)
	else -- Frazzled
		eyes(face)
		brows(face)
		arc(face, "Mouth", UDim2.fromScale(0.5, 0.74), 0.36, false)
		local drop = shape(
			face,
			"Sweat",
			UDim2.fromScale(0.88, 0.22),
			UDim2.fromScale(0.1, 0.16),
			SWEAT,
			true
		)
		drop.BackgroundTransparency = 0.1
	end
end

-- Shows `mood` on `head`, replacing any previous mood face. Cheap to call
-- repeatedly; it only redraws when the mood changes.
function MoodFace.apply(head: BasePart, mood: string): ()
	local gui = head:FindFirstChild(MoodFace.GUI_NAME)
	if gui and gui:IsA("SurfaceGui") then
		if gui:GetAttribute("Mood") == mood then
			return
		end
		gui:ClearAllChildren()
	else
		local created = Instance.new("SurfaceGui")
		created.Name = MoodFace.GUI_NAME
		created.Face = Enum.NormalId.Front
		created.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		created.PixelsPerStud = 100
		created.LightInfluence = 0.5
		created.Parent = head
		gui = created
	end

	local surface = gui :: SurfaceGui
	surface:SetAttribute("Mood", mood)
	draw(surface, mood)

	-- Hide the classic face decal so faces don't overlap.
	local decal = head:FindFirstChild("face")
	if decal and decal:IsA("Decal") then
		decal.Transparency = 1
	end
end

return MoodFace
