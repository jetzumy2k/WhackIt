--!strict
--[[
	HUD (Stress Meter, score, hint), HP bars over bosses and the Victory Card.
	Display only: every number shown comes from server-written attributes,
	leaderstats or server messages; nothing here changes game state.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Attributes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attributes"))
local BossConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BossConfig"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local GameplayController = require(script.Parent.GameplayController)

local UIController = {}

local VICTORY_CARD_SECONDS = 3
local PANEL_COLOR = Color3.fromRGB(30, 30, 40)
local STRESS_COLOR = Color3.fromRGB(235, 80, 80)
local HEALTH_COLOR = Color3.fromRGB(90, 210, 110)
local TEXT_COLOR = Color3.fromRGB(255, 255, 255)

local localPlayer = Players.LocalPlayer
local victoryCardShownAt = 0

local function makeLabel(name: string, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.TextColor3 = TEXT_COLOR
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = parent
	return label
end

-- A dark bar with a coloured fill; returns the fill and the text label on top.
local function makeBar(name: string, color: Color3, parent: Instance): (Frame, TextLabel)
	local bar = Instance.new("Frame")
	bar.Name = name
	bar.BackgroundColor3 = PANEL_COLOR
	bar.BorderSizePixel = 0
	bar.Parent = parent
	Instance.new("UICorner").Parent = bar

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = bar
	Instance.new("UICorner").Parent = fill

	local label = makeLabel("Label", bar)
	label.ZIndex = 2
	return fill, label
end

local function setFill(fill: Frame, value: number, max: number): ()
	local ratio = if max > 0 then math.clamp(value / max, 0, 1) else 0
	fill.Size = UDim2.fromScale(ratio, 1)
end

local function buildHud(): (ScreenGui, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Stress Meter, top centre.
	local stressFill, stressLabel = makeBar("StressBar", STRESS_COLOR, gui)
	local stressBar = stressFill.Parent :: Frame
	stressBar.AnchorPoint = Vector2.new(0.5, 0)
	stressBar.Position = UDim2.new(0.5, 0, 0, 12)
	stressBar.Size = UDim2.new(0.4, 0, 0, 30)
	local stressConstraint = Instance.new("UISizeConstraint")
	stressConstraint.MinSize = Vector2.new(200, 24)
	stressConstraint.MaxSize = Vector2.new(480, 36)
	stressConstraint.Parent = stressBar

	local function refreshStress(): ()
		local stress = localPlayer:GetAttribute(Attributes.Stress)
		local value = if typeof(stress) == "number" then stress else GameConfig.StartingStress
		setFill(stressFill, value, GameConfig.MaxStress)
		stressLabel.Text = string.format("Stress %d / %d", math.ceil(value), GameConfig.MaxStress)
	end
	localPlayer:GetAttributeChangedSignal(Attributes.Stress):Connect(refreshStress)
	refreshStress()

	-- Score, under the Stress Meter.
	local scoreLabel = makeLabel("Score", gui)
	scoreLabel.AnchorPoint = Vector2.new(0.5, 0)
	scoreLabel.Position = UDim2.new(0.5, 0, 0, 48)
	scoreLabel.Size = UDim2.new(0.3, 0, 0, 26)
	scoreLabel.Text = "Score: 0"
	task.spawn(function()
		local leaderstats = localPlayer:WaitForChild("leaderstats")
		local score = leaderstats:WaitForChild("Score")
		if not score:IsA("IntValue") then
			return
		end
		local function refreshScore(): ()
			scoreLabel.Text = "Score: " .. score.Value
		end
		score.Changed:Connect(refreshScore)
		refreshScore()
	end)

	-- How to play, bottom centre.
	local hint = makeLabel("Hint", gui)
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -24)
	hint.Size = UDim2.new(0.6, 0, 0, 28)
	hint.TextTransparency = 0.2
	hint.Text = if UserInputService.TouchEnabled
		then "Walk up to a boss and tap to swing your hammer!"
		else "Walk up to a boss and click to swing your hammer!"

	-- Victory Card, centre, hidden until a boss you fought is defeated.
	local card = Instance.new("Frame")
	card.Name = "VictoryCard"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.4)
	card.Size = UDim2.fromScale(0.45, 0.18)
	card.BackgroundColor3 = PANEL_COLOR
	card.BackgroundTransparency = 0.1
	card.Visible = false
	card.Parent = gui
	Instance.new("UICorner").Parent = card
	local cardConstraint = Instance.new("UISizeConstraint")
	cardConstraint.MinSize = Vector2.new(260, 90)
	cardConstraint.MaxSize = Vector2.new(560, 180)
	cardConstraint.Parent = card
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = card
	makeLabel("Text", card)

	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	return gui, card
end

local attachBossBar: (model: Model, billboardParent: Instance) -> ()
function attachBossBar(model: Model, billboardParent: Instance): ()
	local body = model.PrimaryPart
	if body == nil then
		-- The model can replicate a moment before its parts; retry once they arrive.
		local connection: RBXScriptConnection
		connection = model:GetPropertyChangedSignal("PrimaryPart"):Connect(function()
			if model.PrimaryPart then
				connection:Disconnect()
				attachBossBar(model, billboardParent)
			end
		end)
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BossBar"
	billboard.ResetOnSpawn = false
	billboard.Adornee = body
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(200, 50)
	billboard.StudsOffset = Vector3.new(0, body.Size.Y / 2 + 2, 0)
	billboard.MaxDistance = 120

	local nameLabel = makeLabel("Name", billboard)
	nameLabel.Size = UDim2.fromScale(1, 0.5)
	local bossId = model:GetAttribute(Attributes.BossId)
	local definition = if typeof(bossId) == "string" then BossConfig.ById[bossId] else nil
	nameLabel.Text = if definition then definition.DisplayName else model.Name

	local fill, healthLabel = makeBar("HealthBar", HEALTH_COLOR, billboard)
	local healthBar = fill.Parent :: Frame
	healthBar.Position = UDim2.fromScale(0, 0.55)
	healthBar.Size = UDim2.fromScale(1, 0.45)

	local function refresh(): ()
		local health = model:GetAttribute(Attributes.Health)
		local maxHealth = model:GetAttribute(Attributes.MaxHealth)
		if typeof(health) ~= "number" or typeof(maxHealth) ~= "number" then
			return
		end
		setFill(fill, health, maxHealth)
		healthLabel.Text = if model:GetAttribute(Attributes.Defeated) == true
			then "DEFEATED!"
			else string.format("%d / %d", health, maxHealth)
	end
	model:GetAttributeChangedSignal(Attributes.Health):Connect(refresh)
	model:GetAttributeChangedSignal(Attributes.Defeated):Connect(refresh)
	refresh()

	billboard.Parent = billboardParent
	-- The billboard lives outside the model, so remove it when the boss goes.
	model.Destroying:Connect(function()
		billboard:Destroy()
	end)
	model.AncestryChanged:Connect(function(_, parent: Instance?)
		if parent == nil then
			billboard:Destroy()
		end
	end)
end

local function showVictoryCard(card: Frame, payload: unknown): ()
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	local bossId, rewarded, score, stress =
		data.BossId, data.Rewarded, data.ScoreAwarded, data.StressRelieved
	if typeof(bossId) ~= "string" or typeof(rewarded) ~= "boolean" then
		return
	end

	local definition = BossConfig.ById[bossId]
	local bossName = if definition then definition.DisplayName else "Boss"
	local text = card:FindFirstChild("Text") :: TextLabel
	if rewarded and typeof(score) == "number" and typeof(stress) == "number" then
		text.Text = string.format(
			"%s defeated!\n+%d score   -%d stress",
			bossName,
			score,
			math.floor(stress + 0.5)
		)
	else
		text.Text = string.format("%s defeated!\nHit it more next time to earn a reward.", bossName)
	end

	-- A newer card resets the timer instead of being hidden by the older one.
	victoryCardShownAt = os.clock()
	local shownAt = victoryCardShownAt
	card.Visible = true
	task.delay(VICTORY_CARD_SECONDS, function()
		if victoryCardShownAt == shownAt then
			card.Visible = false
		end
	end)
end

function UIController.start(): ()
	-- The hammer is the only tool and stays in hand; hiding the hotbar stops
	-- players accidentally unequipping it with number keys.
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

	local _, card = buildHud()

	local billboards = Instance.new("Folder")
	billboards.Name = "BossBars"
	billboards.Parent = localPlayer:WaitForChild("PlayerGui")

	local bossesFolder = GameplayController.waitForBossesFolder()
	local function onBossAdded(child: Instance): ()
		if child:IsA("Model") then
			attachBossBar(child, billboards)
		end
	end
	bossesFolder.ChildAdded:Connect(onBossAdded)
	for _, child in bossesFolder:GetChildren() do
		onBossAdded(child)
	end

	local bossDefeated = ReplicatedStorage:WaitForChild("Remotes")
		:WaitForChild("Combat")
		:WaitForChild("BossDefeated")
	assert(bossDefeated:IsA("RemoteEvent"), "BossDefeated must be a RemoteEvent")
	bossDefeated.OnClientEvent:Connect(function(payload: unknown)
		showVictoryCard(card, payload)
	end)
end

return UIController
