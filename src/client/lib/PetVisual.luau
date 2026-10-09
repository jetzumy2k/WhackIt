--!strict
--[[
	A pet's body and how it moves (docs/PETS.md "Looks and movement").

	Pets are built locally on each client from a few anchored parts: pure
	presentation (the server keeps ownership and buffs), so they never
	replicate, collide, block raycasts or fire touches, and cost the server
	nothing. They are animated procedurally rather than with Animation assets:
	part-built pets have no Motor6Ds, and uploaded animations would need
	physics-driven rigs. Every part hangs off a simple skeleton instead:

	  Root   legs, from the hips (the pivot is the feet centre for walkers and
	         the body centre for flyers; -Z is the front)
	  Torso  body, tail, wings, spots: breathes, bobs with each step, leans
	         when running or hopping, tilts back when sitting
	  Head   head, eyes, nose, ears, horns, antennae: turns and nods

	pose() turns a PoseState (decided by Controllers/PetController each frame:
	gait phase, stride, lean, head turn, sitting, excitement, wing phase)
	into CFrames for every part, so all pets move in one Workspace:BulkMoveTo.
	Legs swing with the distance actually walked (no sliding feet): a
	diagonal gait for four legs, a tripod gait for six. Wings flap, tails wag
	(fast for a dog, a slow sway for a cat), ears twitch now and then.

	Each pet also gets one small ParticleEmitter of glitter (PetConfig.Glitter
	by rarity), emitted inside its body; it goes with the model when it's
	destroyed, so nothing is left behind.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("PetConfig"))

local PetVisual = {}

-- Built into every pet: what moves a part, relative to its group.
type Joint = {
	Part: BasePart,
	Group: string, -- "Root" | "Torso" | "Head"
	Kind: string, -- "Static" | "Leg" | "Wing" | "Tail" | "Ear" | "Antenna"
	Hinge: CFrame, -- the pivot point, in the group's space
	Rest: CFrame, -- the part relative to its hinge
	Side: number, -- -1 left, 1 right, 0 middle
	Phase: number, -- offset in the gait / wing cycle (radians)
	End: string, -- legs: "Front" | "Mid" | "Back"
}

export type Rig = {
	Model: Model,
	Joints: { Joint },
	Species: string,
	Movement: string, -- PetConfig.Movement
	Flies: boolean,
	Scale: number,
	HeadHinge: CFrame,
	TailRate: number, -- wags per second at rest
	TailSwing: number, -- radians
	FlapSwing: number, -- radians
	Glitter: ParticleEmitter?,
}

-- Everything the controller decides for one frame.
export type PoseState = {
	Time: number, -- seconds alive: breathing, ears, tail
	Phase: number, -- gait cycle (radians), advanced by distance walked
	Stride: number, -- 0 still, 1 walking, 2 running (blended)
	Lift: number, -- extra height in studs (hops, little jumps)
	Lean: number, -- forward pitch (radians)
	Bank: number, -- roll into turns (flyers)
	HeadYaw: number,
	HeadPitch: number,
	Sit: number, -- 0..1
	Excite: number, -- 0..1, a short happy reaction
	Flap: number, -- wing cycle (radians)
}

export type BuildOptions = {
	Glitter: boolean?, -- default true
	LowDetail: boolean?, -- phones: half the glitter
}

local INK = Color3.fromRGB(25, 25, 30)
local GOLD = Color3.fromRGB(250, 210, 90)
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local function newPart(
	model: Model,
	name: string,
	size: Vector3,
	color: Color3,
	shape: string?
): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if shape == "Ball" then
		part.Shape = Enum.PartType.Ball
	elseif shape == "Egg" then
		-- Block + sphere mesh: an ellipsoid of the part's size.
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
	part.Parent = model
	return part
end

-- A neutral pose (standing still), for previews and tests.
function PetVisual.restPose(time: number): PoseState
	return {
		Time = time,
		Phase = 0,
		Stride = 0,
		Lift = 0,
		Lean = 0,
		Bank = 0,
		HeadYaw = 0,
		HeadPitch = 0,
		Sit = 0,
		Excite = 0,
		Flap = time * 6,
	}
end

local function addGlitter(part: BasePart, rarity: string, lowDetail: boolean): ParticleEmitter?
	local style = PetConfig.Glitter[rarity]
	if style == nil then
		return nil
	end
	local keypoints: { ColorSequenceKeypoint } = {}
	for index, color in style.Colors do
		local at = if #style.Colors == 1 then 0 else (index - 1) / (#style.Colors - 1)
		table.insert(keypoints, ColorSequenceKeypoint.new(at, color))
	end
	if #keypoints == 1 then
		table.insert(keypoints, ColorSequenceKeypoint.new(1, style.Colors[1]))
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Glitter"
	emitter.Texture = SPARKLE_TEXTURE
	emitter.Rate = if lowDetail then style.Rate * 0.5 else style.Rate
	emitter.Lifetime = NumberRange.new(style.Lifetime * 0.7, style.Lifetime)
	emitter.Speed = NumberRange.new(0.2, 0.6)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, style.Size),
		NumberSequenceKeypoint.new(0.5, style.Size * 0.8),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.LightEmission = style.LightEmission
	emitter.Color = ColorSequence.new(keypoints)
	-- Born anywhere inside the body, so the sparkles sit on the pet.
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.Parent = part
	return emitter
