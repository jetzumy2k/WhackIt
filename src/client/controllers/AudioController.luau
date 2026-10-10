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

local Responsive = require(script.Parent.Parent.Lib.Responsive)

local AudioController = {}

local LOAD_TIMEOUT_SECONDS = 10
local MIN_TOUCH_SIZE = 44

local muted = false
local current: Sound? = nil
local toggleButton: TextButton? = nil

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

	-- A small utility button beside the Menu button (top-left).
	local button =
		Responsive.iconButton(gui, "MusicToggle", "🎵", "Music", Color3.fromRGB(60, 150, 170))
	button.BackgroundTransparency = 0.2
	Responsive.onChanged(function()
		local phone = Responsive.formFactor() == "Phone"
		-- Right of the Menu button (54 wide on phones, 120 elsewhere).
		button.Position = UDim2.fromOffset(if phone then 16 + 54 + 8 else 16 + 120 + 8, 16)
		button.Size = if phone
			then UDim2.fromOffset(MIN_TOUCH_SIZE, 46)
			else UDim2.fromOffset(104, 48)
		Responsive.styleIconButton(button, phone, 18)
	end)

	toggleButton = button
	button.Activated:Connect(function()
		AudioController.setMuted(not muted)
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- Whether there is any music to play (MusicConfig.Tracks).
function AudioController.hasMusic(): boolean
	return #MusicConfig.Tracks > 0
end

function AudioController.isMuted(): boolean
	return muted
end

-- Turns the music off or on (the HUD button and the Player Panel share this).
function AudioController.setMuted(value: boolean): ()
	muted = value
	local button = toggleButton
	if button then
		local icon = button:FindFirstChild("Icon")
		if icon and icon:IsA("TextLabel") then
			icon.Text = if muted then "🔇" else "🎵"
		end
		Responsive.setButtonLabel(button, if muted then "Muted" else "Music")
	end
	local sound = current
	if sound then
		fadeTo(sound, targetVolume())
	end
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
