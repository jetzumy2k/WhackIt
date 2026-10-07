--!strict
--[[
	Builds a hammer's parts from its look (Config/HammerStyleConfig): the held
	Tool on the server (Lib/HammerTool) and the shop preview on the client.

	Parts, all welded together, never colliding, touching or adding mass:
	  * Handle: invisible core the hand grips (Tool.Grip, see gripFor);
	  * Shaft and handle details (grip wrap, collar, pommel...): welded to it;
	  * Head: the mallet head across the far end. Its length runs along its
	    own X axis, so the swing trail and squash-and-stretch work for every
	    shape (Lib/SwingAnimator);
	  * head details (bands, face caps...): children of Head, each joined by a
	    Weld named DETAIL_WELD, so the client can scale them with the head.
	Effects (one small static light, one slow emitter) are only added for the
	held Tool, never for previews.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HammerStyleConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("HammerStyleConfig"))

local HammerModel = {}

-- Name of the Weld joining each head detail to the Head (Lib/SwingAnimator).
HammerModel.DETAIL_WELD = "DetailWeld"
-- Head attribute with the swing trail colour (Lib/SwingAnimator).
HammerModel.TRAIL_COLOR_ATTRIBUTE = "TrailColor"
-- How far from the shaft's hand end the fist sits.
local GRIP_FROM_END = 0.45
local CORE_WIDTH = 0.25
local QUARTER = math.rad(90)

export type Built = {
	Handle: BasePart,
	Head: BasePart,
}

local function newPart(name: string, shape: HammerStyleConfig.Shape, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = if shape == "Cylinder"
		then Enum.PartType.Cylinder
		elseif shape == "Ball" then Enum.PartType.Ball
		else Enum.PartType.Block
	part.Size = size
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	return part
end

local function weldTo(anchor: BasePart, part: BasePart, name: string?): ()
	local weld = Instance.new("WeldConstraint")
	if name then
		weld.Name = name
	end
	weld.Part0 = anchor
	weld.Part1 = part
	weld.Parent = anchor
end

-- Where the hand holds the Handle, in Handle space (for Tool.Grip). The hand
-- sits near +Z so the head at -Z points away from the fist (Lib/HammerTool).
function HammerModel.gripFor(style: HammerStyleConfig.Style): CFrame
	return CFrame.new(0, 0, style.Shaft.Length / 2 - GRIP_FROM_END)
end

-- The style for a hammer look: its own, or a plain two-colour one for looks
-- without a known style (so an unknown id still gives a working hammer).
function HammerModel.styleFor(
	styleId: string?,
	headColor: Color3,
	handleColor: Color3
): HammerStyleConfig.Style
	local style = if styleId then HammerStyleConfig.ById[styleId] else nil
	if style then
		return style
	end
	return {
		Id = "plain",
		Shaft = {
			Shape = "Round",
			Length = 3.2,
			Width = 0.35,
			Color = handleColor,
			Material = Enum.Material.SmoothPlastic,
		},
		Head = {
			Shape = "Cylinder",
			Size = Vector3.new(1.9, 1.35, 1.35),
			Color = headColor,
			Material = Enum.Material.SmoothPlastic,
		},
		HandleDetails = {},
		HeadDetails = {},
		TrailColor = Color3.new(1, 1, 1),
	}
end

local function addEffects(head: BasePart, style: HammerStyleConfig.Style): ()
	local glow = style.Glow
	if glow then
		local light = Instance.new("PointLight")
		light.Name = "StyleGlow"
		light.Color = glow.Color
		light.Range = math.min(glow.Range, HammerStyleConfig.MaxGlowRange)
		light.Brightness = math.min(glow.Brightness, HammerStyleConfig.MaxGlowBrightness)
		light.Shadows = false
		light.Parent = head
	end
	local particles = style.Particles
	if particles then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "StyleParticles"
		emitter.Rate = math.min(particles.Rate, HammerStyleConfig.MaxParticleRate)
		emitter.Lifetime = NumberRange.new(particles.Lifetime * 0.6, particles.Lifetime)
		emitter.Size = NumberSequence.new(particles.Size, 0)
		emitter.Speed = NumberRange.new(particles.Speed * 0.5, particles.Speed)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Acceleration = Vector3.new(0, particles.Rise, 0)
		emitter.Color = ColorSequence.new(particles.Color, particles.FadeColor)
		emitter.Transparency = NumberSequence.new(0.1, 1)
		emitter.LightEmission = 0.5
		emitter.LightInfluence = 0
		emitter.Parent = head
	end
end

-- Builds the parts into `parent` with the Handle at `origin`. Every part gets
-- its final CFrame (previews rely on that); welds hold it together in a Tool.
function HammerModel.build(
	style: HammerStyleConfig.Style,
	parent: Instance,
	origin: CFrame,
	withEffects: boolean
): Built
	local shaft = style.Shaft
	local length = shaft.Length

	local handle = newPart("Handle", "Block", Vector3.new(CORE_WIDTH, CORE_WIDTH, length))
	handle.Transparency = 1
	handle.CFrame = origin
	handle.Parent = parent

	local shaftPart = if shaft.Shape == "Round"
		then newPart("Shaft", "Cylinder", Vector3.new(length, shaft.Width, shaft.Width))
		else newPart("Shaft", "Block", Vector3.new(shaft.Width, shaft.Width, length))
	shaftPart.Color = shaft.Color
	shaftPart.Material = shaft.Material
	-- A cylinder's length runs along its X axis: turn it to lie along Z.
	shaftPart.CFrame = if shaft.Shape == "Round"
		then origin * CFrame.Angles(0, QUARTER, 0)
		else origin
	shaftPart.Parent = parent
	weldTo(handle, shaftPart)

	for _, detail in style.HandleDetails do
		local part = newPart(detail.Name, detail.Shape, detail.Size)
		part.Color = detail.Color
		part.Material = detail.Material
		part.Transparency = detail.Transparency or 0
		part.Reflectance = detail.Reflectance or 0
		part.CFrame = origin * detail.Offset
		part.Parent = parent
		weldTo(handle, part)
	end

	local headStyle = style.Head
	local head = newPart("Head", headStyle.Shape, headStyle.Size)
	head.Color = headStyle.Color
	head.Material = headStyle.Material
	head.Reflectance = headStyle.Reflectance or 0
	head.Transparency = headStyle.Transparency or 0
	-- Across the far (-Z) end, standing upright so the swing lands face-first.
	head.CFrame = origin * CFrame.new(0, 0, -length / 2) * CFrame.Angles(0, 0, QUARTER)
	head:SetAttribute(HammerModel.TRAIL_COLOR_ATTRIBUTE, style.TrailColor)
	head.Parent = parent
	weldTo(handle, head, "HeadWeld")

	for _, detail in style.HeadDetails do
		local part = newPart(detail.Name, detail.Shape, detail.Size)
		part.Color = detail.Color
		part.Material = detail.Material
		part.Transparency = detail.Transparency or 0
		part.Reflectance = detail.Reflectance or 0
		part.CFrame = head.CFrame * detail.Offset
		part.Parent = head
		-- A Weld (not a WeldConstraint): its C0 can follow the head's squash.
		local weld = Instance.new("Weld")
		weld.Name = HammerModel.DETAIL_WELD
		weld.Part0 = head
		weld.Part1 = part
		weld.C0 = detail.Offset
		weld.Parent = part
	end

	if withEffects then
		addEffects(head, style)
	end
	return { Handle = handle, Head = head }
end

return HammerModel
