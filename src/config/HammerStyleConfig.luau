--!strict
--[[
	How each hammer looks (docs/GAMEPLAY_RULES.md "Hammer looks"). Visual only:
	damage, prices and ownership stay in HammerConfig / StoreConfig. Built by
	Shared/HammerModel for the held Tool (server) and the shop preview (client).

	Coordinates (studs):
	  * Handle space: the shaft runs along Z; +Z is the hand / pommel end,
	    -Z the end the head sits on (see Lib/HammerTool).
	  * Head space: the head's length runs along X (the two striking faces at
	    +-X), so the swing trail and squash-and-stretch (Lib/SwingAnimator) work
	    for every shape. Head details are scaled with the head while swinging.

	Effects stay subtle on purpose: at most one small static light and one
	slow particle emitter per hammer (limits below, checked in tests).
]]

export type Shape = "Block" | "Cylinder" | "Ball"

export type Detail = {
	Name: string,
	Shape: Shape,
	Size: Vector3,
	Offset: CFrame,
	Color: Color3,
	Material: Enum.Material,
	Transparency: number?,
	Reflectance: number?,
}

export type Glow = { Color: Color3, Range: number, Brightness: number }

export type Impact = { Color: Color3, Accent: Color3 }

export type Particles = {
	Color: Color3,
	FadeColor: Color3,
	Rate: number, -- per second
	Lifetime: number,
	Size: number,
	Speed: number,
	Rise: number, -- upward acceleration (embers float up; 0 for none)
}

export type Style = {
	Id: string,
	Shaft: {
		Shape: "Round" | "Square",
		Length: number,
		Width: number,
		Color: Color3,
		Material: Enum.Material,
	},
	Head: {
		Shape: "Cylinder" | "Block",
		Size: Vector3, -- X = length between the striking faces
		Color: Color3,
		Material: Enum.Material,
		Reflectance: number?,
		Transparency: number?,
	},
	HandleDetails: { Detail },
	HeadDetails: { Detail },
	TrailColor: Color3, -- swing trail (Lib/SwingAnimator)
	Glow: Glow?,
	Particles: Particles?,
	-- Colours of the hit burst where this hammer lands (Lib/HitEffects);
	-- nil = the default gold sparkles.
	Impact: Impact?,
}

local SMOOTH = Enum.Material.SmoothPlastic
local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local WOOD = Enum.Material.Wood
local FABRIC = Enum.Material.Fabric
local GLASS = Enum.Material.Glass

local QUARTER = math.rad(90)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Handle-space pieces ------------------------------------------------------

-- A ring or sleeve around the shaft, centred at `z`.
local function sleeve(
	name: string,
	z: number,
	length: number,
	diameter: number,
	color: Color3,
	material: Enum.Material
): Detail
	return {
		Name = name,
		Shape = "Cylinder",
		Size = Vector3.new(length, diameter, diameter),
		Offset = CFrame.new(0, 0, z) * CFrame.Angles(0, QUARTER, 0),
		Color = color,
		Material = material,
	}
end

-- Grip wrap where the hand holds the shaft (Lib/HammerTool grips at Length/2 - 0.45).
local function grip(length: number, width: number, color: Color3): Detail
	return sleeve("Grip", length / 2 - 0.5, 1.0, width + 0.08, color, FABRIC)
end

-- Ball on the hand end of the shaft.
local function pommel(
	length: number,
	diameter: number,
	color: Color3,
	material: Enum.Material
): Detail
	return {
		Name = "Pommel",
		Shape = "Ball",
		Size = Vector3.one * diameter,
		Offset = CFrame.new(0, 0, length / 2 + 0.05),
		Color = color,
		Material = material,
	}
end

