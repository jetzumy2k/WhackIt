--!strict
--[[
	Shows each player's stress on their character, visible to everyone:
	  * the face (Lib/MoodFace) follows the mood band of their stress;
	  * the held hammer glows (light + sparkles) while they're in Zen (0 stress).
	Driven by the Player's "Stress" attribute (StressService), so it reacts to
	hits, defeats, Zen and stress creeping back alike.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Attributes = require(ReplicatedStorage.Shared.Attributes)
local MoodFace = require(ServerScriptService.Lib.MoodFace)
local StressRules = require(ReplicatedStorage.Shared.StressRules)

local MoodService = {}

local GLOW_NAME = "ZenGlow"
local GLOW_COLOR = Color3.fromRGB(255, 225, 120)

local watched: { [Player]: boolean } = {}

local function currentMood(player: Player): StressRules.Mood?
	local stress = player:GetAttribute(Attributes.Stress)
	return if typeof(stress) == "number" then StressRules.moodFor(stress) else nil
end

-- Light + sparkles on the hammer head, switched on only in Zen.
local function setGlow(tool: Tool, on: boolean): ()
	local head = tool:FindFirstChild("Head")
	if head == nil or not head:IsA("BasePart") then
		return
	end
	local light = head:FindFirstChild(GLOW_NAME)
	if light == nil then
		local created = Instance.new("PointLight")
		created.Name = GLOW_NAME
		created.Color = GLOW_COLOR
		created.Brightness = 3
		created.Range = 10
		created.Parent = head
		light = created
	end
	local sparkles = head:FindFirstChild(GLOW_NAME .. "Sparkles")
	if sparkles == nil then
		local created = Instance.new("Sparkles")
		created.Name = GLOW_NAME .. "Sparkles"
		created.SparkleColor = GLOW_COLOR
		created.Parent = head
		sparkles = created
	end
	if light and light:IsA("PointLight") then
		light.Enabled = on
	end
	if sparkles and sparkles:IsA("Sparkles") then
		sparkles.Enabled = on
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
	end
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute(Attributes.HammerId) ~= nil then
			setGlow(child, mood == "Zen")
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
