--!strict
--[[
	Studio-only performance probe, client half (docs/UPDATE_TEST_PLAN.md B4,
	polish round 2026-10-10). Does nothing in a live game.

	Every INTERVAL seconds each test client prints one line: frame rate,
	average and worst frame time, memory, network in/out, instances it can
	see in Workspace, where the player stands and the experiment mode.

	Experiment (lobby performance, 2026-10-10): a small "🧪 Perf" button
	cycles what this client draws, to find what costs frames:
	  Normal → NoEffects (Bloom, SunRays, Atmosphere, ColorCorrection off)
	  → NoLights (every PointLight/SpotLight/SurfaceLight off)
	  → NoShadows (Lighting.GlobalShadows off) → AllOff (all three).
	Only this client's view changes; switching starts a new measuring window.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

local PerfProbeController = {}

local INTERVAL = 10
local MODES = { "Normal", "NoEffects", "NoLights", "NoShadows", "AllOff" }

local mode = 1
local savedShadows = true
local changed: { [Instance]: boolean } = {}

local function isLight(instance: Instance): boolean
	return instance:IsA("PointLight") or instance:IsA("SpotLight") or instance:IsA("SurfaceLight")
end

-- Turns this client's effects and lights on or off for the current mode.
local function apply(): ()
	local name = MODES[mode]
	local effectsOff = name == "NoEffects" or name == "AllOff"
	local lightsOff = name == "NoLights" or name == "AllOff"
	local shadowsOff = name == "NoShadows" or name == "AllOff"
	-- Put back what an earlier mode switched off.
	for instance, wasEnabled in changed do
		if instance.Parent then
			(instance :: any).Enabled = wasEnabled
		end
	end
	table.clear(changed)
	local function switch(instance: Instance): ()
		local enabled = (instance :: any).Enabled
		if enabled then
			changed[instance] = true
			(instance :: any).Enabled = false
		end
	end
	if effectsOff then
		for _, child in Lighting:GetChildren() do
			if child:IsA("PostEffect") then
				switch(child)
			end
		end
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then
			-- Atmosphere has no Enabled: move it out and back.
			changed[atmosphere] = true
			atmosphere.Parent = nil
		end
	end
	if lightsOff then
		for _, descendant in Workspace:GetDescendants() do
			if isLight(descendant) then
				switch(descendant)
			end
		end
	end
	Lighting.GlobalShadows = if shadowsOff then false else savedShadows
end

local function restoreAtmosphere(): ()
	for instance in changed do
		if instance:IsA("Atmosphere") and instance.Parent == nil then
			instance.Parent = Lighting
			changed[instance] = nil
		end
	end
end

local function buildButton(onSwitch: () -> ()): ()
	local gui = Instance.new("ScreenGui")
	gui.Name = "PerfProbe"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.new(0.5, 0, 0, 4)
	button.Size = UDim2.fromOffset(190, 26)
	button.BackgroundColor3 = Color3.fromRGB(40, 44, 63)
	button.TextColor3 = Color3.fromRGB(240, 242, 248)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.Text = "🧪 Perf: " .. MODES[mode]
	button.Parent = gui
	Instance.new("UICorner").Parent = button
	button.Activated:Connect(function()
		restoreAtmosphere()
		mode = mode % #MODES + 1
		apply()
		button.Text = "🧪 Perf: " .. MODES[mode]
		onSwitch()
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function PerfProbeController.start(): ()
	if not RunService:IsStudio() then
		return
	end
	savedShadows = Lighting.GlobalShadows
	local frames, worst, started = 0, 0, os.clock()
	local function reset(): ()
		frames, worst, started = 0, 0, os.clock()
	end
	buildButton(reset)
	RunService.RenderStepped:Connect(function(dt: number)
		frames += 1
		worst = math.max(worst, dt)
	end)
	-- Lighting.Technology may not be readable from scripts.
	local readable, technology = pcall(function(): string
		return tostring(Lighting.Technology)
	end)
	local tech = if readable then technology else "?"
	while true do
		task.wait(INTERVAL)
		local elapsed = os.clock() - started
		local character = Players.LocalPlayer.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local at = if root and root:IsA("BasePart") then root.Position else Vector3.zero
		print(
			string.format(
				"[Perf] client mode=%s fps=%.1f avg=%.1fms worst=%.0fms mem=%.0fMB recv=%.1fkB/s send=%.1fkB/s instances=%d at=(%d,%d,%d) tech=%s",
				MODES[mode],
				frames / elapsed,
				elapsed / math.max(frames, 1) * 1000,
				worst * 1000,
				Stats:GetTotalMemoryUsageMb(),
				Stats.DataReceiveKbps,
				Stats.DataSendKbps,
				#Workspace:GetDescendants(),
				math.floor(at.X),
				math.floor(at.Y),
				math.floor(at.Z),
				tech
			)
		)
		reset()
	end
end

return PerfProbeController
