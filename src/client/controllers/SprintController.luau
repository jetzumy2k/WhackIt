--!strict
--[[
	Sprint: run faster to get to a boss.
	  * Keyboard: hold Shift.
	  * Gamepad: press the left stick (L3) to toggle.
	  * Touch: a "Sprint" button toggles it.
	A toggle switches off once the character has run and then stops, so it
	never stays on by accident.

	Movement speed is client-applied (the client simulates its own character).
	It only affects how fast you walk, never damage or rewards, and the server's
	MovementGuard ignores hits from anyone moving faster than its limit.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Attributes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attributes"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local PickleballConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("PickleballConfig"))

local Responsive = require(script.Parent.Parent.Lib.Responsive)
local UiTokens = require(script.Parent.Parent.Lib.UiTokens)

local SprintController = {}

local HOLD_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.LeftShift] = true,
	[Enum.KeyCode.RightShift] = true,
}
local TOGGLE_KEY = Enum.KeyCode.ButtonL3
local BUTTON_ON = Color3.fromRGB(80, 190, 90)
local BUTTON_OFF = Color3.fromRGB(70, 70, 90)
local MIN_TOUCH_SIZE = 44
local STOP_GRACE_SECONDS = 0.6
local FOV_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local localPlayer = Players.LocalPlayer
local held = 0 -- Shift keys currently down
local toggled = false -- gamepad / touch toggle
local movedSinceToggle = false
local stillSince: number? = nil
local sprinting = false
local defaultFieldOfView = 70
local touchButton: TextButton? = nil

local function humanoid(): Humanoid?
	local character = localPlayer.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

-- During a pickleball match everyone walks at the same fixed speed.
local function inMatch(): boolean
	local match = localPlayer:GetAttribute(Attributes.RecMatch)
	return typeof(match) == "string" and match ~= ""
end

local function apply(): ()
	local playing = inMatch()
	local wantSprint = (held > 0 or toggled) and not playing
	local currentHumanoid = humanoid()
	if currentHumanoid then
		currentHumanoid.WalkSpeed = if playing
			then PickleballConfig.Game.WalkSpeed
			elseif wantSprint then GameConfig.SprintSpeed
			else GameConfig.WalkSpeed
	end
	if touchButton then
		touchButton.BackgroundColor3 = if wantSprint then BUTTON_ON else BUTTON_OFF
	end
	if wantSprint == sprinting then
		return
	end
	sprinting = wantSprint
	local camera = Workspace.CurrentCamera
	if camera then
		-- Reduced motion: no zoom-out while sprinting (docs/UI.md).
		local zoom = wantSprint and not UiTokens.reducedMotion()
		TweenService:Create(camera, FOV_TWEEN, {
			FieldOfView = if zoom then GameConfig.SprintFieldOfView else defaultFieldOfView,
		}):Play()
	end
end

local function setToggle(on: boolean): ()
	toggled = on
	movedSinceToggle = false
	stillSince = nil
	apply()
end

local function buildTouchButton(): ()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Sprint"
	gui.ResetOnSpawn = false
	local clickable = Instance.new("TextButton")
	clickable.Name = "SprintButton"
	clickable.Text = "Sprint"
	clickable.TextColor3 = Color3.new(1, 1, 1)
	clickable.Font = Enum.Font.FredokaOne
	clickable.BackgroundColor3 = BUTTON_OFF
	-- Just left of Roblox's jump button, where the right thumb already is
	-- (the HUD button column sits top-right on touch screens, Lib/Responsive).
	clickable.AnchorPoint = Vector2.new(1, 1)
	Responsive.onChanged(function()
		if Responsive.formFactor() == "Phone" then
			clickable.Position = UDim2.new(1, -104, 1, -24)
			clickable.Size = UDim2.fromOffset(88, MIN_TOUCH_SIZE)
		else
			clickable.Position = UDim2.new(1, -170, 1, -100)
			clickable.Size = UDim2.fromOffset(96, MIN_TOUCH_SIZE + 4)
		end
	end)
	Responsive.capText(clickable, 20)
	clickable.Parent = gui
	Instance.new("UICorner").Parent = clickable
	clickable.Activated:Connect(function()
		setToggle(not toggled)
	end)
	touchButton = clickable
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

function SprintController.start(): ()
	local camera = Workspace.CurrentCamera
	if camera then
		defaultFieldOfView = camera.FieldOfView
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return -- typing in chat or a text box
		end
		if HOLD_KEYS[input.KeyCode] then
			held += 1
			apply()
		elseif input.KeyCode == TOGGLE_KEY then
			setToggle(not toggled)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if HOLD_KEYS[input.KeyCode] then
			held = math.max(0, held - 1)
			apply()
		end
	end)
	-- Losing focus (alt-tab) never delivers the key-up, so forget held keys.
	UserInputService.WindowFocusReleased:Connect(function()
		held = 0
		apply()
	end)

	-- A toggle switches off once the character has run and then stood still
	-- for a moment (not straight after the tap, before they start moving).
	RunService.Heartbeat:Connect(function()
		if not toggled then
			return
		end
		local currentHumanoid = humanoid()
		local moving = currentHumanoid ~= nil and currentHumanoid.MoveDirection.Magnitude >= 0.1
		if moving then
			movedSinceToggle = true
			stillSince = nil
		elseif movedSinceToggle then
			local now = os.clock()
			stillSince = stillSince or now
			if now - (stillSince :: number) >= STOP_GRACE_SECONDS then
				setToggle(false)
			end
		end
	end)

	-- A pickleball match starting or ending switches the walk speed.
	localPlayer:GetAttributeChangedSignal(Attributes.RecMatch):Connect(function()
		toggled = false
		apply()
	end)
	localPlayer.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("Humanoid", 10)
		toggled = false
		apply()
	end)

	if UserInputService.TouchEnabled then
		buildTouchButton()
	end
	apply()
end

return SprintController
