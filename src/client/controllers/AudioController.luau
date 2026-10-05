--!strict
--[[
	Background music: plays MusicConfig.Tracks in a loop (shuffled start),
	fading between tracks, with a Music On/Off button in the HUD. Local to each
	player. With no tracks configured it does nothing and shows no button.
	A track that fails to load is skipped.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local MusicConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("MusicConfig"))

local AudioController = {}

local LOAD_TIMEOUT_SECONDS = 10
local MIN_TOUCH_SIZE = 44

local muted = false
local current: Sound? = nil

local function fadeTo(sound: Sound, volume: number): Tween
	local tween =
		TweenService:Create(sound, TweenInfo.new(MusicConfig.FadeSeconds), { Volume = volume })
	tween:Play()
	return tween
end

local function targetVolume(): number
	return if muted then 0 else MusicConfig.Volume
end

-- Plays one track to the end (or until it fails to load).
local function playTrack(track: MusicConfig.Track): ()
	local sound = Instance.new("Sound")
	sound.Name = "Music"
	sound.SoundId = track.Id
	sound.Volume = 0
	sound.Parent = SoundService

	local loaded = sound.IsLoaded
	if not loaded then
		local started = os.clock()
		repeat
			task.wait(0.25)
		until sound.IsLoaded or os.clock() - started > LOAD_TIMEOUT_SECONDS
		loaded = sound.IsLoaded
	end
	if not loaded then
		warn(string.format("[Audio] could not load %q (%s); skipping", track.Name, track.Id))
		sound:Destroy()
		return
	end

	current = sound
	sound:Play()
	fadeTo(sound, targetVolume())
	sound.Ended:Wait()
	current = nil
	sound:Destroy()
end

local function buildToggle(): ()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Music"
	gui.ResetOnSpawn = false

	local button = Instance.new("TextButton")
	button.Name = "MusicToggle"
	button.AnchorPoint = Vector2.new(0, 0)
	button.Position = UDim2.fromOffset(16, 16)
	button.Size = UDim2.fromOffset(120, MIN_TOUCH_SIZE)
	button.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	button.BackgroundTransparency = 0.2
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.FredokaOne
	button.TextScaled = true
	button.Text = "Music: On"
	button.Parent = gui
	Instance.new("UICorner").Parent = button

	button.Activated:Connect(function()
		muted = not muted
		button.Text = if muted then "Music: Off" else "Music: On"
		local sound = current
		if sound then
			fadeTo(sound, targetVolume())
		end
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function AudioController.start(): ()
	local tracks = MusicConfig.Tracks
	if #tracks == 0 then
		return
	end
	buildToggle()

	local index = math.random(1, #tracks)
	while true do
		playTrack(tracks[index])
		index = index % #tracks + 1
	end
end

return AudioController