-- Collar just below a head that is `headDepth` deep (the head's Z size).
local function collar(
	length: number,
	headDepth: number,
	width: number,
	color: Color3,
	material: Enum.Material
): Detail
	return sleeve("Collar", -length / 2 + headDepth / 2 + 0.1, 0.18, width + 0.12, color, material)
end

-- Head-space pieces --------------------------------------------------------

-- A band or face cap around a cylinder head, at `x` along its length.
local function band(
	name: string,
	x: number,
	thickness: number,
	diameter: number,
	color: Color3,
	material: Enum.Material
): Detail
	return {
		Name = name,
		Shape = "Cylinder",
		Size = Vector3.new(thickness, diameter, diameter),
		Offset = CFrame.new(x, 0, 0),
		Color = color,
		Material = material,
	}
end

-- A square plate or band around a block head, at `x` along its length.
local function plate(
	name: string,
	x: number,
	thickness: number,
	side: number,
	color: Color3,
	material: Enum.Material
): Detail
	return {
		Name = name,
		Shape = "Block",
		Size = Vector3.new(thickness, side, side),
		Offset = CFrame.new(x, 0, 0),
		Color = color,
		Material = material,
	}
end

local function dot(
	name: string,
	at: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material
): Detail
	return {
		Name = name,
		Shape = "Ball",
		Size = Vector3.one * diameter,
		Offset = CFrame.new(at),
		Color = color,
		Material = material,
	}
end

-- Styles -------------------------------------------------------------------

local styles: { Style } = {
	{
		-- Free starter: a squishy toy hammer.
		Id = "squeaky",
		Shaft = {
			Shape = "Round",
			Length = 3.0,
			Width = 0.38,
			Color = rgb(255, 210, 60),
			Material = SMOOTH,
		},
		Head = {
			Shape = "Cylinder",
			Size = Vector3.new(1.8, 1.35, 1.35),
			Color = rgb(255, 70, 90),
			Material = SMOOTH,
		},
		HandleDetails = {
			grip(3.0, 0.38, rgb(255, 120, 150)),
			pommel(3.0, 0.55, rgb(255, 70, 90), SMOOTH),
		},
		HeadDetails = {
			band("FaceA", 0.93, 0.12, 1.1, rgb(255, 255, 255), SMOOTH),
			band("FaceB", -0.93, 0.12, 1.1, rgb(255, 255, 255), SMOOTH),
			band("Stripe", 0, 0.22, 1.4, rgb(255, 230, 240), SMOOTH),
		},
		TrailColor = rgb(255, 220, 230),
	},
	{
		-- Wooden handle, steel head, rubber grip: the one from the supply closet.
		Id = "office",
		Shaft = {
			Shape = "Round",
			Length = 3.2,
			Width = 0.34,
			Color = rgb(150, 100, 60),
			Material = WOOD,
		},
		Head = {
			Shape = "Block",
			Size = Vector3.new(1.9, 0.7, 0.7),
			Color = rgb(150, 155, 165),
			Material = METAL,
		},
		HandleDetails = {
			grip(3.2, 0.34, rgb(30, 30, 35)),
			collar(3.2, 0.7, 0.34, rgb(40, 110, 220), SMOOTH),
		},
		HeadDetails = {
			band("Face", 1.0, 0.22, 0.85, rgb(120, 125, 135), METAL),
			plate("Neck", -0.55, 0.3, 0.6, rgb(130, 135, 145), METAL),
			{
				Name = "Claw",
				Shape = "Block",
				Size = Vector3.new(0.6, 0.18, 0.5),
				Offset = CFrame.new(-1.05, 0.12, 0) * CFrame.Angles(0, 0, math.rad(25)),
				Color = rgb(130, 135, 145),
				Material = METAL,
			},
		},
		TrailColor = rgb(220, 225, 235),
	},
	{
		-- A bouncy rubber mallet.
		Id = "bouncy",
		Shaft = {
			Shape = "Round",
			Length = 3.1,
			Width = 0.36,
			Color = rgb(245, 245, 250),
			Material = SMOOTH,
		},
		Head = {
			Shape = "Cylinder",
			Size = Vector3.new(1.7, 1.4, 1.4),
			Color = rgb(80, 200, 255),
			Material = SMOOTH,
		},
		HandleDetails = {
			grip(3.1, 0.36, rgb(40, 120, 220)),
			pommel(3.1, 0.5, rgb(80, 200, 255), SMOOTH),
		},
		HeadDetails = {
			band("FaceA", 0.9, 0.2, 1.48, rgb(30, 110, 200), SMOOTH),
			band("FaceB", -0.9, 0.2, 1.48, rgb(30, 110, 200), SMOOTH),
		},
		TrailColor = rgb(160, 225, 255),
	},
	{
		-- Clear head dotted with bubbles.
		Id = "bubble_wrap",
		Shaft = {
			Shape = "Round",
			Length = 3.1,
			Width = 0.36,
			Color = rgb(120, 200, 140),
			Material = SMOOTH,
		},
		Head = {
			Shape = "Cylinder",
			Size = Vector3.new(1.8, 1.35, 1.35),
			Color = rgb(215, 240, 255),
			Material = GLASS,
			Transparency = 0.15,
		},
		HandleDetails = {
			grip(3.1, 0.36, rgb(70, 160, 100)),
			pommel(3.1, 0.5, rgb(215, 240, 255), GLASS),
		},
		HeadDetails = {
			dot("Bubble", Vector3.new(-0.5, 0.62, 0), 0.34, rgb(240, 250, 255), GLASS),
			dot("Bubble", Vector3.new(0.1, 0.62, 0.15), 0.3, rgb(240, 250, 255), GLASS),
			dot("Bubble", Vector3.new(0.6, 0.6, -0.1), 0.34, rgb(240, 250, 255), GLASS),
			dot("Bubble", Vector3.new(-0.2, -0.6, 0.1), 0.32, rgb(240, 250, 255), GLASS),
			dot("Bubble", Vector3.new(0.45, 0, 0.62), 0.32, rgb(240, 250, 255), GLASS),
			dot("Bubble", Vector3.new(-0.35, 0, -0.62), 0.32, rgb(240, 250, 255), GLASS),
			band("FaceA", 0.92, 0.1, 1.2, rgb(150, 220, 170), SMOOTH),
			band("FaceB", -0.92, 0.1, 1.2, rgb(150, 220, 170), SMOOTH),
		},
		TrailColor = rgb(220, 245, 255),
	},
	{
		-- Dark metal with glowing cyan and pink strips.
		Id = "neon",
		Shaft = {
			Shape = "Round",
			Length = 3.2,
			Width = 0.34,
			Color = rgb(30, 30, 40),
			Material = METAL,
		},
		Head = {
			Shape = "Block",
			Size = Vector3.new(1.8, 0.95, 0.95),
			Color = rgb(28, 28, 38),
			Material = METAL,
		},
		HandleDetails = {
			grip(3.2, 0.34, rgb(20, 20, 26)),
			sleeve("NeonRing", 3.2 / 2 - 1.15, 0.08, 0.44, rgb(0, 240, 255), NEON),
			collar(3.2, 0.95, 0.34, rgb(255, 60, 200), NEON),
		},
		HeadDetails = {
			plate("NeonBandA", 0.55, 0.1, 1.0, rgb(0, 240, 255), NEON),
			plate("NeonBandB", -0.55, 0.1, 1.0, rgb(0, 240, 255), NEON),
			plate("FaceA", 0.93, 0.08, 0.75, rgb(255, 60, 200), NEON),
			plate("FaceB", -0.93, 0.08, 0.75, rgb(255, 60, 200), NEON),
		},
		TrailColor = rgb(0, 240, 255),
		Glow = { Color = rgb(0, 220, 255), Range = 4, Brightness = 0.6 },
	},
	{
		-- Cartoon / mega: an oversized striped head.
		Id = "rainbow_mega",
		Shaft = {
			Shape = "Round",
			Length = 3.0,
			Width = 0.42,
			Color = rgb(255, 230, 90),
			Material = SMOOTH,
		},
		Head = {
			Shape = "Cylinder",
			Size = Vector3.new(2.2, 1.75, 1.75),
			Color = rgb(255, 120, 220),
			Material = SMOOTH,
		},
		HandleDetails = {
			grip(3.0, 0.42, rgb(255, 120, 220)),
			pommel(3.0, 0.62, rgb(120, 220, 255), SMOOTH),
		},
		HeadDetails = {
			band("StripeRed", -0.72, 0.2, 1.78, rgb(255, 80, 80), SMOOTH),
			band("StripeOrange", -0.36, 0.2, 1.78, rgb(255, 160, 60), SMOOTH),
			band("StripeYellow", 0, 0.2, 1.78, rgb(255, 230, 80), SMOOTH),
			band("StripeGreen", 0.36, 0.2, 1.78, rgb(100, 220, 120), SMOOTH),
			band("StripeBlue", 0.72, 0.2, 1.78, rgb(90, 160, 255), SMOOTH),
			band("FaceA", 1.12, 0.1, 1.45, rgb(255, 255, 255), SMOOTH),
			band("FaceB", -1.12, 0.1, 1.45, rgb(255, 255, 255), SMOOTH),
		},
		TrailColor = rgb(255, 200, 240),
	},
	{
		-- Polished gold with a few soft glints.
		Id = "golden",
		Shaft = {
			Shape = "Round",
			Length = 3.2,
			Width = 0.34,
			Color = rgb(110, 45, 35),
			Material = WOOD,
		},
		Head = {
			Shape = "Cylinder",
			Size = Vector3.new(1.85, 1.3, 1.3),
			Color = rgb(255, 200, 60),
			Material = METAL,
			Reflectance = 0.2,
		},
		HandleDetails = {
			grip(3.2, 0.34, rgb(140, 30, 40)),
			collar(3.2, 1.3, 0.34, rgb(255, 200, 60), METAL),
			pommel(3.2, 0.5, rgb(255, 200, 60), METAL),
		},
		HeadDetails = {
			band("BandA", 0.6, 0.12, 1.36, rgb(220, 150, 30), METAL),
			band("BandB", -0.6, 0.12, 1.36, rgb(220, 150, 30), METAL),
			band("FaceA", 0.95, 0.1, 1.1, rgb(255, 235, 150), METAL),
			band("FaceB", -0.95, 0.1, 1.1, rgb(255, 235, 150), METAL),
		},
		TrailColor = rgb(255, 225, 120),
		Particles = {
			Color = rgb(255, 240, 170),
			FadeColor = rgb(255, 200, 60),
			Rate = 2,
			Lifetime = 0.8,
			Size = 0.18,
			Speed = 0.3,
			Rise = 0,
		},
	},
	{
		-- Lava-rock head with glowing orange faces and a few rising embers.
		Id = "fire",
		Shaft = {
			Shape = "Round",
			Length = 3.2,
			Width = 0.36,
			Color = rgb(50, 42, 40),
			Material = METAL,
		},
		Head = {
			Shape = "Block",
			Size = Vector3.new(1.8, 1.05, 1.05),
			Color = rgb(120, 40, 25),
			Material = Enum.Material.CrackedLava,
		},
		HandleDetails = {
			grip(3.2, 0.36, rgb(90, 45, 30)),
			sleeve("EmberRing", 3.2 / 2 - 1.15, 0.08, 0.46, rgb(255, 130, 30), NEON),
			collar(3.2, 1.05, 0.36, rgb(70, 60, 58), METAL),
		},
		HeadDetails = {
			plate("FaceA", 0.93, 0.08, 0.85, rgb(255, 120, 30), NEON),
			plate("FaceB", -0.93, 0.08, 0.85, rgb(255, 120, 30), NEON),
			plate("Band", 0, 0.14, 1.09, rgb(60, 40, 35), METAL),
		},
		TrailColor = rgb(255, 150, 60),
		Glow = { Color = rgb(255, 130, 50), Range = 5, Brightness = 0.8 },
		Particles = {
			Color = rgb(255, 210, 90),
			FadeColor = rgb(255, 90, 30),
			Rate = 5,
			Lifetime = 0.7,
			Size = 0.16,
			Speed = 0.6,
			Rise = 3,
		},
	},
	{
		-- White-blue head with bolt stripes and the odd spark.
		Id = "lightning",
		Shaft = {
			Shape = "Round",
			Length = 3.2,
			Width = 0.34,
			Color = rgb(30, 40, 80),
			Material = METAL,
		},
		Head = {
			Shape = "Cylinder",
			Size = Vector3.new(1.8, 1.25, 1.25),
			Color = rgb(215, 230, 255),
			Material = METAL,
			Reflectance = 0.1,
		},
		HandleDetails = {
			grip(3.2, 0.34, rgb(255, 220, 50)),
			collar(3.2, 1.25, 0.34, rgb(80, 180, 255), NEON),
			pommel(3.2, 0.48, rgb(30, 40, 80), METAL),
		},
		HeadDetails = {
			{
				Name = "BoltA",
				Shape = "Block",
				Size = Vector3.new(0.8, 0.1, 1.29),
				Offset = CFrame.new(-0.25, 0, 0) * CFrame.Angles(0, 0, math.rad(35)),
				Color = rgb(255, 225, 60),
				Material = NEON,
			},
			{
				Name = "BoltB",
				Shape = "Block",
				Size = Vector3.new(0.8, 0.1, 1.29),
				Offset = CFrame.new(0.25, 0, 0) * CFrame.Angles(0, 0, math.rad(-35)),
				Color = rgb(255, 225, 60),
				Material = NEON,
			},
			band("FaceA", 0.93, 0.08, 1.05, rgb(80, 180, 255), NEON),
			band("FaceB", -0.93, 0.08, 1.05, rgb(80, 180, 255), NEON),
		},
		TrailColor = rgb(160, 210, 255),
		Glow = { Color = rgb(150, 200, 255), Range = 4, Brightness = 0.7 },
		Particles = {
			Color = rgb(220, 240, 255),
			FadeColor = rgb(100, 180, 255),
			Rate = 4,
			Lifetime = 0.25,
			Size = 0.12,
			Speed = 3,
			Rise = 0,
		},
	},
	{
		-- A little planet: deep-space head, a glowing ring and drifting stars.
		Id = "cosmic",
		Shaft = {
			Shape = "Round",
			Length = 3.2,
			Width = 0.34,
			Color = rgb(60, 30, 110),
			Material = METAL,
		},
		Head = {
			Shape = "Cylinder",
			Size = Vector3.new(1.8, 1.4, 1.4),
			Color = rgb(30, 20, 70),
			Material = SMOOTH,
			Reflectance = 0.15,
		},
		HandleDetails = {
			grip(3.2, 0.34, rgb(30, 20, 60)),
			sleeve("StarRing", 3.2 / 2 - 1.15, 0.08, 0.44, rgb(190, 140, 255), NEON),
			collar(3.2, 1.4, 0.34, rgb(120, 220, 255), NEON),
		},
		HeadDetails = {
			{
				Name = "PlanetRing",
				Shape = "Cylinder",
				Size = Vector3.new(0.06, 2.1, 2.1),
				Offset = CFrame.Angles(0, math.rad(15), 0),
				Color = rgb(200, 160, 255),
				Material = NEON,
				Transparency = 0.35,
			},
			dot("Star", Vector3.new(-0.5, 0.62, 0.2), 0.14, rgb(255, 255, 255), NEON),
			dot("Star", Vector3.new(0.35, -0.6, 0.25), 0.12, rgb(255, 255, 255), NEON),
			dot("Star", Vector3.new(0.55, 0.3, -0.6), 0.12, rgb(255, 255, 255), NEON),
			band("FaceA", 0.93, 0.08, 1.15, rgb(120, 220, 255), NEON),
			band("FaceB", -0.93, 0.08, 1.15, rgb(120, 220, 255), NEON),
		},
		TrailColor = rgb(190, 150, 255),
		Glow = { Color = rgb(170, 120, 255), Range = 4, Brightness = 0.6 },
		Particles = {
			Color = rgb(255, 255, 255),
			FadeColor = rgb(180, 140, 255),
			Rate = 3,
			Lifetime = 1.2,
			Size = 0.12,
			Speed = 0.3,
			Rise = 0,
		},
	},
	{
		-- Top tier: a heavy industrial crusher with hazard stripes.
		Id = "stress_crusher",
		Shaft = {
			Shape = "Square",
			Length = 3.3,
			Width = 0.42,
			Color = rgb(110, 115, 125),
			Material = METAL,
		},
		Head = {
			Shape = "Block",
			Size = Vector3.new(2.2, 1.45, 1.45),
			Color = rgb(85, 90, 100),
			Material = Enum.Material.DiamondPlate,
		},
		HandleDetails = {
			grip(3.3, 0.42, rgb(200, 40, 40)),
			collar(3.3, 1.45, 0.42, rgb(255, 200, 40), SMOOTH),
			{
				Name = "Pommel",
				Shape = "Block",
				Size = Vector3.new(0.6, 0.6, 0.3),
				Offset = CFrame.new(0, 0, 3.3 / 2 + 0.1),
				Color = rgb(60, 62, 70),
				Material = METAL,
			},
		},
		HeadDetails = {
			plate("FaceA", 1.1, 0.16, 1.3, rgb(200, 205, 215), METAL),
			plate("FaceB", -1.1, 0.16, 1.3, rgb(200, 205, 215), METAL),
			plate("HazardA", 0.55, 0.2, 1.5, rgb(255, 200, 40), SMOOTH),
			plate("HazardB", -0.55, 0.2, 1.5, rgb(255, 200, 40), SMOOTH),
			plate("HazardDarkA", 0.75, 0.2, 1.5, rgb(30, 30, 35), SMOOTH),
			plate("HazardDarkB", -0.75, 0.2, 1.5, rgb(30, 30, 35), SMOOTH),
			{
				Name = "Gauge",
				Shape = "Block",
				Size = Vector3.new(0.5, 0.08, 0.4),
				Offset = CFrame.new(0, 0.74, 0),
				Color = rgb(255, 70, 70),
				Material = NEON,
			},
		},
		TrailColor = rgb(255, 210, 90),
	},
	-- Legendary tier (2026-10-10) ---------------------------------------------
	-- Each has its own impact burst (Impact: Lib/HitEffects tints the sparkles
	-- and the ring where it lands with these colours).
	{
		-- A judge's gavel charged with a thunderstorm.
		Id = "thunder_gavel",
		Shaft = {
			Shape = "Round",
			Length = 3.3,
			Width = 0.36,
			Color = rgb(40, 45, 70),
			Material = METAL,
		},
		Head = {
			Shape = "Cylinder",
			Size = Vector3.new(2.0, 1.25, 1.25),
			Color = rgb(55, 70, 120),
			Material = METAL,
			Reflectance = 0.1,
		},
		HandleDetails = {
			grip(3.3, 0.36, rgb(25, 28, 45)),
			collar(3.3, 1.25, 0.36, rgb(240, 200, 70), METAL),
			pommel(3.3, 0.5, rgb(120, 180, 255), NEON),
		},
		HeadDetails = {
			band("FaceA", 0.96, 0.08, 1.05, rgb(150, 210, 255), NEON),
			band("FaceB", -0.96, 0.08, 1.05, rgb(150, 210, 255), NEON),
			band("GoldA", 0.55, 0.14, 1.32, rgb(240, 200, 70), METAL),
			band("GoldB", -0.55, 0.14, 1.32, rgb(240, 200, 70), METAL),
			{
				Name = "Bolt",
				Shape = "Block",
				Size = Vector3.new(0.12, 0.7, 0.08),
				Offset = CFrame.new(0.12, 0.45, -0.6) * CFrame.Angles(0, 0, math.rad(25)),
				Color = rgb(255, 235, 90),
				Material = NEON,
			},
			{
				Name = "Bolt",
				Shape = "Block",
				Size = Vector3.new(0.12, 0.7, 0.08),
				Offset = CFrame.new(-0.12, -0.2, -0.6) * CFrame.Angles(0, 0, math.rad(-25)),
				Color = rgb(255, 235, 90),
				Material = NEON,
			},
		},
		TrailColor = rgb(150, 200, 255),
		Glow = { Color = rgb(120, 170, 255), Range = 5, Brightness = 0.7 },
		Particles = {
			Color = rgb(255, 255, 200),
			FadeColor = rgb(120, 170, 255),
			Rate = 4,
			Lifetime = 0.3,
			Size = 0.12,
			Speed = 3,
			Rise = 0,
		},
		Impact = { Color = rgb(170, 210, 255), Accent = rgb(255, 235, 90) },
	},
	{
		-- A block of glacier ice with crystal spikes; snow drifts down from it.
		Id = "frost",
		Shaft = {
			Shape = "Round",
			Length = 3.2,
			Width = 0.34,
			Color = rgb(200, 215, 230),
			Material = METAL,
		},
		Head = {
			Shape = "Block",
			Size = Vector3.new(2.0, 1.15, 1.15),
			Color = rgb(170, 225, 255),
			Material = Enum.Material.Ice,
			Transparency = 0.1,
		},
		HandleDetails = {
			grip(3.2, 0.34, rgb(235, 245, 255)),
			collar(3.2, 1.15, 0.34, rgb(120, 210, 255), NEON),
			pommel(3.2, 0.5, rgb(190, 235, 255), Enum.Material.Ice),
		},
		HeadDetails = {
			plate("FaceA", 1.02, 0.1, 1.0, rgb(245, 252, 255), GLASS),
			plate("FaceB", -1.02, 0.1, 1.0, rgb(245, 252, 255), GLASS),
			{
				Name = "Crystal",
				Shape = "Block",
				Size = Vector3.new(0.2, 0.55, 0.2),
				Offset = CFrame.new(0, 0.75, 0) * CFrame.Angles(0, math.rad(45), 0),
				Color = rgb(150, 230, 255),
				Material = NEON,
				Transparency = 0.3,
			},
			{
				Name = "Crystal",
				Shape = "Block",
				Size = Vector3.new(0.16, 0.42, 0.16),
				Offset = CFrame.new(0.42, 0.68, 0.1) * CFrame.Angles(0, 0, math.rad(-20)),
				Color = rgb(150, 230, 255),
				Material = NEON,
				Transparency = 0.3,
			},
			{
				Name = "Crystal",
				Shape = "Block",
				Size = Vector3.new(0.16, 0.42, 0.16),
				Offset = CFrame.new(-0.42, 0.68, -0.1) * CFrame.Angles(0, 0, math.rad(20)),
				Color = rgb(150, 230, 255),
				Material = NEON,
				Transparency = 0.3,
			},
		},
		TrailColor = rgb(190, 240, 255),
		Glow = { Color = rgb(150, 220, 255), Range = 4, Brightness = 0.5 },
		Particles = {
			Color = rgb(255, 255, 255),
			FadeColor = rgb(170, 225, 255),
			Rate = 4,
			Lifetime = 1.2,
			Size = 0.14,
			Speed = 0.3,
			Rise = -0.6, -- snowflakes drift down
		},
		Impact = { Color = rgb(200, 240, 255), Accent = rgb(120, 200, 255) },
	},
	{
		-- Cooled basalt around a molten core: glowing cracks and rising embers.
		Id = "lava",
		Shaft = {
			Shape = "Square",
			Length = 3.3,
			Width = 0.4,
			Color = rgb(55, 40, 35),
			Material = Enum.Material.Basalt,
		},
		Head = {
			Shape = "Cylinder",
			Size = Vector3.new(2.05, 1.4, 1.4),
			Color = rgb(60, 45, 40),
			Material = Enum.Material.Basalt,
		},
		HandleDetails = {
			grip(3.3, 0.4, rgb(30, 25, 25)),
			collar(3.3, 1.4, 0.4, rgb(255, 110, 30), NEON),
			sleeve("Ember", 3.3 / 2 - 1.2, 0.08, 0.46, rgb(255, 150, 40), NEON),
		},
		HeadDetails = {
			band("FaceA", 0.98, 0.1, 1.2, rgb(255, 120, 40), Enum.Material.CrackedLava),
			band("FaceB", -0.98, 0.1, 1.2, rgb(255, 120, 40), Enum.Material.CrackedLava),
			band("CrackA", 0.4, 0.06, 1.44, rgb(255, 120, 30), NEON),
			band("CrackB", -0.3, 0.06, 1.44, rgb(255, 90, 20), NEON),
			band("CrackC", 0.05, 0.04, 1.43, rgb(255, 180, 60), NEON),
		},
		TrailColor = rgb(255, 140, 50),
		Glow = { Color = rgb(255, 120, 40), Range = 5, Brightness = 0.8 },
		Particles = {
			Color = rgb(255, 220, 120),
			FadeColor = rgb(255, 70, 20),
			Rate = 5,
			Lifetime = 1.0,
			Size = 0.14,
			Speed = 0.6,
			Rise = 2.5,
		},
		Impact = { Color = rgb(255, 170, 60), Accent = rgb(255, 70, 20) },
	},
	{
		-- A clear violet prism with diamond faces and a pink heart of light.
		Id = "crystal",
		Shaft = {
			Shape = "Round",
			Length = 3.2,
			Width = 0.32,
			Color = rgb(235, 235, 245),
			Material = METAL,
		},
		Head = {
			Shape = "Block",
			Size = Vector3.new(2.1, 1.2, 1.2),
			Color = rgb(200, 150, 255),
			Material = GLASS,
			Transparency = 0.25,
			Reflectance = 0.3,
		},
		HandleDetails = {
			grip(3.2, 0.32, rgb(150, 110, 220)),
			collar(3.2, 1.2, 0.32, rgb(255, 160, 230), NEON),
			pommel(3.2, 0.48, rgb(220, 180, 255), GLASS),
		},
		HeadDetails = {
			{
				Name = "FaceA",
				Shape = "Block",
				Size = Vector3.new(0.5, 0.85, 0.85),
				Offset = CFrame.new(1.05, 0, 0) * CFrame.Angles(math.rad(45), 0, 0),
				Color = rgb(235, 210, 255),
				Material = GLASS,
				Transparency = 0.2,
				Reflectance = 0.4,
			},
			{
				Name = "FaceB",
				Shape = "Block",
				Size = Vector3.new(0.5, 0.85, 0.85),
				Offset = CFrame.new(-1.05, 0, 0) * CFrame.Angles(math.rad(45), 0, 0),
				Color = rgb(235, 210, 255),
				Material = GLASS,
				Transparency = 0.2,
				Reflectance = 0.4,
			},
			dot("Heart", Vector3.new(0, 0, 0), 0.55, rgb(255, 130, 220), NEON),
			plate("Rim", 0, 0.08, 1.25, rgb(255, 255, 255), NEON),
		},
		TrailColor = rgb(240, 170, 255),
		Glow = { Color = rgb(230, 150, 255), Range = 4, Brightness = 0.6 },
		Particles = {
			Color = rgb(255, 170, 230),
			FadeColor = rgb(150, 230, 255),
			Rate = 4,
			Lifetime = 0.9,
			Size = 0.13,
			Speed = 0.4,
			Rise = 0.4,
		},
		Impact = { Color = rgb(255, 170, 240), Accent = rgb(150, 230, 255) },
	},
	{
		-- A humming energy cell: green plasma behind glass between steel caps.
		Id = "plasma",
		Shaft = {
			Shape = "Square",
			Length = 3.3,
			Width = 0.38,
			Color = rgb(50, 55, 65),
			Material = METAL,
		},
		Head = {
			Shape = "Cylinder",
			Size = Vector3.new(2.1, 1.3, 1.3),
			Color = rgb(60, 255, 200),
			Material = NEON,
			Transparency = 0.35,
		},
		HandleDetails = {
			grip(3.3, 0.38, rgb(25, 30, 35)),
			collar(3.3, 1.3, 0.38, rgb(170, 175, 190), METAL),
			pommel(3.3, 0.5, rgb(60, 255, 200), NEON),
		},
		HeadDetails = {
			band("CapA", 0.88, 0.34, 1.42, rgb(70, 75, 90), METAL),
			band("CapB", -0.88, 0.34, 1.42, rgb(70, 75, 90), METAL),
			band("CoilA", 0.38, 0.08, 1.38, rgb(200, 205, 220), METAL),
			band("CoilB", -0.38, 0.08, 1.38, rgb(200, 205, 220), METAL),
			dot("Core", Vector3.new(0, 0, 0), 0.6, rgb(220, 255, 240), NEON),
		},
		TrailColor = rgb(90, 255, 210),
		Glow = { Color = rgb(60, 255, 200), Range = 5, Brightness = 0.8 },
		Particles = {
			Color = rgb(200, 255, 240),
			FadeColor = rgb(40, 220, 180),
			Rate = 5,
			Lifetime = 0.4,
			Size = 0.1,
			Speed = 2.5,
			Rise = 0,
		},
		Impact = { Color = rgb(120, 255, 210), Accent = rgb(220, 255, 120) },
	},
	{
		-- Carved jade with gold faces, a golden dragon spine and a red tassel.
		Id = "jade_dragon",
		Shaft = {
			Shape = "Round",
			Length = 3.4,
			Width = 0.34,
			Color = rgb(170, 40, 40),
			Material = WOOD,
		},
		Head = {
			Shape = "Block",
			Size = Vector3.new(2.15, 1.25, 1.25),
			Color = rgb(60, 180, 120),
			Material = Enum.Material.Marble,
		},
		HandleDetails = {
			grip(3.4, 0.34, rgb(240, 200, 80)),
			collar(3.4, 1.25, 0.34, rgb(240, 200, 80), METAL),
			{
				Name = "Tassel",
				Shape = "Block",
				Size = Vector3.new(0.14, 0.14, 0.5),
				Offset = CFrame.new(0, -0.15, 3.4 / 2 + 0.05),
				Color = rgb(220, 40, 40),
				Material = FABRIC,
			},
		},
		HeadDetails = {
			plate("FaceA", 1.1, 0.12, 1.1, rgb(240, 200, 80), METAL),
			plate("FaceB", -1.1, 0.12, 1.1, rgb(240, 200, 80), METAL),
			dot("Spine", Vector3.new(-0.55, 0.66, 0), 0.26, rgb(240, 200, 80), METAL),
			dot("Spine", Vector3.new(0, 0.7, 0), 0.3, rgb(240, 200, 80), METAL),
			dot("Spine", Vector3.new(0.55, 0.66, 0), 0.26, rgb(240, 200, 80), METAL),
			dot("Pearl", Vector3.new(0, 0, -0.64), 0.3, rgb(255, 250, 235), NEON),
		},
		TrailColor = rgb(120, 230, 160),
		Glow = { Color = rgb(255, 220, 120), Range = 4, Brightness = 0.5 },
		Particles = {
			Color = rgb(255, 230, 140),
			FadeColor = rgb(80, 210, 140),
			Rate = 3,
			Lifetime = 1.3,
			Size = 0.12,
			Speed = 0.3,
			Rise = 0.5,
		},
		Impact = { Color = rgb(255, 220, 110), Accent = rgb(80, 220, 140) },
	},
	{
		-- A pocket sun: a blazing core inside a corona ring, with sun rays.
		Id = "solar",
		Shaft = {
			Shape = "Round",
			Length = 3.3,
			Width = 0.34,
			Color = rgb(255, 245, 220),
			Material = METAL,
		},
		Head = {
			Shape = "Cylinder",
			Size = Vector3.new(1.9, 1.5, 1.5),
			Color = rgb(255, 190, 50),
			Material = NEON,
		},
		HandleDetails = {
			grip(3.3, 0.34, rgb(230, 150, 40)),
			collar(3.3, 1.5, 0.34, rgb(255, 120, 40), NEON),
			pommel(3.3, 0.5, rgb(255, 220, 90), NEON),
		},
		HeadDetails = {
			band("FaceA", 0.95, 0.1, 1.2, rgb(255, 250, 220), NEON),
			band("FaceB", -0.95, 0.1, 1.2, rgb(255, 250, 220), NEON),
			{
				Name = "Corona",
				Shape = "Cylinder",
				Size = Vector3.new(0.06, 2.3, 2.3),
				Offset = CFrame.identity,
				Color = rgb(255, 150, 40),
				Material = NEON,
				Transparency = 0.45,
			},
			{
				Name = "Ray",
				Shape = "Block",
				Size = Vector3.new(0.1, 2.3, 0.1),
				Offset = CFrame.new(0, 0, 0) * CFrame.Angles(math.rad(45), 0, 0),
				Color = rgb(255, 230, 120),
				Material = NEON,
				Transparency = 0.3,
			},
			{
				Name = "Ray",
				Shape = "Block",
				Size = Vector3.new(0.1, 2.3, 0.1),
				Offset = CFrame.new(0, 0, 0) * CFrame.Angles(math.rad(-45), 0, 0),
				Color = rgb(255, 230, 120),
				Material = NEON,
				Transparency = 0.3,
			},
		},
		TrailColor = rgb(255, 210, 80),
		Glow = { Color = rgb(255, 200, 90), Range = 6, Brightness = 1 },
		Particles = {
			Color = rgb(255, 245, 180),
			FadeColor = rgb(255, 120, 30),
			Rate = 5,
			Lifetime = 0.8,
			Size = 0.15,
			Speed = 0.5,
			Rise = 1.5,
		},
		Impact = { Color = rgb(255, 230, 120), Accent = rgb(255, 120, 30) },
	},
	{
		-- A slab of night with violet edges and a ring of light around it.
		Id = "void",
		Shaft = {
			Shape = "Square",
			Length = 3.4,
			Width = 0.4,
			Color = rgb(20, 15, 30),
			Material = METAL,
		},
		Head = {
			Shape = "Block",
			Size = Vector3.new(2.25, 1.4, 1.4),
			Color = rgb(15, 10, 25),
			Material = SMOOTH,
			Reflectance = 0.2,
		},
		HandleDetails = {
			grip(3.4, 0.4, rgb(60, 30, 100)),
			collar(3.4, 1.4, 0.4, rgb(170, 90, 255), NEON),
			pommel(3.4, 0.52, rgb(170, 90, 255), NEON),
		},
		HeadDetails = {
			plate("FaceA", 1.13, 0.08, 1.25, rgb(170, 90, 255), NEON),
			plate("FaceB", -1.13, 0.08, 1.25, rgb(170, 90, 255), NEON),
			plate("EdgeA", 0.7, 0.05, 1.42, rgb(120, 60, 200), NEON),
			plate("EdgeB", -0.7, 0.05, 1.42, rgb(120, 60, 200), NEON),
			{
				Name = "Horizon",
				Shape = "Cylinder",
				Size = Vector3.new(0.05, 2.2, 2.2),
				Offset = CFrame.Angles(0, math.rad(90), math.rad(20)),
				Color = rgb(200, 140, 255),
				Material = NEON,
				Transparency = 0.4,
			},
		},
		TrailColor = rgb(160, 90, 255),
		Glow = { Color = rgb(150, 80, 255), Range = 5, Brightness = 0.7 },
		Particles = {
			Color = rgb(220, 180, 255),
			FadeColor = rgb(60, 20, 120),
			Rate = 4,
			Lifetime = 1.1,
			Size = 0.14,
			Speed = 0.2,
			Rise = -0.3,
		},
		Impact = { Color = rgb(190, 120, 255), Accent = rgb(60, 20, 140) },
	},
	{
		-- A swirling galaxy with a ringed planet and twinkling stars.
		Id = "galaxy",
		Shaft = {
			Shape = "Round",
			Length = 3.4,
			Width = 0.34,
			Color = rgb(25, 20, 50),
			Material = METAL,
		},
		Head = {
			Shape = "Cylinder",
			Size = Vector3.new(2.1, 1.45, 1.45),
			Color = rgb(35, 40, 110),
			Material = SMOOTH,
			Reflectance = 0.25,
		},
		HandleDetails = {
			grip(3.4, 0.34, rgb(60, 40, 120)),
			collar(3.4, 1.45, 0.34, rgb(255, 120, 220), NEON),
			pommel(3.4, 0.5, rgb(120, 200, 255), NEON),
		},
		HeadDetails = {
			band("SwirlA", 0.5, 0.1, 1.48, rgb(255, 120, 220), NEON),
			band("SwirlB", -0.5, 0.1, 1.48, rgb(120, 200, 255), NEON),
			band("FaceA", 1.0, 0.08, 1.2, rgb(200, 220, 255), NEON),
			band("FaceB", -1.0, 0.08, 1.2, rgb(200, 220, 255), NEON),
			{
				Name = "PlanetRing",
				Shape = "Cylinder",
				Size = Vector3.new(0.05, 2.3, 2.3),
				Offset = CFrame.Angles(0, math.rad(20), math.rad(70)),
				Color = rgb(255, 210, 150),
				Material = NEON,
				Transparency = 0.35,
			},
			dot("Star", Vector3.new(-0.25, 0.7, 0.3), 0.13, rgb(255, 255, 255), NEON),
			dot("Star", Vector3.new(0.3, -0.68, -0.3), 0.12, rgb(255, 255, 255), NEON),
		},
		TrailColor = rgb(180, 140, 255),
		Glow = { Color = rgb(140, 120, 255), Range = 5, Brightness = 0.7 },
		Particles = {
			Color = rgb(255, 255, 255),
			FadeColor = rgb(255, 120, 220),
			Rate = 4,
			Lifetime = 1.3,
			Size = 0.13,
			Speed = 0.3,
			Rise = 0,
		},
		Impact = { Color = rgb(255, 150, 230), Accent = rgb(120, 200, 255) },
	},
	{
		-- The legend: white marble and gold with a jade inlay and a floating halo.
		Id = "zen_titan",
		Shaft = {
			Shape = "Round",
			Length = 3.5,
			Width = 0.38,
			Color = rgb(245, 240, 230),
			Material = Enum.Material.Marble,
		},
		Head = {
			Shape = "Block",
			Size = Vector3.new(2.4, 1.5, 1.5),
			Color = rgb(250, 248, 240),
			Material = Enum.Material.Marble,
		},
		HandleDetails = {
			grip(3.5, 0.38, rgb(230, 190, 80)),
			collar(3.5, 1.5, 0.38, rgb(230, 190, 80), METAL),
			pommel(3.5, 0.56, rgb(120, 230, 170), NEON),
		},
		HeadDetails = {
			plate("FaceA", 1.22, 0.14, 1.35, rgb(230, 190, 80), METAL),
			plate("FaceB", -1.22, 0.14, 1.35, rgb(230, 190, 80), METAL),
			plate("Jade", 0, 0.12, 1.52, rgb(100, 220, 160), NEON),
			plate("TrimA", 0.6, 0.06, 1.53, rgb(230, 190, 80), METAL),
			plate("TrimB", -0.6, 0.06, 1.53, rgb(230, 190, 80), METAL),
			{
				Name = "Halo",
				Shape = "Cylinder",
				Size = Vector3.new(0.06, 1.4, 1.4),
				Offset = CFrame.new(0, 1.15, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Color = rgb(255, 230, 140),
				Material = NEON,
				Transparency = 0.25,
			},
		},
		TrailColor = rgb(255, 240, 200),
		Glow = { Color = rgb(255, 240, 200), Range = 6, Brightness = 1 },
		Particles = {
			Color = rgb(255, 250, 230),
			FadeColor = rgb(140, 230, 180),
			Rate = 4,
			Lifetime = 1.4,
			Size = 0.15,
			Speed = 0.3,
			Rise = 0.8,
		},
		Impact = { Color = rgb(255, 245, 210), Accent = rgb(120, 230, 170) },
	},
	{
		-- Robux Mystery Hammer: gold and purple with a soft purple glint.
		Id = "mystery",
		Shaft = {
			Shape = "Round",
			Length = 3.2,
			Width = 0.36,
			Color = rgb(120, 70, 200),
			Material = METAL,
		},
		Head = {
			Shape = "Cylinder",
			Size = Vector3.new(1.85, 1.35, 1.35),
			Color = rgb(255, 200, 60),
			Material = METAL,
			Reflectance = 0.15,
		},
		HandleDetails = {
			grip(3.2, 0.36, rgb(70, 30, 130)),
			collar(3.2, 1.35, 0.36, rgb(255, 200, 60), METAL),
			pommel(3.2, 0.52, rgb(190, 120, 255), NEON),
		},
		HeadDetails = {
			band("BandA", 0.5, 0.14, 1.4, rgb(120, 70, 200), METAL),
			band("BandB", -0.5, 0.14, 1.4, rgb(120, 70, 200), METAL),
			band("FaceA", 0.94, 0.08, 1.1, rgb(190, 120, 255), NEON),
			band("FaceB", -0.94, 0.08, 1.1, rgb(190, 120, 255), NEON),
		},
		TrailColor = rgb(210, 160, 255),
		Particles = {
			Color = rgb(230, 200, 255),
			FadeColor = rgb(150, 90, 230),
			Rate = 2,
			Lifetime = 0.8,
			Size = 0.16,
			Speed = 0.3,
			Rise = 0,
		},
	},
}

local byId: { [string]: Style } = {}
for _, style in styles do
	if byId[style.Id] then
		error(string.format("[HammerStyleConfig] duplicate style id %q", style.Id))
	end
	byId[style.Id] = table.freeze(style)
end

return table.freeze({
	List = table.freeze(styles),
	ById = table.freeze(byId),
	-- Limits every style is held to (tests/Unit/Config/HammerStyleConfig.spec):
	-- readable while swinging, in proportion with the arm, cheap to render.
	MinShaftLength = 2.8,
	MaxShaftLength = 3.6,
	MaxHeadSize = 2.4,
	MaxDetails = 10,
	MaxGlowRange = 6,
	MaxGlowBrightness = 1,
	MaxParticleRate = 6,
})
