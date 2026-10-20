--!strict
--[[
	The Synthesis Machine in the world, on this client (built by the server's
	Lib/SynthesisMachineBuilder, docs/SYNTHESIS.md):
	  * idle: the two energy rings turn slowly in opposite directions, the
	    core breathes and the neon strips pulse. Each is one repeating tween
	    started once; no per-frame script work.
	  * a synthesis (the server bumps the model's play counter after every
	    one, so everyone nearby sees it): the input sockets light one by one,
	    the core swells and flashes, a burst of sparks in the result tier's
	    colour (more for rarer tiers), and the OUTPUT orb glows in that colour
	    for a few seconds. About 3 seconds, then back to idle.
	Reduced motion: no spinning or swelling, just the colours.
	Display only: the server decides every result (SynthesisService).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local SynthesisConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("SynthesisConfig"))
local UiTokens = require(script.Parent.Parent.Lib.UiTokens)

local SynthesisMachineController = {}

-- Names and attributes set by Lib/SynthesisMachineBuilder (server-only module).
local MODEL_NAME = "SynthesisMachine"
local PROMPT_NAME = "SynthesisPrompt"
local GLOW_ATTRIBUTE = "SynthesisGlow"
local RING_ATTRIBUTE = "SynthesisRing"
local SLOT_ATTRIBUTE = "SynthesisSlot"
local PLAY_ATTRIBUTE = "SynthesisPlays"
local TIER_ATTRIBUTE = "SynthesisTier"

local RING_SECONDS = 7
local PULSE_SECONDS = 1.6
local SLOT_STEP = 0.18
local ORB_SECONDS = 3.5
local ENERGY = Color3.fromRGB(110, 235, 255)
-- Sparks per tier order (Common .. Legendary).
local BURST_SIZE = { 12, 18, 30, 45, 70 }

local current: Model? = nil
local playToken = 0
-- The core's resting size; its breathing tween restarts from it after a play.
local coreSize = Vector3.one

-- Where the machine's prompt is, once the machine has streamed in.
function SynthesisMachineController.promptPosition(): Vector3?
	local model = current
	local prompt = if model then model:FindFirstChild(PROMPT_NAME, true) else nil
	local anchor = if prompt then prompt.Parent else nil
	if anchor and anchor:IsA("Attachment") then
		return anchor.WorldPosition
	end
	return nil
end

local function tween(object: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local created = TweenService:Create(object, info, goal)
	created:Play()
	return created
end

local PULSE =
	TweenInfo.new(PULSE_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

local function breathe(core: BasePart): ()
	core.Size = coreSize
	if not UiTokens.reducedMotion() then
		tween(core, PULSE, { Size = coreSize * 1.15 })
	end
end

local function startIdle(model: Model): ()
	local reduced = UiTokens.reducedMotion()
	for _, child in model:GetChildren() do
		local direction = child:GetAttribute(RING_ATTRIBUTE)
		if child:IsA("Model") and typeof(direction) == "number" and not reduced then
			local root = child.PrimaryPart
			if root and root.Anchored then
				-- Orientation tweens per component, so 0 -> 360 is one full turn.
				local start = root.Orientation
				tween(
					root,
					TweenInfo.new(
						RING_SECONDS,
						Enum.EasingStyle.Linear,
						Enum.EasingDirection.In,
						-1
					),
					{ Orientation = start + Vector3.new(0, 360 * direction, 0) }
				)
			end
		end
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute(GLOW_ATTRIBUTE) == true then
			tween(descendant, PULSE, { Transparency = 0.45 })
		end
	end
	local core = model:FindFirstChild("Core")
	if core and core:IsA("BasePart") then
		coreSize = core.Size
		breathe(core)
	end
end

-- The synthesis sequence, in the result tier's colour.
local function play(model: Model): ()
	playToken += 1
	local token = playToken
	local tierName = model:GetAttribute(TIER_ATTRIBUTE)
	local tier = if typeof(tierName) == "string" then SynthesisConfig.Tiers[tierName] else nil
	local color = if tier then tier.Color else ENERGY
	local order = if tier then tier.Order else 1
	local reduced = UiTokens.reducedMotion()

	local slots: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if
			descendant:IsA("BasePart")
			and typeof(descendant:GetAttribute(SLOT_ATTRIBUTE)) == "number"
		then
			table.insert(slots, descendant)
		end
	end
	local function slotIndex(slot: BasePart): number
		local index = slot:GetAttribute(SLOT_ATTRIBUTE)
		return if typeof(index) == "number" then index else 0
	end
	table.sort(slots, function(a, b)
		return slotIndex(a) < slotIndex(b)
	end)
	for index, slot in slots do
		task.delay((index - 1) * SLOT_STEP, function()
			if token == playToken then
				slot.Color = color
				slot.Transparency = 0
			end
		end)
	end

	local core = model:FindFirstChild("Core")
	local orb = model:FindFirstChild("OutputOrb")
	local chargeAt = #slots * SLOT_STEP
	task.delay(chargeAt, function()
		if token ~= playToken or core == nil or not core:IsA("BasePart") then
			return
		end
		core.Color = color
		local light = core:FindFirstChildOfClass("PointLight")
		if light then
			light.Color = color
			light.Brightness = 3
		end
		if not reduced then
			tween(
				core,
				TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, true),
				{
					Size = coreSize * 1.9,
				}
			)
		end
		local burst = core:FindFirstChild("Burst")
		if burst and burst:IsA("ParticleEmitter") then
			burst.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
			burst:Emit(BURST_SIZE[order] or BURST_SIZE[1])
		end
	end)
	task.delay(chargeAt + 0.6, function()
		if token == playToken and orb and orb:IsA("BasePart") then
			orb.Color = color
			orb.Transparency = 0.05
		end
	end)
	task.delay(chargeAt + 0.6 + ORB_SECONDS, function()
		if token ~= playToken then
			return
		end
		for _, slot in slots do
			slot.Color = ENERGY
			slot.Transparency = 0.7
		end
		if orb and orb:IsA("BasePart") then
			tween(orb, TweenInfo.new(0.6), { Transparency = 1 })
		end
		if core and core:IsA("BasePart") then
			core.Color = ENERGY
			local light = core:FindFirstChildOfClass("PointLight")
			if light then
				light.Color = ENERGY
				light.Brightness = 1.2
			end
			breathe(core)
		end
	end)
end

local function attach(model: Model): ()
	if current == model then
		return
	end
	current = model
	startIdle(model)
	model:GetAttributeChangedSignal(PLAY_ATTRIBUTE):Connect(function()
		play(model)
	end)
end

function SynthesisMachineController.start(): ()
	local existing = Workspace:FindFirstChild(MODEL_NAME)
	if existing and existing:IsA("Model") then
		attach(existing)
	end
	Workspace.ChildAdded:Connect(function(child: Instance)
		if child.Name == MODEL_NAME and child:IsA("Model") then
			attach(child)
		end
	end)
end

return SynthesisMachineController
