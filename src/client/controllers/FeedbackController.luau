--!strict
-- Hit feedback: a soft flash, sparkles and impact ring (Lib/HitEffects, pooled
-- per boss), floating damage numbers, camera shake and a "bonk" for the hitter,
-- and a brief happy face on whoever landed the hit (Lib/CharacterExpression).
-- Purely local visuals driven by Combat.CombatFeedback. The boss's own hit and
-- defeat animations live in BossVisualController.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local GameplayController = require(script.Parent.GameplayController)
local BossVisualController = require(script.Parent.BossVisualController)
local CharacterExpression = require(script.Parent.Parent.Lib.CharacterExpression)
local HitEffects = require(script.Parent.Parent.Lib.HitEffects)
local SwingAnimator = require(script.Parent.Parent.Lib.SwingAnimator)

local FeedbackController = {}

local DAMAGE_NUMBER_SECONDS = 0.7
local DAMAGE_NUMBER_RISE = 3
local DAMAGE_NUMBER_MAX_DISTANCE = 60 -- studs; matches the boss HP label
local SHAKE_SECONDS = 0.08
local SHAKE_STRENGTH = 0.6
-- Other players' swings are shown from the start of the downswing: their hit is
-- only known once confirmed, so replaying the wind-up would land late.
local REMOTE_SWING_START = 0.42
-- A short cartoon "bonk" on your own confirmed hits (built-in sound, no asset).
local BONK_SOUND_ID = "rbxasset://sounds/action_jump_land.mp3"
local BONK_VOLUME = 0.55
local BONK_PITCH = 1.35
local BONK_CRIT_PITCH = 1.6
-- How long the hitter beams after a landed hit, and after the defeating one.
local HAPPY_SECONDS = 0.7
local HAPPY_DEFEAT_SECONDS = 1.5

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
	-- Not AlwaysOnTop, so hits in other offices or floors don't show through
	-- walls; it starts a little above the boss so its own model can't hide it.
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.MaxDistance = DAMAGE_NUMBER_MAX_DISTANCE
	billboard.Size = if isCrit then UDim2.fromOffset(150, 60) else UDim2.fromOffset(80, 40)
	local startOffset = Vector3.new(random:NextNumber(-1.5, 1.5), body.Size.Y / 2 + 1, 0)
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

-- One local Sound, reused: a new hit restarts it, so hits never pile up sounds.
local bonkSound: Sound? = nil
local function playBonk(crit: boolean): ()
	local sound = bonkSound
	if sound == nil then
		local created = Instance.new("Sound")
		created.Name = "HammerBonk"
		created.SoundId = BONK_SOUND_ID
		created.Volume = BONK_VOLUME
		created.Parent = SoundService
		bonkSound = created
		sound = created
	end
	local bonk = sound :: Sound
	bonk.PlaybackSpeed = if crit then BONK_CRIT_PITCH else BONK_PITCH
	bonk.TimePosition = 0
	bonk:Play()
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
		HitEffects.play(body, if visual and visual:IsA("Model") then visual else nil, {
			Own = isOwnHit,
			Crit = feedback.Crit,
			Defeated = feedback.Defeated,
		})
		showDamageNumber(body, feedback.Damage, isOwnHit, feedback.Crit, effects)
		BossVisualController.onConfirmedHit(model, isOwnHit, feedback.Defeated)
		local hitter = Players:GetPlayerByUserId(feedback.HitterUserId)
		if isOwnHit then
			shakeCamera()
			playBonk(feedback.Crit)
		elseif hitter and hitter.Character then
			SwingAnimator.play(hitter.Character, REMOTE_SWING_START)
		end
		if hitter and hitter.Character then
			CharacterExpression.show(
				hitter.Character,
				"Happy",
				if feedback.Defeated then HAPPY_DEFEAT_SECONDS else HAPPY_SECONDS
			)
		end
	end)
end

return FeedbackController
