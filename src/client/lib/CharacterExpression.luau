--!strict
--[[
	Short, friendly expressions on any character's head, drawn on this client
	only, over the server's mood face (Lib/MoodFace on the server):
	  * "Determined": focused eyes, level brows, a confident grin (own swing);
	  * "Happy": ^ ^ eyes, a big open smile and blush (a hit that landed,
	    anyone's, from Combat.CombatFeedback).
	When it ends the mood face shows again.

	Each head gets one local SurfaceGui with every expression built once; showing
	one only toggles Visible / Enabled, so nothing is recreated per swing or per
	frame, and there's no loop: a single task.delay ends each expression. A new
	character (respawn) has a new head and simply gets its own on first use.
	Works on R6 and R15 (both have a "Head" part); a character without one is
	skipped.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FaceShapes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FaceShapes"))

export type Expression = "Determined" | "Happy"

local CharacterExpression = {}

CharacterExpression.GUI_NAME = "ActionFace"
-- The server's mood face (Lib/MoodFace.GUI_NAME).
local MOOD_GUI_NAME = "MoodFace"

local EXPRESSIONS: { Expression } = { "Determined", "Happy" }

-- Head -> how many expressions have been shown, so an older timer can tell
-- that a newer expression replaced it. Weak keys: heads are never kept alive.
local showCounts: { [BasePart]: number } = setmetatable({}, { __mode = "k" }) :: any

local function drawDetermined(face: Frame): ()
	FaceShapes.eyes(face, 0.12)
	FaceShapes.focusedBrows(face)
	FaceShapes.arc(face, "Mouth", UDim2.fromScale(0.5, 0.68), 0.3, true)
end

local function drawHappy(face: Frame): ()
	FaceShapes.happyEyes(face)
	local mouth = FaceShapes.arc(face, "Mouth", UDim2.fromScale(0.5, 0.66), 0.4, true, true)
	FaceShapes.shape(
		mouth,
		"Tongue",
		UDim2.fromScale(0.5, 0.82),
		UDim2.fromScale(0.42, 0.42),
		FaceShapes.TONGUE,
		true
	)
	FaceShapes.blush(face)
end

local function findHead(character: Model): BasePart?
	local head = character:FindFirstChild("Head")
	return if head and head:IsA("BasePart") then head else nil
end

-- The head's expression gui, built the first time it's needed.
local function surfaceFor(head: BasePart): SurfaceGui
	local existing = head:FindFirstChild(CharacterExpression.GUI_NAME)
	if existing and existing:IsA("SurfaceGui") then
		return existing
	end
	local gui = FaceShapes.newSurface(head, CharacterExpression.GUI_NAME)
	gui.Enabled = false
	for _, expression in EXPRESSIONS do
		local face = Instance.new("Frame")
		face.Name = expression
		face.BackgroundTransparency = 1
		face.Size = UDim2.fromScale(1, 1)
		face.Visible = false
		face.Parent = gui
		if expression == "Determined" then
			drawDetermined(face)
		else
			drawHappy(face)
		end
	end
	return gui
end

-- The mood face and classic decal are hidden locally while an expression shows.
local function setBaseFaceVisible(head: BasePart, visible: boolean): ()
	local mood = head:FindFirstChild(MOOD_GUI_NAME)
	if mood and mood:IsA("SurfaceGui") then
		mood.Enabled = visible
	end
	local decal = head:FindFirstChild("face")
	if decal and decal:IsA("Decal") then
		-- Local only, on top of the server's Transparency (which stays as is).
		decal.LocalTransparencyModifier = if visible then 0 else 1
	end
end

-- Shows `expression` on `character` for `seconds`, replacing any expression
-- already showing there.
function CharacterExpression.show(character: Model, expression: Expression, seconds: number): ()
	local head = findHead(character)
	if head == nil then
		return
	end
	local gui = surfaceFor(head)
	for _, child in gui:GetChildren() do
		if child:IsA("Frame") then
			child.Visible = child.Name == expression
		end
	end
	gui.Enabled = true
	setBaseFaceVisible(head, false)

	local count = (showCounts[head] or 0) + 1
	showCounts[head] = count
	task.delay(seconds, function()
		if showCounts[head] ~= count or head.Parent == nil then
			return -- replaced by a newer expression, or the character is gone
		end
		gui.Enabled = false
		setBaseFaceVisible(head, true)
	end)
end

return CharacterExpression