end

-- Builds the rig for `speciesId` (a plain blob for an unknown species).
function PetVisual.build(speciesId: string, options: BuildOptions?): Rig
	local species = PetConfig.ById[speciesId]
	local look = if species then species.Look else nil
	local s = if look then look.Scale else 1
	local primary = if look then look.Primary else Color3.fromRGB(230, 230, 230)
	local secondary = if look then look.Secondary else Color3.fromRGB(200, 200, 200)
	local movement = if species then species.Movement else "Ground"
	local model = Instance.new("Model")
	model.Name = "Pet_" .. speciesId
	local joints: { Joint } = {}
	local headHinge = CFrame.identity
	local tailRate, tailSwing, flapSwing = 6, 0.4, 0.7

	-- Adds a part: `offset` is where it sits at rest (pet space, before
	-- scaling); `hinge` is where it turns (defaults to its own centre).
	local function add(
		name: string,
		size: Vector3,
		color: Color3,
		offset: CFrame,
		group: string,
		kind: string?,
		hinge: CFrame?,
		shape: string?,
		side: number?,
		phase: number?,
		legEnd: string?
	): BasePart
		local part = newPart(model, name, size * s, color, shape)
		local scaledOffset = offset.Rotation + offset.Position * s
		local hingeAt = if hinge
			then hinge.Rotation + hinge.Position * s
			else scaledOffset.Rotation + scaledOffset.Position
		table.insert(joints, {
			Part = part,
			Group = group,
			Kind = kind or "Static",
			Hinge = hingeAt,
			Rest = hingeAt:Inverse() * scaledOffset,
			Side = side or 0,
			Phase = phase or 0,
			End = legEnd or "",
		})
		return part
	end
	local function eyes(y: number, z: number, spread: number, size: number?): ()
		local eyeSize = size or 0.14
		for _, x in { -spread, spread } do
			add(
				"Eye",
				Vector3.new(eyeSize, eyeSize, eyeSize),
				INK,
				CFrame.new(x, y, z),
				"Head",
				nil,
				nil,
				"Ball"
			)
		end
	end

	if movement == "Crawling" then
		-- Bugs: a domed shell low to the ground, six legs, antennae.
		local shell = add(
			"Shell",
			Vector3.new(1, 0.6, 1.2),
			primary,
			CFrame.new(0, 0.42, 0),
			"Torso",
			nil,
			nil,
			"Egg"
		)
		model.PrimaryPart = shell
		headHinge = CFrame.new(0, 0.38, -0.5)
		add(
			"Head",
			Vector3.new(0.45, 0.4, 0.42),
			secondary,
			CFrame.new(0, 0.36, -0.72),
			"Head",
			nil,
			nil,
			"Ball"
		)
		eyes(0.45, -0.9, 0.12, 0.11)
		for _, side in { -1, 1 } do
			add(
				"Antenna",
				Vector3.new(0.05, 0.42, 0.05),
				secondary,
				CFrame.new(side * 0.13, 0.7, -0.86)
					* CFrame.Angles(math.rad(-35), 0, math.rad(-side * 20)),
				"Head",
				"Antenna",
				CFrame.new(side * 0.1, 0.52, -0.82),
				nil,
				side
			)
			for index, z in { -0.35, 0, 0.35 } do
				-- Tripod gait: front and back of one side move with the middle of the other.
				local phase = if (index % 2 == 1) == (side == -1) then 0 else math.pi
				add(
					"Leg",
					Vector3.new(0.5, 0.07, 0.07),
					secondary,
					CFrame.new(side * 0.62, 0.15, z) * CFrame.Angles(0, 0, math.rad(side * 30)),
					"Root",
					"Leg",
					CFrame.new(side * 0.4, 0.3, z),
					nil,
					side,
					phase,
					"Mid"
				)
			end
		end
		if look and look.Spots then
			for _, spot in
				{
					Vector2.new(-0.22, -0.15),
					Vector2.new(0.22, -0.15),
					Vector2.new(-0.2, 0.3),
					Vector2.new(0.2, 0.3),
				}
			do
				add(
					"Spot",
					Vector3.new(0.2, 0.08, 0.2),
					secondary,
					CFrame.new(spot.X, 0.7, spot.Y),
					"Torso",
					nil,
					nil,
					"Ball"
				)
			end
		else
			add("Stripe", Vector3.new(0.05, 0.04, 1.05), secondary, CFrame.new(0, 0.72, 0), "Torso")
		end
	elseif movement == "Flying" then
		-- Flyers: body at the pivot, wings either side.
		local butterfly = speciesId == "butterfly"
		local dragon = speciesId == "dragon"
		local bodySize = if butterfly
			then Vector3.new(0.22, 0.22, 0.85)
			else Vector3.new(0.55, 0.55, 1.05)
		local body = add("Body", bodySize, primary, CFrame.identity, "Torso", nil, nil, "Egg")
		model.PrimaryPart = body
		headHinge = CFrame.new(0, 0.1, -0.42)
		local headSize = if butterfly then 0.28 else 0.55
		add(
			"Head",
			Vector3.new(headSize, headSize, headSize),
			primary,
			CFrame.new(0, 0.18, -0.6),
			"Head",
			nil,
			nil,
			"Ball"
		)
		eyes(
			if butterfly then 0.24 else 0.32,
			if butterfly then -0.7 else -0.84,
			if butterfly then 0.08 else 0.13
		)
		if butterfly then
			flapSwing = 0.9
			for _, side in { -1, 1 } do
				add(
					"Antenna",
					Vector3.new(0.04, 0.45, 0.04),
					primary,
					CFrame.new(side * 0.08, 0.45, -0.75)
						* CFrame.Angles(math.rad(-25), 0, math.rad(-side * 15)),
					"Head",
					"Antenna",
					CFrame.new(side * 0.06, 0.25, -0.68),
					nil,
					side
				)
				-- Upper and lower wing: the lower one trails a little.
				add(
					"Wing",
					Vector3.new(1, 0.04, 0.8),
					secondary,
					CFrame.new(side * 0.6, 0.05, -0.18),
					"Torso",
					"Wing",
					CFrame.new(side * 0.1, 0.05, -0.18),
					nil,
					side,
					0
				)
				add(
					"Wing",
					Vector3.new(0.7, 0.04, 0.6),
					secondary:Lerp(primary, 0.25),
					CFrame.new(side * 0.45, 0.02, 0.3),
					"Torso",
					"Wing",
					CFrame.new(side * 0.1, 0.02, 0.3),
					nil,
					side,
					0.5
				)
			end
		else
			local wingSize = if dragon
				then Vector3.new(1.45, 0.07, 0.95)
				else Vector3.new(1.05, 0.07, 0.7)
			flapSwing = if dragon then 0.6 else 0.7
			for _, side in { -1, 1 } do
				add(
					"Wing",
					wingSize,
					secondary,
					CFrame.new(side * (0.25 + wingSize.X / 2), 0.15, 0.05),
					"Torso",
					"Wing",
					CFrame.new(side * 0.25, 0.15, 0.05),
					nil,
					side,
					0
				)
			end
			if speciesId == "toucan" then
				add(
					"Beak",
					Vector3.new(0.26, 0.26, 0.6),
					secondary,
					CFrame.new(0, 0.12, -1.05),
					"Head",
					nil,
					nil,
					"Egg"
				)
			end
			if look and look.Ears == "Horns" then
				for _, side in { -1, 1 } do
					add(
						"Horn",
						Vector3.new(0.1, 0.36, 0.1),
						GOLD,
						CFrame.new(side * 0.15, 0.5, -0.55) * CFrame.Angles(math.rad(25), 0, 0),
						"Head"
					)
				end
			end
			if dragon then
				tailRate, tailSwing = 1.6, 0.35
				add(
					"Tail",
					Vector3.new(0.2, 0.2, 1),
					primary,
					CFrame.new(0, -0.05, 0.95),
					"Torso",
					"Tail",
					CFrame.new(0, -0.05, 0.5)
				)
				for _, side in { -1, 1 } do
					add(
						"Claw",
						Vector3.new(0.14, 0.32, 0.14),
						primary,
						CFrame.new(side * 0.18, -0.38, 0.1),
						"Torso"
					)
				end
			elseif look and look.Tail == "Flame" then
				-- Phoenix: a crest and three tail feathers fanning gently.
				tailRate, tailSwing = 1.8, 0.25
				for _, side in { -1, 1 } do
					add(
						"Crest",
						Vector3.new(0.08, 0.32, 0.18),
						secondary,
						CFrame.new(side * 0.07, 0.52, -0.6) * CFrame.Angles(math.rad(-20), 0, 0),
						"Head"
					)
				end
				for index, angle in { -18, 0, 18 } do
					local feather = add(
						"Feather",
						Vector3.new(0.18, 0.06, 0.95),
						secondary,
						CFrame.new(0, -0.05, 0.9) * CFrame.Angles(0, math.rad(angle), 0),
						"Torso",
						"Tail",
						CFrame.new(0, -0.05, 0.45),
						nil,
						0,
						index * 0.6
					)
					if index == 2 then
						feather.Material = Enum.Material.Neon -- one soft glowing feather, no light
					end
				end
			end
		end
	else
		-- Walkers (Ground, Hopping): body on four legs, head in front.
		local body = add(
			"Body",
			Vector3.new(1, 0.8, 1.4),
			primary,
			CFrame.new(0, 0.82, 0),
			"Torso",
			nil,
			nil,
			"Egg"
		)
		model.PrimaryPart = body
		headHinge = CFrame.new(0, 1.1, -0.55)
		add(
			"Head",
			Vector3.new(0.85, 0.85, 0.85),
			primary,
			CFrame.new(0, 1.32, -0.8),
			"Head",
			nil,
			nil,
			"Ball"
		)
		add(
			"Snout",
			Vector3.new(0.45, 0.32, 0.35),
			secondary,
			CFrame.new(0, 1.19, -1.17),
			"Head",
			nil,
			nil,
			"Egg"
		)
		add(
			"Nose",
			Vector3.new(0.14, 0.12, 0.12),
			INK,
			CFrame.new(0, 1.26, -1.34),
			"Head",
			nil,
			nil,
			"Ball"
		)
		eyes(1.44, -1.14, 0.18)
		-- Diagonal gait: front-left with back-right.
		for _, side in { -1, 1 } do
			for _, legEnd in { "Front", "Back" } do
				local z = if legEnd == "Front" then -0.42 else 0.45
				local phase = if (side == -1) == (legEnd == "Front") then 0 else math.pi
				add(
					"Leg",
					Vector3.new(0.24, 0.58, 0.24),
					primary,
					CFrame.new(side * 0.3, 0.29, z),
					"Root",
					"Leg",
					CFrame.new(side * 0.3, 0.58, z),
					nil,
					side,
					phase,
					legEnd
				)
			end
		end
		local ears = if look then look.Ears else nil
		for _, side in { -1, 1 } do
			if ears == "Floppy" then
				add(
					"Ear",
					Vector3.new(0.18, 0.5, 0.35),
					secondary,
					CFrame.new(side * 0.42, 1.32, -0.72) * CFrame.Angles(0, 0, math.rad(side * 15)),
					"Head",
					"Ear",
					CFrame.new(side * 0.36, 1.55, -0.72),
					nil,
					side
				)
			elseif ears == "Pointy" then
				add(
					"Ear",
					Vector3.new(0.2, 0.36, 0.18),
					primary,
					CFrame.new(side * 0.26, 1.76, -0.74) * CFrame.Angles(0, 0, math.rad(-side * 15)),
					"Head",
					"Ear",
					CFrame.new(side * 0.24, 1.6, -0.74),
					nil,
					side
				)
			elseif ears == "Round" then
				add(
					"Ear",
					Vector3.new(0.3, 0.3, 0.2),
					primary,
					CFrame.new(side * 0.33, 1.66, -0.72),
					"Head",
					"Ear",
					CFrame.new(side * 0.3, 1.55, -0.72),
					"Ball",
					side
				)
			elseif ears == "Long" then
				add(
					"Ear",
					Vector3.new(0.18, 0.85, 0.24),
					secondary,
					CFrame.new(side * 0.17, 2.05, -0.7),
					"Head",
					"Ear",
					CFrame.new(side * 0.15, 1.65, -0.7),
					"Egg",
					side
				)
			end
		end
		if look and look.Horn then
			add(
				"Horn",
				Vector3.new(0.12, 0.55, 0.12),
				GOLD,
				CFrame.new(0, 1.86, -1.02) * CFrame.Angles(math.rad(-30), 0, 0),
				"Head"
			)
		end
		local tail = if look then look.Tail else nil
		if tail == "Wag" then
			tailRate, tailSwing = 9, 0.5 -- a happy dog
			add(
				"Tail",
				Vector3.new(0.15, 0.15, 0.6),
				primary,
				CFrame.new(0, 1.05, 0.95) * CFrame.Angles(math.rad(25), 0, 0),
				"Torso",
				"Tail",
				CFrame.new(0, 0.95, 0.68)
			)
		elseif tail == "Puff" then
			tailRate, tailSwing = 3, 0.25
			add(
				"Tail",
				Vector3.new(0.4, 0.4, 0.4),
				secondary,
				CFrame.new(0, 0.9, 0.8),
				"Torso",
				"Tail",
				CFrame.new(0, 0.9, 0.68),
				"Ball"
			)
		elseif tail == "Curl" then
			tailRate, tailSwing = 1.4, 0.35 -- a slow cat sway
			add(
				"Tail",
				Vector3.new(0.14, 0.7, 0.14),
				primary,
				CFrame.new(0, 1.25, 0.82),
				"Torso",
				"Tail",
				CFrame.new(0, 0.92, 0.75)
			)
		end
	end

	local glitter: ParticleEmitter? = nil
	local wantGlitter = options == nil or options.Glitter ~= false
	if wantGlitter and species and model.PrimaryPart then
		glitter = addGlitter(
			model.PrimaryPart,
			species.Rarity,
			options ~= nil and options.LowDetail == true
		)
	end

	return {
		Model = model,
		Joints = joints,
		Species = speciesId,
		Movement = movement,
		Flies = movement == "Flying",
		Scale = s,
		HeadHinge = headHinge.Rotation + headHinge.Position * s,
		TailRate = tailRate,
		TailSwing = tailSwing,
		FlapSwing = flapSwing,
		Glitter = glitter,
	}
