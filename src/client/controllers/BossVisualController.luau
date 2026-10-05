--!strict
--[[
	Draws and animates the cartoon monster for every boss (Shared/BossVisual).
	Local presentation only, driven by the server-written attributes on the boss
	Model: Health going down plays a hit reaction, Defeated plays the defeat.

	Animation per frame: idle bob and sway, turn to face the local player, a
	lean-back hop on each hit, and a spin-and-shrink on defeat.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Attributes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attributes"))
local BossVisual = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BossVisual"))
local BossVisualConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BossVisualConfig"))
local GameplayController = require(script.Parent.GameplayController)

local BossVisualController = {}

local BOB_HEIGHT = 0.2
local BOB_SPEED = 2.2
local SWAY_ANGLE = math.rad(4)
local SWAY_SPEED = 1.3
local TURN_SPEED = 6 -- higher = snappier turn toward the player
local HIT_SECONDS = 0.35
local HIT_LEAN = math.rad(16)
local HIT_HOP = 0.6
local HIT_POP = 0.08
local DEFEAT_SECONDS = 0.8
local DEFEAT_SPINS = 2
local MIN_SCALE = 0.05

type Entry = {
	Body: BasePart,
	Visual: Model,
	Phase: number, -- de-syncs idle motion between bosses
	Yaw: number,
	Scale: number,
	LastHealth: number?,
	HitAt: number?,
	DefeatedAt: number?,
}

local localPlayer = Players.LocalPlayer
local entries: { [Model]: Entry } = {}

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

local function numberAttribute(model: Model, name: string): number?
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" then value else nil
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
	local look = if typeof(bossId) == "string" then BossVisualConfig[bossId] else nil
	if look == nil then
		return
	end

	local visual = BossVisual.build(look)
	visual:PivotTo(body.CFrame)
	visual.Parent = boss

	local entry: Entry = {
		Body = body,
		Visual = visual,
		Phase = math.random() * math.pi * 2,
		Yaw = 0,
		Scale = 1,
		LastHealth = numberAttribute(boss, Attributes.Health),
		HitAt = nil,
		DefeatedAt = if boss:GetAttribute(Attributes.Defeated) == true then os.clock() else nil,
	}
	entries[boss] = entry

	boss:GetAttributeChangedSignal(Attributes.Health):Connect(function()
		local health = numberAttribute(boss, Attributes.Health)
		if health and entry.LastHealth and health < entry.LastHealth then
			entry.HitAt = os.clock()
		end
		entry.LastHealth = health
	end)
	boss:GetAttributeChangedSignal(Attributes.Defeated):Connect(function()
		if boss:GetAttribute(Attributes.Defeated) == true and entry.DefeatedAt == nil then
			entry.DefeatedAt = os.clock()
		end
	end)
	boss.AncestryChanged:Connect(function(_, parent: Instance?)
		if parent == nil then
			entries[boss] = nil
		end
	end)
end

local function animate(entry: Entry, now: number, dt: number): ()
	local origin = entry.Body.Position

	local character = localPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") and entry.DefeatedAt == nil then
		local targetYaw = yawToward(origin, root.Position, entry.Yaw)
		entry.Yaw = lerpAngle(entry.Yaw, targetYaw, math.min(1, dt * TURN_SPEED))
	end

	local bob = math.sin(now * BOB_SPEED + entry.Phase) * BOB_HEIGHT
	local sway = math.sin(now * SWAY_SPEED + entry.Phase) * SWAY_ANGLE

	local lean, hop, scale, spin = 0, 0, 1, 0
	if entry.HitAt then
		local progress = (now - entry.HitAt) / HIT_SECONDS
		if progress < 1 then
			local pulse = math.sin(progress * math.pi)
			lean = pulse * HIT_LEAN -- top tips backwards, away from the hammer
			hop = pulse * HIT_HOP
			scale = 1 + pulse * HIT_POP
		end
	end
	if entry.DefeatedAt then
		local progress = math.clamp((now - entry.DefeatedAt) / DEFEAT_SECONDS, 0, 1)
		spin = progress * DEFEAT_SPINS * 2 * math.pi
		scale = math.max(MIN_SCALE, 1 - progress)
	end

	entry.Visual:PivotTo(
		CFrame.new(origin + Vector3.new(0, bob + hop, 0))
			* CFrame.Angles(0, entry.Yaw + sway + spin, 0)
			* CFrame.Angles(lean, 0, 0)
	)
	if math.abs(scale - entry.Scale) > 0.001 then
		entry.Visual:ScaleTo(scale)
		entry.Scale = scale
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

	RunService.RenderStepped:Connect(function(dt: number)
		local now = os.clock()
		for boss, entry in entries do
			-- Streamed out or destroyed: stop animating it.
			if entry.Body.Parent == nil then
				entries[boss] = nil
				continue
			end
			animate(entry, now, dt)
		end
	end)
end

return BossVisualController
