--!strict
--[[
	Draws and animates the cartoon monster for every boss (Shared/BossVisual).
	Local presentation only, driven by the server-written attributes on the boss
	Model: Health going down plays a hit reaction, Defeated plays the defeat.
	The server's hitbox (the boss body) never moves, so none of this affects
	hit detection, and nothing here is sent to the server.

	Per frame (Shared/BossMotion, personalities in Config/BossPersonalityConfig):
	  * idle bob, sway and a small side-to-side shuffle in the boss's style;
	  * faces you when you're within FaceStuds, otherwise looks around;
	  * an occasional personal fidget (taps, glances, flinches, head tilts,
	    yawns, puffing up);
	  * a surprised hop, a "ping" and a short line when you walk up to it;
	  * the lean-back hop on each hit plus a dizzy wobble, a "boing" (at most
	    every HitSoundCooldown, however many players hit) and, now and then on
	    your own hits, a short line ("Ouch!", "Okay, okay!");
	  * a spin-and-shrink on defeat.

	Each boss has at most two Sounds (hit, notice), created on first use under
	its body and reused, so they go away with the boss. Lines go into the boss's
	speech bubble for this player only (UIController.showBossLine) and never
	cover a server shout.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Attributes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attributes"))
local BossMotion = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BossMotion"))
local BossPersonalityConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BossPersonalityConfig"))
local BossVisual = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BossVisual"))
local BossVisualConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BossVisualConfig"))
local GameplayController = require(script.Parent.GameplayController)
local ProgressController = require(script.Parent.ProgressController)
local UIController = require(script.Parent.UIController)

local BossVisualController = {}

local TURN_SPEED = 6 -- higher = snappier turn toward the player
local LOOK_TURN_SPEED = 2 -- gentler turn while looking around
local HOME_YAW = math.pi -- facing +Z: office doors and the lobby are that way
local HIT_SECONDS = 0.35
local HIT_LEAN = math.rad(16)
local HIT_HOP = 0.6
local HIT_POP = 0.08
local DEFEAT_SECONDS = 0.8
local DEFEAT_SPINS = 2
local DEFEAT_PITCH = 0.7 -- the hit "boing", pitched down
local MIN_SCALE = 0.05
-- Locked bosses are drawn washed-out grey until the player unlocks them.
local LOCKED_GREY = Color3.fromRGB(150, 150, 155)
local LOCKED_TINT = 0.8

local PERSONALITY = BossPersonalityConfig

type Entry = {
	Body: BasePart,
	Visual: Model,
	Personality: BossPersonalityConfig.Personality,
	Phase: number, -- de-syncs idle motion between bosses
	Yaw: number,
	Scale: number, -- current animation scale (1 = normal)
	BaseScale: number, -- the boss's configured size (BossVisualConfig.Scale)
	LastHealth: number?,
	HitAt: number?,
	DefeatedAt: number?,
	BossId: string,
	Locked: boolean,
	OriginalColors: { [BasePart]: Color3 },
	-- Liveliness
	NextFidgetAt: number,
	FidgetAt: number?,
	SurpriseAt: number?,
	Near: boolean, -- the local player is within ApproachStuds
	LastNoticeAt: number,
	LastHitSoundAt: number,
	LastHitLineAt: number,
	Sounds: { [string]: Sound },
}

local localPlayer = Players.LocalPlayer
local entries: { [Model]: Entry } = {}
local random = Random.new()

local function lerpAngle(from: number, to: number, alpha: number): number
	local delta = (to - from + math.pi) % (2 * math.pi) - math.pi
	return from + delta * alpha
end

-- Yaw that turns the monster's front (-Z) toward `target`; keeps `current` if too close.
local function yawToward(origin: Vector3, target: Vector3, current: number): number
	local flat = Vector3.new(target.X - origin.X, 0, target.Z - origin.Z)
	if flat.Magnitude < 0.1 then
		return current
	end
	return math.atan2(-flat.X, -flat.Z)
end

local function pick(lines: { string }): string?
	if #lines == 0 then
		return nil
	end
	return lines[random:NextInteger(1, #lines)]
end

-- Greys out (or restores) the monster when its lock state changes.
local function refreshLock(entry: Entry): ()
	local locked = not ProgressController.isBossUnlocked(entry.BossId)
	if locked == entry.Locked then
		return
	end
	entry.Locked = locked
	for part, original in entry.OriginalColors do
		part.Color = if locked then original:Lerp(LOCKED_GREY, LOCKED_TINT) else original
	end
end

local function numberAttribute(model: Model, name: string): number?
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" then value else nil
end

local function cameraDistance(entry: Entry): number
	local camera = Workspace.CurrentCamera
	return if camera then (camera.CFrame.Position - entry.Body.Position).Magnitude else 0
end

-- Plays one of the boss's (at most two) reused sounds, if you're close enough.
local function playSound(entry: Entry, key: string, pitch: number): ()
	if cameraDistance(entry) > PERSONALITY.SoundMaxDistance then
		return
	end
	local sound: Sound? = entry.Sounds[key]
	if sound == nil then
		local created = Instance.new("Sound")
		created.Name = "Boss" .. key
		created.SoundId = (PERSONALITY.Sounds :: { [string]: string })[key] or ""
		created.Volume = PERSONALITY.SoundVolume
		created.RollOffMaxDistance = PERSONALITY.SoundMaxDistance
		created.RollOffMinDistance = 10
		created.Parent = entry.Body
		entry.Sounds[key] = created
		sound = created
	end
	local chosen = sound :: Sound
	chosen.PlaybackSpeed = pitch
	chosen.TimePosition = 0
	chosen:Play()
end

local function onHealthDrop(entry: Entry, now: number): ()
	entry.HitAt = now
	entry.FidgetAt = nil -- the hit reaction takes over
	if now - entry.LastHitSoundAt >= PERSONALITY.HitSoundCooldown then
		entry.LastHitSoundAt = now
		playSound(entry, "Hit", entry.Personality.Pitch * random:NextNumber(0.92, 1.08))
	end
end

local attach: (boss: Model) -> ()
function attach(boss: Model): ()
	if entries[boss] then
		return
	end
	local body = boss.PrimaryPart
	if body == nil then
		-- The model can replicate a moment before its parts; retry once they arrive.
		local connection: RBXScriptConnection
		connection = boss:GetPropertyChangedSignal("PrimaryPart"):Connect(function()
			if boss.PrimaryPart then
				connection:Disconnect()
				attach(boss)
			end
		end)
		return
	end

	local bossId = boss:GetAttribute(Attributes.BossId)
	if typeof(bossId) ~= "string" then
		return
	end
	-- Admin-created bosses borrow the look (and personality) of an office boss.
	local lookId = boss:GetAttribute(Attributes.BossLook)
	local styleId = if typeof(lookId) == "string" then lookId else bossId
	local look = BossVisualConfig[styleId]
	if look == nil then
		return
	end

	local visual = BossVisual.build(look)
	if look.Scale ~= 1 then
		visual:ScaleTo(look.Scale)
	end
	visual:PivotTo(body.CFrame)
	local originalColors: { [BasePart]: Color3 } = {}
	for _, descendant in visual:GetDescendants() do
		if descendant:IsA("BasePart") then
			originalColors[descendant] = descendant.Color
		end
	end
	visual.Parent = boss

	local now = os.clock()
	local entry: Entry = {
		Body = body,
		Visual = visual,
		Personality = PERSONALITY.ByBossId[styleId] or PERSONALITY.Default,
		Phase = random:NextNumber(0, math.pi * 2),
		Yaw = HOME_YAW,
		Scale = 1,
		BaseScale = look.Scale,
		LastHealth = numberAttribute(boss, Attributes.Health),
		HitAt = nil,
		DefeatedAt = if boss:GetAttribute(Attributes.Defeated) == true then now else nil,
		BossId = bossId,
		Locked = false,
		OriginalColors = originalColors,
		NextFidgetAt = now + random:NextNumber(PERSONALITY.FidgetMin, PERSONALITY.FidgetMax),
		FidgetAt = nil,
		SurpriseAt = nil,
		Near = false,
		LastNoticeAt = -math.huge,
		LastHitSoundAt = -math.huge,
		LastHitLineAt = -math.huge,
		Sounds = {},
	}
	entries[boss] = entry
	refreshLock(entry)

	boss:GetAttributeChangedSignal(Attributes.Health):Connect(function()
		local health = numberAttribute(boss, Attributes.Health)
		if health and entry.LastHealth and health < entry.LastHealth then
			onHealthDrop(entry, os.clock())
		end
		entry.LastHealth = health
	end)
	boss:GetAttributeChangedSignal(Attributes.Defeated):Connect(function()
		if boss:GetAttribute(Attributes.Defeated) == true and entry.DefeatedAt == nil then
			entry.DefeatedAt = os.clock()
			playSound(entry, "Hit", entry.Personality.Pitch * DEFEAT_PITCH)
		end
	end)
	boss.AncestryChanged:Connect(function(_, parent: Instance?)
		if parent == nil then
			entries[boss] = nil
		end
	end)
end

-- The boss notices you walking up: a hop, a "ping" and a short line.
local function notice(boss: Model, entry: Entry, now: number): ()
	entry.LastNoticeAt = now
	entry.SurpriseAt = now
	playSound(entry, "Notice", entry.Personality.Pitch)
	local line =
		pick(if entry.Locked then PERSONALITY.LockedLines else entry.Personality.ApproachLines)
	if line then
		UIController.showBossLine(boss, line)
	end
end

-- Tracks the local player's distance: notices on approach, and returns
-- whether the boss should face them (else it looks around).
local function watchPlayer(boss: Model, entry: Entry, now: number): Vector3?
	local character = localPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		entry.Near = false
		return nil
	end
	local origin = entry.Body.Position
	local offset = root.Position - origin
	local sameFloor = math.abs(offset.Y) <= PERSONALITY.SameFloorStuds + entry.Body.Size.Y / 2
	local flat = Vector2.new(offset.X, offset.Z).Magnitude
	if not sameFloor or flat > PERSONALITY.LeaveStuds then
		entry.Near = false
	elseif flat <= PERSONALITY.ApproachStuds and not entry.Near then
		entry.Near = true
		if entry.DefeatedAt == nil and now - entry.LastNoticeAt >= PERSONALITY.ApproachCooldown then
			notice(boss, entry, now)
		end
	end
	if sameFloor and flat <= PERSONALITY.FaceStuds then
		return root.Position
	end
	return nil
end

local function animate(boss: Model, entry: Entry, now: number, dt: number): ()
	local origin = entry.Body.Position
	local personality = entry.Personality

	if entry.DefeatedAt == nil then
		local target = watchPlayer(boss, entry, now)
		if target then
			entry.Yaw = lerpAngle(
				entry.Yaw,
				yawToward(origin, target, entry.Yaw),
				math.min(1, dt * TURN_SPEED)
			)
		else
			local look = BossMotion.lookAround(personality, HOME_YAW, now, entry.Phase)
			entry.Yaw = lerpAngle(entry.Yaw, look, math.min(1, dt * LOOK_TURN_SPEED))
		end
	end

	local motion = BossMotion.idle(personality, now, entry.Phase)

	-- Fidget now and then, unless reacting to something else.
	if entry.FidgetAt == nil and entry.HitAt == nil and now >= entry.NextFidgetAt then
		entry.FidgetAt = now
		entry.NextFidgetAt = now
			+ PERSONALITY.FidgetSeconds
			+ random:NextNumber(PERSONALITY.FidgetMin, PERSONALITY.FidgetMax)
	end
	local fidgetAt = entry.FidgetAt
	if fidgetAt then
		local progress = (now - fidgetAt) / PERSONALITY.FidgetSeconds
		if progress >= 1 then
			entry.FidgetAt = nil
		else
			motion = BossMotion.add(motion, BossMotion.fidget(personality.Fidget, progress))
		end
	end
	local surpriseAt = entry.SurpriseAt
	if surpriseAt then
		local progress = (now - surpriseAt) / BossMotion.SURPRISE_SECONDS
		if progress >= 1 then
			entry.SurpriseAt = nil
		else
			motion = BossMotion.add(motion, BossMotion.surprise(progress))
		end
	end

	local lean, hop, scale, spin = motion.Lean, 0, motion.Scale, 0
	local hitAt = entry.HitAt
	if hitAt then
		local elapsed = now - hitAt
		local progress = elapsed / HIT_SECONDS
		if progress < 1 then
			local bump = math.sin(progress * math.pi)
			lean += bump * HIT_LEAN -- top tips backwards, away from the hammer
			hop = bump * HIT_HOP
			scale *= 1 + bump * HIT_POP
		end
		local wobble = elapsed / (HIT_SECONDS + BossMotion.WOBBLE_SECONDS)
		if wobble < 1 then
			motion.Yaw += BossMotion.wobble(wobble)
		else
			entry.HitAt = nil
		end
	end
	if entry.DefeatedAt then
		local progress = math.clamp((now - entry.DefeatedAt) / DEFEAT_SECONDS, 0, 1)
		spin = progress * DEFEAT_SPINS * 2 * math.pi
		scale = math.max(MIN_SCALE, 1 - progress)
	end

	entry.Visual:PivotTo(
		CFrame.new(origin + Vector3.new(0, motion.Lift + hop, 0))
			* CFrame.Angles(0, entry.Yaw + motion.Yaw + spin, 0)
			* CFrame.new(motion.Shuffle, 0, 0)
			* CFrame.Angles(lean, 0, motion.Roll)
	)
	if math.abs(scale - entry.Scale) > 0.001 then
		entry.Visual:ScaleTo(scale * entry.BaseScale)
		entry.Scale = scale
	end
end

-- A confirmed hit (FeedbackController): your own hits sometimes get a line.
function BossVisualController.onConfirmedHit(boss: Model, isOwnHit: boolean, defeated: boolean): ()
	local entry = entries[boss]
	if entry == nil or not isOwnHit or defeated then
		return
	end
	local now = os.clock()
	if
		now - entry.LastHitLineAt >= PERSONALITY.HitLineCooldown
		and random:NextNumber() < PERSONALITY.HitLineChance
	then
		entry.LastHitLineAt = now
		local line = pick(entry.Personality.HitLines)
		if line then
			UIController.showBossLine(boss, line)
		end
	end
end

function BossVisualController.start(): ()
	local bossesFolder = GameplayController.waitForBossesFolder()
	bossesFolder.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Model") then
			attach(child)
		end
	end)
	for _, child in bossesFolder:GetChildren() do
		if child:IsA("Model") then
			attach(child)
		end
	end

	ProgressController.Changed:Connect(function()
		for _, entry in entries do
			refreshLock(entry)
		end
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		local now = os.clock()
		for boss, entry in entries do
			-- Streamed out or destroyed: stop animating it.
			if entry.Body.Parent == nil then
				entries[boss] = nil
				continue
			end
			animate(boss, entry, now, dt)
		end
	end)
end

return BossVisualController