end

-- Parts and CFrames for the rig at `pivot` in `state`.
function PetVisual.pose(rig: Rig, pivot: CFrame, state: PoseState): ({ BasePart }, { CFrame })
	local s = rig.Scale
	local walk = math.min(state.Stride, 1)
	local run = math.clamp(state.Stride - 1, 0, 1)
	local still = 1 - walk
	local t = state.Time

	local root = pivot * CFrame.new(0, state.Lift, 0) * CFrame.Angles(0, 0, state.Bank)
	-- Breathing at rest, a bob with every step, a lean when running.
	local breath = math.sin(t * 2.3) * 0.02 * s * still
	local bob = if rig.Flies
		then 0
		else math.abs(math.sin(state.Phase)) * (0.05 + 0.05 * run) * s * walk
	local sway = if rig.Movement == "Crawling" then math.sin(state.Phase) * 0.06 * walk else 0
	local sitTilt = state.Sit * 0.32
	local torso = root
		* CFrame.new(0, breath + bob - state.Sit * 0.18 * s, 0)
		* CFrame.Angles(-state.Lean + sitTilt, 0, sway)
	local nod = math.sin(state.Phase * 2) * 0.06 * walk + math.sin(t * 1.1) * 0.03 * still
	local head = torso
		* rig.HeadHinge
		* CFrame.Angles(state.HeadPitch + nod - sitTilt * 0.6, state.HeadYaw, 0)
		* rig.HeadHinge:Inverse()

	local legSwing = 0.45 * walk + 0.3 * run
	local wag = math.sin(t * rig.TailRate * (1 + state.Excite * 1.5))
		* rig.TailSwing
		* (1 + state.Excite)
	local flap = rig.FlapSwing

	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	for _, joint in rig.Joints do
		local base = if joint.Group == "Head"
			then head
			elseif joint.Group == "Torso" then torso
			else root
		local motion = CFrame.identity
		local kind = joint.Kind
		if kind == "Leg" then
			local swing = math.sin(state.Phase + joint.Phase) * legSwing
			if joint.End == "Mid" then
				-- Bug legs sweep forward and back, and lift on the forward stroke.
				motion = CFrame.Angles(
					0,
					swing * 0.8,
					math.max(0, math.cos(state.Phase + joint.Phase)) * 0.25 * walk * joint.Side
				)
			elseif joint.End == "Back" then
				motion = CFrame.Angles(swing - state.Sit * 1.1, 0, 0)
			else
				motion = CFrame.Angles(swing, 0, 0)
			end
		elseif kind == "Wing" then
			local beat = math.sin(state.Flap - joint.Phase) * flap + 0.15
			motion = CFrame.Angles(0, 0, -joint.Side * beat)
		elseif kind == "Tail" then
			motion = CFrame.Angles(0, wag + math.sin(t * 2 + joint.Phase) * 0.05, 0)
		elseif kind == "Ear" then
			-- A small constant drift plus an occasional quick twitch.
			local twitch = math.max(0, math.sin(t * 0.8 + joint.Side * 2.1)) ^ 16 * 0.4
			local back = state.Lean * 0.8 + state.Excite * 0.2
			motion =
				CFrame.Angles(back + math.sin(t * 1.3 + joint.Side) * 0.04, 0, joint.Side * twitch)
		elseif kind == "Antenna" then
			motion = CFrame.Angles(math.sin(t * 3 + joint.Side) * 0.15, 0, 0)
		end
		table.insert(parts, joint.Part)
		table.insert(cframes, base * joint.Hinge * motion * joint.Rest)
	end
	return parts, cframes
end

return PetVisual
