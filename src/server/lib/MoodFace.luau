--!strict
--[[
	Draws a cartoon face for a mood (Shared/StressRules.moodFor) on a character's
	Head with a SurfaceGui made of plain shapes (Shared/FaceShapes), so no image
	assets are needed. Built on the server, so every player sees everyone's mood.
	Every mood stays friendly: high stress looks worried or flustered, never
	angry. Short swing / hit expressions are drawn over it by the client
	(Lib/CharacterExpression).

	The head's original face decal (classic heads) is hidden while the mood face
	is shown. Newer animated (mesh) heads have their face baked in, so on those
	the mood face is drawn on top and the original may show through a little.
	Works the same on R6 and R15: both have a part named "Head".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FaceShapes = require(ReplicatedStorage.Shared.FaceShapes)

local MoodFace = {}

MoodFace.GUI_NAME = "MoodFace"

local INK = FaceShapes.INK

-- `mood` is a StressRules.Mood; typed as string because Luau widens that
-- singleton union on refinement. Unknown values draw the Frazzled face.
local function draw(face: Instance, mood: string): ()
	if mood == "Zen" then
		-- Happy closed eyes, big smile, blush.
		FaceShapes.happyEyes(face)
		FaceShapes.arc(face, "Mouth", UDim2.fromScale(0.5, 0.68), 0.46, true)
		FaceShapes.blush(face)
	elseif mood == "Relaxed" then
		FaceShapes.eyes(face)
		FaceShapes.arc(face, "Mouth", UDim2.fromScale(0.5, 0.66), 0.34, true)
	elseif mood == "Neutral" then
		-- Friendly resting face: a small, easy smile.
		FaceShapes.eyes(face)
		FaceShapes.arc(face, "Mouth", UDim2.fromScale(0.5, 0.68), 0.24, true)
	elseif mood == "Stressed" then
		-- Worried, not cross: raised inner brows and a small wobbly mouth.
		FaceShapes.eyes(face)
		FaceShapes.worriedBrows(face)
		FaceShapes.arc(face, "Mouth", UDim2.fromScale(0.5, 0.74), 0.22, false)
	else -- Frazzled
		-- Flustered: worried brows, a little "o" mouth and a sweat drop.
		FaceShapes.eyes(face)
		FaceShapes.worriedBrows(face)
		local mouth = FaceShapes.shape(
			face,
			"Mouth",
			UDim2.fromScale(0.5, 0.72),
			UDim2.fromScale(0.12, 0.12),
			INK,
			true
		)
		mouth.BackgroundTransparency = 0.05
		local drop = FaceShapes.shape(
			face,
			"Sweat",
			UDim2.fromScale(0.88, 0.22),
			UDim2.fromScale(0.1, 0.16),
			FaceShapes.SWEAT,
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
		gui = FaceShapes.newSurface(head, MoodFace.GUI_NAME)
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
