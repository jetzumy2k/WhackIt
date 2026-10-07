--!strict
--[[
	Builds the friendly lounge NPCs (Config/NpcConfig) as small blocky cartoon
	office workers, in the same plain-parts style as the bosses: legs, shirt
	and tie, arms, a head with a drawn smile (Shared/FaceShapes) and hair, plus
	a prop (book, coffee mug, clipboard).

	Decoration only: no Humanoid, every part non-colliding, unclickable and
	untouchable (so they never block anyone, can't be hit, and never count as
	bosses), parented to Workspace.LobbyNpcs, not Workspace.Bosses.

	Each NPC is three small assemblies, each with one anchored root and the
	rest welded to it, so the client can animate them with plain tweens
	(NpcController):
	  Body     torso root + legs, tie, left arm
	  Head     head root + hair (face drawn on it)
	  RightArm arm root + its prop
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FaceShapes = require(ReplicatedStorage.Shared.FaceShapes)
local NpcConfig = require(ReplicatedStorage.Config.NpcConfig)

local NpcBuilder = {}

NpcBuilder.FOLDER_NAME = "LobbyNpcs"
NpcBuilder.NPC_ATTRIBUTE = "NpcId"
-- Names of each NPC's animated roots (NpcController).
NpcBuilder.BODY = "Body"
NpcBuilder.HEAD = "Head"
NpcBuilder.ARM = "RightArm"

local TORSO = Vector3.new(2, 2.2, 1)
local ARM = Vector3.new(0.8, 2.1, 0.9)
local HEAD = Vector3.new(1.6, 1.6, 1.6)
-- How far forward (degrees) the right arm reaches for each behaviour.
local ARM_REACH: { [string]: number } = { Read = 55, Chat = 45, Coffee = 45, Greet = 25 }

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
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	-- Pure decoration: walk through it, never hit or click it.
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	p.Parent = parent
	return p
end

local function weld(root: BasePart, piece: BasePart): ()
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = root
	constraint.Part1 = piece
	constraint.Parent = root
end

-- A friendly face: shiny eyes and a smile.
local function face(head: BasePart): ()
	local gui = FaceShapes.newSurface(head, "Face")
	FaceShapes.eyes(gui)
	FaceShapes.arc(gui, "Mouth", UDim2.fromScale(0.5, 0.66), 0.34, true)
end

local function build(entry: NpcConfig.Npc, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = entry.Name
	model:SetAttribute(NpcBuilder.NPC_ATTRIBUTE, entry.Id)
	-- Streams in whole, so the client always finds all three roots.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	-- Everything below is laid out in the NPC's own frame (front = -Z), with
	-- `hip` the centre of the hips.
	local sitting = entry.Pose == "Sit"
	local origin = CFrame.new(entry.Position) * CFrame.Angles(0, math.rad(entry.Yaw), 0)
	local hipY = if sitting then 0.45 else 2.2
	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, hipY + y, z)
	end

	local torso = part(model, NpcBuilder.BODY, TORSO, at(0, TORSO.Y / 2, 0), entry.Shirt)
	torso.Anchored = true
	for _, x in { -0.5, 0.5 } do
		if sitting then
			-- Thighs forward along the seat, shins down to the floor.
			weld(
				torso,
				part(model, "Thigh", Vector3.new(0.9, 0.9, 2.5), at(x, 0, -1.25), entry.Pants)
			)
			-- Centre 0.8 above the floor (the seat top is at entry.Position.Y).
			local shinY = 0.8 - entry.Position.Y - hipY
			weld(
				torso,
				part(model, "Shin", Vector3.new(0.9, 1.6, 0.9), at(x, shinY, -2.9), entry.Pants)
			)
		else
			weld(torso, part(model, "Leg", Vector3.new(0.9, 2.2, 1), at(x, -1.1, 0), entry.Pants))
		end
	end
	if entry.Tie then
		weld(
			torso,
			part(model, "Tie", Vector3.new(0.3, 1.3, 0.06), at(0, TORSO.Y - 0.85, -0.53), entry.Tie)
		)
	else
		-- A name badge instead of a tie.
		weld(
			torso,
			part(
				model,
				"Badge",
				Vector3.new(0.5, 0.35, 0.06),
				at(-0.5, TORSO.Y - 0.6, -0.53),
				Color3.new(1, 1, 1)
			)
		)
	end
	-- Arms swing forward from the shoulder by `degrees` to hold their prop.
	local function armAt(side: number, degrees: number): CFrame
		return at(side * 1.4, TORSO.Y, 0)
			* CFrame.Angles(math.rad(degrees), 0, 0)
			* CFrame.new(0, -ARM.Y / 2, 0)
	end
	local reach = ARM_REACH[entry.Behavior] or 0
	local leftReach = if entry.Behavior == "Read" then reach else 0
	weld(torso, part(model, "LeftArm", ARM, armAt(-1, leftReach), entry.Shirt))

	local head = part(model, NpcBuilder.HEAD, HEAD, at(0, TORSO.Y + HEAD.Y / 2, 0), entry.Skin)
	head.Anchored = true
	if entry.HeadYaw then
		head.CFrame = head.CFrame * CFrame.Angles(0, math.rad(entry.HeadYaw), 0)
	end
	face(head)
	local hair = part(
		model,
		"Hair",
		Vector3.new(1.7, 0.45, 1.7),
		head.CFrame * CFrame.new(0, 0.95, 0.05),
		entry.Hair
	)
	weld(head, hair)

	-- Right arm, holding the prop for its behaviour in front of the body.
	local arm = part(model, NpcBuilder.ARM, ARM, armAt(1, reach), entry.Shirt)
	arm.Anchored = true
	local hand = arm.CFrame * CFrame.new(0, -ARM.Y / 2, 0)
	if entry.Behavior == "Read" then
		-- An open book held between both hands, tipped towards the face.
		local handLocal = origin:ToObjectSpace(hand).Position
		weld(
			arm,
			part(
				model,
				"Book",
				Vector3.new(1.8, 1.2, 0.15),
				origin
					* CFrame.new(0, handLocal.Y + 0.35, handLocal.Z)
					* CFrame.Angles(math.rad(25), 0, 0),
				Color3.fromRGB(200, 60, 70)
			)
		)
	elseif entry.Behavior == "Chat" or entry.Behavior == "Coffee" then
		-- Upright in the hand (a cylinder's length runs along X, so stand it up).
		local handPoint = hand.Position
		local mug = part(
			model,
			"Mug",
			Vector3.new(0.7, 0.55, 0.55),
			CFrame.new(handPoint + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.new(1, 1, 1)
		)
		mug.Shape = Enum.PartType.Cylinder
		weld(arm, mug)
	elseif entry.Behavior == "Greet" then
		weld(
			arm,
			part(
				model,
				"Clipboard",
				Vector3.new(0.9, 1.2, 0.08),
				hand * CFrame.new(0, 0.3, -0.3),
				Color3.fromRGB(150, 110, 70)
			)
		)
	end

	model.PrimaryPart = torso
	model.Parent = parent
	return model
end

-- Builds every NPC into a "LobbyNpcs" folder under `parent`.
function NpcBuilder.build(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = NpcBuilder.FOLDER_NAME
	for _, entry in NpcConfig.List do
		build(entry, folder)
	end
	folder.Parent = parent
	return folder
end

return NpcBuilder
