--!strict
--[[
	Drawing pieces for the cartoon faces on player heads: the server's mood face
	(Lib/MoodFace) and the client's short swing / hit expressions
	(Lib/CharacterExpression). Plain GUI shapes, so no image assets are needed.

	Positions and sizes are scale coordinates on the head's front face (0..1).
	Every look here is friendly: no angry brows, no scary shapes.
]]

local FaceShapes = {}

FaceShapes.INK = Color3.fromRGB(35, 30, 40)
FaceShapes.BLUSH = Color3.fromRGB(255, 140, 160)
FaceShapes.SWEAT = Color3.fromRGB(120, 200, 255)
FaceShapes.SHINE = Color3.fromRGB(255, 255, 255)
FaceShapes.TONGUE = Color3.fromRGB(255, 120, 140)
FaceShapes.LINE = 0.05 -- stroke thickness, as a fraction of the face

local STROKE_PIXELS = 4

function FaceShapes.shape(
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

-- Half of a circle, shown by clipping: `smile` shows the bottom half (a U),
-- otherwise the top half (an n). An outline by default; `filled` paints it
-- solid (an open laughing mouth).
function FaceShapes.arc(
	parent: Instance,
	name: string,
	center: UDim2,
	width: number,
	smile: boolean,
	filled: boolean?
): Frame
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
	ring.BorderSizePixel = 0
	ring.Parent = holder
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring
	if filled then
		ring.BackgroundColor3 = FaceShapes.INK
	else
		ring.BackgroundTransparency = 1
		local stroke = Instance.new("UIStroke")
		stroke.Color = FaceShapes.INK
		stroke.Thickness = STROKE_PIXELS
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = ring
	end
	return holder
end

-- Two round eyes with a small shine, which makes them read as bright and alive.
-- `height` < the default squints them a little (focused, not cross).
function FaceShapes.eyes(face: Instance, height: number?): ()
	local eyeHeight = height or 0.16
	for _, x in { 0.32, 0.68 } do
		local eye = FaceShapes.shape(
			face,
			"Eye",
			UDim2.fromScale(x, 0.4),
			UDim2.fromScale(0.13, eyeHeight),
			FaceShapes.INK,
			true
		)
		FaceShapes.shape(
			eye,
			"Shine",
			UDim2.fromScale(0.68, 0.3),
			UDim2.fromScale(0.34, 0.34 * 0.13 / eyeHeight),
			FaceShapes.SHINE,
			true
		)
	end
end

-- Happy closed eyes (^ ^).
function FaceShapes.happyEyes(face: Instance): ()
	FaceShapes.arc(face, "EyeLeft", UDim2.fromScale(0.32, 0.4), 0.18, false)
	FaceShapes.arc(face, "EyeRight", UDim2.fromScale(0.68, 0.4), 0.18, false)
end

-- Worried brows: inner ends higher than outer ends (never the angry V).
function FaceShapes.worriedBrows(face: Instance): ()
	local left = FaceShapes.shape(
		face,
		"Brow",
		UDim2.fromScale(0.32, 0.22),
		UDim2.fromScale(0.2, FaceShapes.LINE),
		FaceShapes.INK,
		true
	)
	left.Rotation = -14
	local right = FaceShapes.shape(
		face,
		"Brow",
		UDim2.fromScale(0.68, 0.22),
		UDim2.fromScale(0.2, FaceShapes.LINE),
		FaceShapes.INK,
		true
	)
	right.Rotation = 14
end

-- Level brows raised a little: "let's do this", not angry.
function FaceShapes.focusedBrows(face: Instance): ()
	for _, x in { 0.32, 0.68 } do
		FaceShapes.shape(
			face,
			"Brow",
			UDim2.fromScale(x, 0.24),
			UDim2.fromScale(0.2, FaceShapes.LINE),
			FaceShapes.INK,
			true
		)
	end
end

function FaceShapes.blush(face: Instance): ()
	for _, x in { 0.2, 0.8 } do
		local cheek = FaceShapes.shape(
			face,
			"Blush",
			UDim2.fromScale(x, 0.58),
			UDim2.fromScale(0.14, 0.08),
			FaceShapes.BLUSH,
			true
		)
		cheek.BackgroundTransparency = 0.3
	end
end

-- A face-sized SurfaceGui on the front of `head`, set up like every face here.
function FaceShapes.newSurface(head: BasePart, name: string): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	gui.LightInfluence = 0.5
	gui.Parent = head
	return gui
end

return FaceShapes
