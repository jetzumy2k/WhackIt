--!strict
--[[
	Shows each player's state on their character, visible to everyone:
	  * the face (Lib/MoodFace) follows the mood band of their stress;
	  * the held hammer glows (light + sparkles) while they're in Zen (0 stress),
	    in the Zen glow colour they picked (GlowStyle attribute, level reward);
	  * a "Lv N · Title" tag floats above their head (Player Level and its
	    title, Shared/LevelRewardRules); gold at the max level.
	Driven by the Player's "Stress" attribute (StressService), so it reacts to
	hits, defeats, Zen and stress creeping back alike.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Attributes = require(ReplicatedStorage.Shared.Attributes)
local LevelRewardConfig = require(ReplicatedStorage.Config.LevelRewardConfig)
local LevelRewardRules = require(ReplicatedStorage.Shared.LevelRewardRules)
local LevelRules = require(ReplicatedStorage.Shared.LevelRules)
local MoodFace = require(ServerScriptService.Lib.MoodFace)
local StressRules = require(ReplicatedStorage.Shared.StressRules)

local MoodService = {}

local GLOW_NAME = "ZenGlow"
local LEVEL_TAG_NAME = "LevelTag"
local TAG_COLOR = Color3.fromRGB(255, 230, 120)
-- Soft on purpose: a warm halo and a few slow sparkles, not glitter spam.
local GLOW_BRIGHTNESS = 0.9
local GLOW_RANGE = 6
local SPARKLE_RATE = 3 -- per second

local watched: { [Player]: boolean } = {}

local function currentMood(player: Player): StressRules.Mood?
	local stress = player:GetAttribute(Attributes.Stress)
	return if typeof(stress) == "number" then StressRules.moodFor(stress) else nil
end

local function glowColor(player: Player): Color3
	local id = player:GetAttribute(Attributes.GlowStyle)
	local glow = if typeof(id) == "string" and id ~= ""
		then LevelRewardRules.cosmetic("Glow", id)
		else nil
	return if glow then glow.Color else LevelRewardConfig.DefaultGlowColor
end

-- Light + sparkles on the hammer head, switched on only in Zen. Created once
-- per hammer (they go away with the Tool on respawn or leaving); the colour
-- follows the player's pick.
local function setGlow(tool: Tool, on: boolean, color: Color3): ()
	local head = tool:FindFirstChild("Head")
	if head == nil or not head:IsA("BasePart") then
		return
	end
	local light = head:FindFirstChild(GLOW_NAME)
	if light == nil then
		local created = Instance.new("PointLight")
		created.Name = GLOW_NAME
		created.Brightness = GLOW_BRIGHTNESS
		created.Range = GLOW_RANGE
		created.Shadows = false
		created.Parent = head
		light = created
	end
	local sparkles = head:FindFirstChild(GLOW_NAME .. "Sparkles")
	if sparkles == nil then
		local created = Instance.new("ParticleEmitter")
		created.Name = GLOW_NAME .. "Sparkles"
		created.Rate = SPARKLE_RATE
		created.Lifetime = NumberRange.new(0.6, 1)
		created.Size = NumberSequence.new(0.18, 0)
		created.Speed = NumberRange.new(0.3, 0.8)
		created.SpreadAngle = Vector2.new(180, 180)
		created.Acceleration = Vector3.new(0, 1, 0)
		created.Transparency = NumberSequence.new(0.2, 1)
		created.LightEmission = 0.3
		created.LightInfluence = 0
		created.Enabled = false
		created.Parent = head
		sparkles = created
	end
	if light and light:IsA("PointLight") then
		light.Color = color
		light.Enabled = on
	end
	if sparkles and sparkles:IsA("ParticleEmitter") then
		sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 250, 220), color)
		sparkles.Enabled = on
	end
end

-- "Lv N · Title" above the head; created once per character, text updated
-- in place. Gold with a crown at the max level.
local function setLevelTag(head: BasePart, level: number): ()
	local tag = head:FindFirstChild(LEVEL_TAG_NAME)
	if tag == nil then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = LEVEL_TAG_NAME
		billboard.Size = UDim2.fromOffset(200, 26)
		billboard.StudsOffset = Vector3.new(0, 2.6, 0)
		billboard.MaxDistance = 80
		billboard.AlwaysOnTop = false
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextStrokeTransparency = 0.3
		label.Parent = billboard
		billboard.Parent = head
		tag = billboard
	end
	local label = if tag then tag:FindFirstChild("Text") else nil
	if label and label:IsA("TextLabel") then
		local max = LevelRules.isMax(level)
		label.Text = string.format(
			"%sLv %d · %s",
			if max then "👑 " else "",
			level,
			LevelRewardRules.titleFor(level)
		)
		label.TextColor3 = if max then LevelRewardConfig.MaxLevelColor else TAG_COLOR
	end
end

local function refresh(player: Player): ()
	local maybeMood = currentMood(player)
	local character = player.Character
	if maybeMood == nil or character == nil then
		return
	end
	local mood: string = maybeMood

	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		MoodFace.apply(head, mood)
		local level = player:GetAttribute(Attributes.Level)
		if typeof(level) == "number" then
			setLevelTag(head, level)
		end
	end
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute(Attributes.HammerId) ~= nil then
			setGlow(child, mood == "Zen", glowColor(player))
		end
	end
end

local function watchCharacter(player: Player, character: Model): ()
	-- Head and hammer arrive a moment after the character; refresh as they do.
	character.ChildAdded:Connect(function(child: Instance)
		if child.Name == "Head" or child:IsA("Tool") then
			refresh(player)
		end
	end)
	refresh(player)
end

local function watch(player: Player): ()
	if watched[player] then
		return
	end
	watched[player] = true
	player:GetAttributeChangedSignal(Attributes.Stress):Connect(function()
		refresh(player)
	end)
	player:GetAttributeChangedSignal(Attributes.Level):Connect(function()
		refresh(player)
	end)
	player:GetAttributeChangedSignal(Attributes.GlowStyle):Connect(function()
		refresh(player)
	end)
	player.CharacterAdded:Connect(function(character: Model)
		watchCharacter(player, character)
	end)
	if player.Character then
		watchCharacter(player, player.Character)
	end
end

function MoodService.init(): ()
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player: Player)
		watched[player] = nil
	end)
end

function MoodService.start(): ()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return MoodService
