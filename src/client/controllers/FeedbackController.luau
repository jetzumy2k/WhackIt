--!strict
-- Hit feedback: flash, floating damage numbers and camera shake for the hitter.
-- Purely local visuals driven by Combat.CombatFeedback. The boss's own hit and
-- defeat animations live in BossVisualController.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameplayController = require(script.Parent.GameplayController)
local SwingAnimator = require(script.Parent.Parent.Lib.SwingAnimator)

local FeedbackController = {}

local FLASH_SECONDS = 0.12
local DAMAGE_NUMBER_SECONDS = 0.7
local DAMAGE_NUMBER_RISE = 3
local SHAKE_SECONDS = 0.08
local SHAKE_STRENGTH = 0.6
local BURST_PARTICLES = 14
local BURST_SECONDS = 1
-- Other players' swings are shown from the start of the downswing: their hit is
-- only known once confirmed, so replaying the wind-up would land late.
local REMOTE_SWING_START = 0.42

local localPlayer = Players.LocalPlayer
local random = Random.new()

type Feedback = {
	BossInstanceId: string,
	Damage: number,
	HitterUserId: number,
	Defeated: boolean,
	Crit: boolean,
}

-- Server messages are still checked before use: a malformed payload must not
-- throw inside the event handler.
local function parse(payload: unknown): Feedback?
	if typeof(payload) ~= "table" then
		return nil
	end
	local data = payload :: { [string]: unknown }
	local id, damage, hitter, defeated =
		data.BossInstanceId, data.Damage, data.HitterUserId, data.Defeated
	if
		typeof(id) ~= "string"
		or typeof(damage) ~= "number"
		or typeof(hitter) ~= "number"
		or typeof(defeated) ~= "boolean"
	then
		return nil
	end
	return {
		BossInstanceId = id,
		Damage = damage,
		HitterUserId = hitter,
		Defeated = defeated,
		Crit = data.Crit == true,
	}
end

local function flash(model: Model): ()
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.3
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	Debris:AddItem(highlight, FLASH_SECONDS)
end

local function showDamageNumber(
	body: BasePart,
	damage: number,
	isOwnHit: boolean,
	isCrit: boolean,
	parent: Instance
): ()
	local billboard = Instance.new("BillboardGui")
	billboard.ResetOnSpawn = false
	billboard.Adornee = body
	billboard.AlwaysOnTop = true
	billboard.Size = if isCrit then UDim2.fromOffset(150, 60) else UDim2.fromOffset(80, 40)
	local startOffset = Vector3.new(random:NextNumber(-1.5, 1.5), body.Size.Y / 2, 0)
	billboard.StudsOffset = startOffset

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = if isCrit then "CRIT! -" .. damage else "-" .. damage
	-- Crits are big and orange; own hits stand out; teammates' hits are softer.
	label.TextColor3 = if isCrit
		then Color3.fromRGB(255, 140, 40)
		elseif isOwnHit then Color3.fromRGB(255, 230, 80)
		else Color3.fromRGB(230, 230, 230)
	label.TextStrokeTransparency = 0.4
	label.Parent = billboard
	billboard.Parent = parent

	local info =
		TweenInfo.new(DAMAGE_NUMBER_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService
		:Create(
			billboard,
			info,
			{ StudsOffset = startOffset + Vector3.new(0, DAMAGE_NUMBER_RISE, 0) }
		)
		:Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(billboard, DAMAGE_NUMBER_SECONDS)
end

-- A short burst of sparks where the hammer meets the boss (Roblox's default
-- particle texture, so no uploaded assets).
local function impactBurst(body: BasePart): ()
	local attachment = Instance.new("Attachment")
	attachment.Name = "ImpactBurst"
	attachment.Position = Vector3.new(0, body.Size.Y / 4, 0)
	attachment.Parent = body
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 240, 150))
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new(0.9, 0)
	emitter.Lifetime = NumberRange.new(0.3, 0.6)
	emitter.Speed = NumberRange.new(12, 20)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = attachment
	emitter:Emit(BURST_PARTICLES)
	Debris:AddItem(attachment, BURST_SECONDS)
end

local function shakeCamera(): ()
	local character = localPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid == nil then
		return
	end
	local offset = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(-1, 1), 0)
		* SHAKE_STRENGTH
	local info =
		TweenInfo.new(SHAKE_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true)
	TweenService:Create(humanoid, info, { CameraOffset = offset }):Play()
end

function FeedbackController.start(): ()
	local effects = Instance.new("Folder")
	effects.Name = "HitEffects"
	effects.Parent = localPlayer:WaitForChild("PlayerGui")

	local combatFeedback = ReplicatedStorage:WaitForChild("Remotes")
		:WaitForChild("Combat")
		:WaitForChild("CombatFeedback")
	assert(combatFeedback:IsA("RemoteEvent"), "CombatFeedback must be a RemoteEvent")

	combatFeedback.OnClientEvent:Connect(function(payload: unknown)
		local feedback = parse(payload)
		if feedback == nil then
			return
		end
		local model = GameplayController.findBoss(feedback.BossInstanceId)
		local body = if model then model.PrimaryPart else nil
		if model == nil or body == nil then
			return -- streamed out or already gone; nothing to show
		end

		local isOwnHit = feedback.HitterUserId == localPlayer.UserId
		-- Flash the drawn monster, not the boss Model: that also holds the
		-- invisible hitbox, which a Highlight would reveal as a white box.
		local visual = model:FindFirstChild("Visual")
		if visual and visual:IsA("Model") then
			flash(visual)
		end
		showDamageNumber(body, feedback.Damage, isOwnHit, feedback.Crit, effects)
		impactBurst(body)
		if isOwnHit then
			shakeCamera()
		else
			local hitter = Players:GetPlayerByUserId(feedback.HitterUserId)
			if hitter and hitter.Character then
				SwingAnimator.play(hitter.Character, REMOTE_SWING_START)
			end
		end
	end)
end

return FeedbackController
