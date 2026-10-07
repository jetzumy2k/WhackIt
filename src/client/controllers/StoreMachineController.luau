--!strict
--[[
	The hammer vending machine on this client (built by the server's
	Lib/StoreMachineBuilder):
	  * its "Open Hammer Store" prompt opens the existing Hammers shop
	    (ShopController.open), with a soft click and a short "press" on the
	    screen. Buying still goes through the shop's Buy buttons and the
	    server's checks; this only opens the panel;
	  * a gentle idle: the display hammers sway a little and the neon strips
	    pulse softly. Each is one TweenService tween set to repeat, started once;
	    no per-frame script work.
]]

local ProximityPromptService = game:GetService("ProximityPromptService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ShopController = require(script.Parent.ShopController)

local StoreMachineController = {}

-- Names and attributes set by Lib/StoreMachineBuilder (server-only module).
local MODEL_NAME = "HammerVendingMachine"
local PROMPT_ATTRIBUTE = "StoreMachine"
local DISPLAY_ATTRIBUTE = "StoreDisplay"
local GLOW_ATTRIBUTE = "StoreGlow"

local CLICK_SOUND_ID = "rbxasset://sounds/clickfast.wav"
local CLICK_VOLUME = 0.35
local SWAY_DEGREES = 12
local SWAY_SECONDS = 2.4
local BOB_STUDS = 0.08
local PULSE_SECONDS = 1.8
local THANKS_SECONDS = 1.5

local clickSound: Sound? = nil

local function playClick(): ()
	local sound = clickSound
	if sound == nil then
		local created = Instance.new("Sound")
		created.Name = "VendingClick"
		created.SoundId = CLICK_SOUND_ID
		created.Volume = CLICK_VOLUME
		created.Parent = SoundService
		clickSound = created
		sound = created
	end
	(sound :: Sound):Play()
end

-- Starts the machine's idle tweens (once per machine instance).
local function startIdle(machine: Model): ()
	local index = 0
	for _, child in machine:GetChildren() do
		if child:IsA("Model") and child:GetAttribute(DISPLAY_ATTRIBUTE) == true then
			local root = child.PrimaryPart
			if root and root.Anchored then
				index += 1
				local base = root.CFrame
				-- Start each hammer at a different point of its sway.
				root.CFrame = base * CFrame.Angles(0, math.rad(-SWAY_DEGREES), 0)
				local info = TweenInfo.new(
					SWAY_SECONDS + index * 0.3,
					Enum.EasingStyle.Sine,
					Enum.EasingDirection.InOut,
					-1,
					true
				)
				TweenService:Create(root, info, {
					CFrame = base
						* CFrame.new(0, BOB_STUDS, 0)
						* CFrame.Angles(0, math.rad(SWAY_DEGREES), 0),
				}):Play()
			end
		end
	end
	for _, descendant in machine:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute(GLOW_ATTRIBUTE) == true then
			local info = TweenInfo.new(
				PULSE_SECONDS,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut,
				-1,
				true
			)
			TweenService:Create(descendant, info, { Transparency = 0.6 }):Play()
		end
	end
end

-- Briefly thanks the player on the machine's screen.
local function flashScreen(machine: Model): ()
	local screen = machine:FindFirstChild("Screen")
	local gui = if screen then screen:FindFirstChildOfClass("SurfaceGui") else nil
	local label = if gui then gui:FindFirstChild("Text") else nil
	if label == nil or not label:IsA("TextLabel") then
		return
	end
	local original = label:GetAttribute("Original")
	if typeof(original) ~= "string" then
		original = label.Text
		label:SetAttribute("Original", original)
	end
	label.Text = "HAPPY\nWHACKING!"
	task.delay(THANKS_SECONDS, function()
		label.Text = original :: string
	end)
end

function StoreMachineController.start(): ()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt:GetAttribute(PROMPT_ATTRIBUTE) ~= true then
			return
		end
		ShopController.open()
		playClick()
		local machine = prompt:FindFirstAncestorOfClass("Model")
		if machine then
			flashScreen(machine)
		end
	end)

	-- The machine is persistent (always streamed in), so wait for it once.
	local machine = Workspace:WaitForChild(MODEL_NAME, 60)
	if machine and machine:IsA("Model") then
		startIdle(machine)
	end
end

return StoreMachineController
