--!strict
--[[
	HUD (Stress Meter, score, hint), HP bars over bosses and the Victory Card.
	Display only: every number shown comes from server-written attributes,
	leaderstats or server messages; nothing here changes game state.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local Attributes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attributes"))
local BossConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BossConfig"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local GameplayController = require(script.Parent.GameplayController)
local LevelRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LevelRules"))
local ProgressController = require(script.Parent.ProgressController)

local UIController = {}

local VICTORY_CARD_SECONDS = 3
local PANEL_COLOR = Color3.fromRGB(30, 30, 40)
local STRESS_COLOR = Color3.fromRGB(235, 80, 80)
local HEALTH_COLOR = Color3.fromRGB(90, 210, 110)
local XP_COLOR = Color3.fromRGB(110, 150, 255)
local TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local TOAST_COLOR = Color3.fromRGB(255, 230, 80)
local TOAST_SECONDS = 2.5
local SAVED_SECONDS = 2
local SHOUT_SECONDS = 4.5
-- Boss name/HP/shout label: size in studs, and how far away it still shows
-- (an office is 30 studs across, so this covers the room and the corridor).
local BOSS_BAR_STUDS = Vector2.new(9, 4.2)
local BOSS_BAR_MAX_DISTANCE = 60

local localPlayer = Players.LocalPlayer
local BUFF_ORDER = { "Xp", "Damage", "CritDamage" }
local BUFF_LABELS: { [string]: string } = { Xp = "XP", Damage = "DMG", CritDamage = "CRIT DMG" }

-- 3725 -> "1:02:05", 125 -> "2:05"
local function formatTime(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	local hours, minutes, secs = total // 3600, (total % 3600) // 60, total % 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, secs)
	end
	return string.format("%d:%02d", minutes, secs)
end
local victoryCardShownAt = 0
local toastLabel: TextLabel? = nil
local savedLabel: TextLabel? = nil
local savedShownAt = 0
local toastShownAt = 0

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

	-- Score and coins, under the Stress Meter (from the server's leaderstats).
	local scoreLabel = makeLabel("Score", gui)
	scoreLabel.AnchorPoint = Vector2.new(0.5, 0)
	scoreLabel.Position = UDim2.new(0.5, 0, 0, 48)
	scoreLabel.Size = UDim2.new(0.6, 0, 0, 26)
	scoreLabel.Text = "Lv 1   Score: 0   Coins: 0   Zen Lv 0"
	task.spawn(function()
		local leaderstats = localPlayer:WaitForChild("leaderstats")
		local score = leaderstats:WaitForChild("Score")
		local coins = leaderstats:WaitForChild("Coins")
		if not score:IsA("IntValue") or not coins:IsA("IntValue") then
			return
		end
		local function refreshStats(): ()
			local snapshot = ProgressController.get()
			local zenLevel = if snapshot then snapshot.ZenLevel else 0
			local level = localPlayer:GetAttribute(Attributes.Level)
			scoreLabel.Text = string.format(
				"Lv %d   Score: %d   Coins: %d   Zen Lv %d",
				if typeof(level) == "number" then level else 1,
				score.Value,
				coins.Value,
				zenLevel
			)
		end
		score.Changed:Connect(refreshStats)
		coins.Changed:Connect(refreshStats)
		ProgressController.Changed:Connect(refreshStats)
		localPlayer:GetAttributeChangedSignal(Attributes.Level):Connect(refreshStats)
		refreshStats()
	end)

	-- Active buffs with time left, under the score line.
	local buffsLabel = makeLabel("Buffs", gui)
	buffsLabel.AnchorPoint = Vector2.new(0.5, 0)
	buffsLabel.Position = UDim2.new(0.5, 0, 0, 76)
	buffsLabel.Size = UDim2.new(0.7, 0, 0, 22)
	buffsLabel.TextColor3 = Color3.fromRGB(150, 230, 255)
	buffsLabel.Text = ""
	task.spawn(function()
		local receivedAt = os.clock()
		local lastSnapshot = ProgressController.get()
		ProgressController.Changed:Connect(function()
			lastSnapshot = ProgressController.get()
			receivedAt = os.clock()
		end)
		while gui.Parent ~= nil do
			local parts: { string } = {}
			local zenEnds = localPlayer:GetAttribute(Attributes.ZenBuffEnds)
			if typeof(zenEnds) == "number" then
				local left = zenEnds - Workspace:GetServerTimeNow()
				if left > 0 then
					table.insert(
						parts,
						string.format(
							"ZEN +%d dmg +%d%% crit %s",
							GameConfig.ZenBuffFlatDamage,
							GameConfig.ZenBuffCritChance * 100,
							formatTime(left)
						)
					)
				end
			end
			if lastSnapshot then
				-- Buffs only count down while playing, so local elapsed time matches the server.
				local elapsed = os.clock() - receivedAt
				for _, kind in BUFF_ORDER do
					local buff = lastSnapshot.Buffs[kind]
					if buff and buff.SecondsLeft - elapsed > 0 then
						table.insert(
							parts,
							string.format(
								"%s +%d%% %s",
								BUFF_LABELS[kind],
								buff.Percent,
								formatTime(buff.SecondsLeft - elapsed)
							)
						)
					end
				end
			end
			buffsLabel.Text = table.concat(parts, "   |   ")
			task.wait(1)
		end
	end)

	-- XP bar: a thin strip along the bottom edge, out of the way of the
	-- Stress Meter, the buttons on the right and the mobile thumbstick/jump.
	local xpFill, xpLabel = makeBar("XpBar", XP_COLOR, gui)
	local xpBar = xpFill.Parent :: Frame
	xpBar.AnchorPoint = Vector2.new(0.5, 1)
	xpBar.Position = UDim2.new(0.5, 0, 1, -6)
	xpBar.Size = UDim2.new(0.36, 0, 0, 16)
	xpBar.BackgroundTransparency = 0.25
	local xpConstraint = Instance.new("UISizeConstraint")
	xpConstraint.MinSize = Vector2.new(180, 14)
	xpConstraint.MaxSize = Vector2.new(440, 18)
	xpConstraint.Parent = xpBar
	local function refreshXp(): ()
		local snapshot = ProgressController.get()
		if snapshot == nil then
			xpFill.Size = UDim2.fromScale(0, 1)
			xpLabel.Text = ""
			return
		end
		local level = LevelRules.levelFor(snapshot.Xp)
		local floor = LevelRules.scoreForLevel(level)
		local nextAt = LevelRules.scoreForLevel(level + 1)
		setFill(xpFill, snapshot.Xp - floor, nextAt - floor)
		xpLabel.Text = string.format(
			"Lv %d   %d / %d XP to Lv %d",
			level,
			snapshot.Xp - floor,
			nextAt - floor,
			level + 1
		)
	end
	ProgressController.Changed:Connect(refreshXp)
	refreshXp()

	-- How to play, bottom centre (above the XP bar).
	local hint = makeLabel("Hint", gui)
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -28)
	hint.Size = UDim2.new(0.6, 0, 0, 28)
	hint.TextTransparency = 0.2
	hint.Text = if UserInputService.TouchEnabled
		then "Walk up to a boss and tap to swing your hammer! Tap Sprint to run."
		else "Walk up to a boss and click to swing your hammer! Hold Shift to sprint."

	-- "Progress saved" note, bottom-left, shown briefly after each save.
	local saved = makeLabel("Saved", gui)
	saved.AnchorPoint = Vector2.new(0, 1)
	saved.Position = UDim2.new(0, 16, 1, -16)
	saved.Size = UDim2.fromOffset(170, 22)
	saved.TextXAlignment = Enum.TextXAlignment.Left
	saved.TextColor3 = Color3.fromRGB(150, 230, 150)
	saved.Text = "Progress saved"
	saved.Visible = false
	savedLabel = saved

	-- Short-lived tips (e.g. "Get closer to the boss!"), just above the hint.
	local toast = makeLabel("Toast", gui)
	toast.AnchorPoint = Vector2.new(0.5, 1)
	toast.Position = UDim2.new(0.5, 0, 1, -64)
	toast.Size = UDim2.new(0.5, 0, 0, 32)
	toast.TextColor3 = TOAST_COLOR
	toast.TextStrokeTransparency = 0.3
	toast.Visible = false
	toastLabel = toast

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

	-- Not AlwaysOnTop: walls and floors hide it, so bosses in other offices and
	-- on other floors don't pile their labels up on the walls. Sized in studs,
	-- so a distant label shrinks instead of covering the screen.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BossBar"
	billboard.ResetOnSpawn = false
	billboard.Adornee = body
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.Size = UDim2.fromScale(BOSS_BAR_STUDS.X, BOSS_BAR_STUDS.Y)
	billboard.StudsOffset = Vector3.new(0, body.Size.Y / 2 + BOSS_BAR_STUDS.Y / 2 + 0.5, 0)
	billboard.MaxDistance = BOSS_BAR_MAX_DISTANCE

	-- Speech bubble on top (boss shouts), then the name and HP bar below it.
	local bubble = Instance.new("TextLabel")
	bubble.Name = "Shout"
	bubble.Size = UDim2.fromScale(1, 0.5)
	bubble.BackgroundColor3 = Color3.fromRGB(245, 240, 230)
	bubble.TextColor3 = Color3.fromRGB(35, 30, 40)
	bubble.Font = Enum.Font.FredokaOne
	bubble.TextScaled = true
	bubble.TextWrapped = true
	bubble.Visible = false
	bubble.Parent = billboard
	Instance.new("UICorner").Parent = bubble
	local bubblePadding = Instance.new("UIPadding")
	bubblePadding.PaddingLeft = UDim.new(0, 8)
	bubblePadding.PaddingRight = UDim.new(0, 8)
	bubblePadding.Parent = bubble

	local shownSeq = 0
	local function showShout(): ()
		local text = model:GetAttribute(Attributes.ShoutText)
		local seq = model:GetAttribute(Attributes.ShoutSeq)
		if typeof(text) ~= "string" or typeof(seq) ~= "number" then
			return
		end
		bubble.Text = text
		bubble.Visible = true
		shownSeq = seq
		task.delay(SHOUT_SECONDS, function()
			if shownSeq == seq then
				bubble.Visible = false
			end
		end)
	end
	model:GetAttributeChangedSignal(Attributes.ShoutSeq):Connect(showShout)

	local nameLabel = makeLabel("Name", billboard)
	nameLabel.Position = UDim2.fromScale(0, 0.52)
	nameLabel.Size = UDim2.fromScale(1, 0.24)
	local bossId = model:GetAttribute(Attributes.BossId)
	local definition = if typeof(bossId) == "string" then BossConfig.ById[bossId] else nil
	local customName = model:GetAttribute(Attributes.BossName)
	nameLabel.Text = if definition
		then definition.DisplayName
		elseif typeof(customName) == "string" then customName
		else model.Name

	local fill, healthLabel = makeBar("HealthBar", HEALTH_COLOR, billboard)
	local healthBar = fill.Parent :: Frame
	healthBar.Position = UDim2.fromScale(0, 0.77)
	healthBar.Size = UDim2.fromScale(1, 0.23)

	local function refresh(): ()
		local health = model:GetAttribute(Attributes.Health)
		local maxHealth = model:GetAttribute(Attributes.MaxHealth)
		if typeof(health) ~= "number" or typeof(maxHealth) ~= "number" then
			return
		end
		setFill(fill, health, maxHealth)
		local status = if typeof(bossId) == "string"
			then ProgressController.unlockStatus(bossId)
			else nil
		local previous = if status and status.PreviousBossId
			then BossConfig.ById[status.PreviousBossId]
			else nil
		if status and status.LevelNeeded > 0 then
			healthLabel.Text = string.format("LOCKED: reach Lv %d", status.LevelNeeded)
		elseif status and not status.Unlocked and previous then
			healthLabel.Text =
				string.format("LOCKED: beat %s x%d", previous.DisplayName, status.DefeatsNeeded)
		elseif status and not status.Unlocked then
			healthLabel.Text =
				string.format("LOCKED: beat every boss (%d left)", status.DefeatsNeeded)
		elseif model:GetAttribute(Attributes.Defeated) == true then
			healthLabel.Text = "DEFEATED!"
		else
			healthLabel.Text = string.format("%d / %d", health, maxHealth)
		end
	end
	model:GetAttributeChangedSignal(Attributes.Health):Connect(refresh)
	model:GetAttributeChangedSignal(Attributes.Defeated):Connect(refresh)
	local progressConnection = ProgressController.Changed:Connect(refresh)
	model.Destroying:Connect(function()
		progressConnection:Disconnect()
	end)
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

-- Shows the centre card; a newer card resets the timer instead of being hidden
-- by the older one.
local function showCard(card: Frame, text: string): ()
	local label = card:FindFirstChild("Text") :: TextLabel
	label.Text = text
	victoryCardShownAt = os.clock()
	local shownAt = victoryCardShownAt
	card.Visible = true
	task.delay(VICTORY_CARD_SECONDS, function()
		if victoryCardShownAt == shownAt then
			card.Visible = false
		end
	end)
end

-- Your Zen gets the big card; someone else's gets a toast.
local function onZenAchieved(card: Frame, payload: unknown): ()
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	local userId, name, level, bonus = data.UserId, data.DisplayName, data.ZenLevel, data.BonusCoins
	if typeof(userId) ~= "number" or typeof(name) ~= "string" or typeof(level) ~= "number" then
		return
	end
	if userId == localPlayer.UserId then
		showCard(
			card,
			string.format(
				"ZEN ACHIEVED!\n+%d coins   Zen Level %d\nYour hammer glows while you stay Zen.",
				if typeof(bonus) == "number" then bonus else 0,
				level
			)
		)
	else
		UIController.showToast(string.format("%s reached Zen! (Level %d)", name, level))
	end
end

local function showVictoryCard(card: Frame, payload: unknown): ()
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	local bossId, rewarded, score, coins, stress =
		data.BossId, data.Rewarded, data.ScoreAwarded, data.CoinsAwarded, data.StressRelieved
	if typeof(bossId) ~= "string" or typeof(rewarded) ~= "boolean" then
		return
	end

	local definition = BossConfig.ById[bossId]
	local bossName = if definition
		then definition.DisplayName
		elseif typeof(data.BossName) == "string" then data.BossName
		else "Boss"
	local lines = { bossName .. " defeated!" }
	if data.AdminDamage == true then
		table.insert(lines, "Admin damage was on: no rewards for this boss.")
		showCard(card, table.concat(lines, "\n"))
		return
	end
	if typeof(score) == "number" and typeof(coins) == "number" then
		local share = data.SharePercent
		table.insert(
			lines,
			string.format(
				"+%d score   +%d coins   (your share %d%%)",
				score,
				coins,
				if typeof(share) == "number" then share else 0
			)
		)
	end
	if data.LastHit == true then
		table.insert(lines, "LAST HIT BONUS!")
	end
	if rewarded and typeof(stress) == "number" and stress > 0 then
		table.insert(lines, string.format("-%d stress", math.floor(stress + 0.5)))
	elseif not rewarded then
		table.insert(lines, "Deal at least 10% of its HP to count the defeat.")
	end
	local buffDrop = data.BuffDropText
	if typeof(buffDrop) == "string" and #buffDrop <= 60 then
		table.insert(lines, "BONUS DROP: " .. buffDrop .. "!")
	end
	local unlocked = data.UnlockedBossIds
	if typeof(unlocked) == "table" then
		for _, unlockedId in unlocked :: { unknown } do
			local unlockedBoss = if typeof(unlockedId) == "string"
				then BossConfig.ById[unlockedId]
				else nil
			if unlockedBoss then
				table.insert(lines, "NEW BOSS UNLOCKED: " .. unlockedBoss.DisplayName .. "!")
			end
		end
	end
	showCard(card, table.concat(lines, "\n"))
end

-- Shows a short tip; a newer tip replaces the current one. No-op before the HUD exists.
function UIController.showToast(text: string): ()
	local toast = toastLabel
	if toast == nil then
		return
	end
	toast.Text = text
	toast.Visible = true
	toastShownAt = os.clock()
	local shownAt = toastShownAt
	task.delay(TOAST_SECONDS, function()
		if toastShownAt == shownAt then
			toast.Visible = false
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

	local zenAchieved =
		ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Mood"):WaitForChild("ZenAchieved")
	assert(zenAchieved:IsA("RemoteEvent"), "ZenAchieved must be a RemoteEvent")
	zenAchieved.OnClientEvent:Connect(function(payload: unknown)
		onZenAchieved(card, payload)
	end)

	-- Short messages from the server (e.g. the Executive Elevator).
	local toastRemote =
		ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notify"):WaitForChild("Toast")
	assert(toastRemote:IsA("RemoteEvent"), "Notify.Toast must be a RemoteEvent")
	toastRemote.OnClientEvent:Connect(function(message: unknown)
		if typeof(message) == "string" and #message <= 120 then
			UIController.showToast(message)
		end
	end)

	local savedRemote =
		ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Profile"):WaitForChild("Saved")
	assert(savedRemote:IsA("RemoteEvent"), "Profile.Saved must be a RemoteEvent")
	savedRemote.OnClientEvent:Connect(function()
		local label = savedLabel
		if label == nil then
			return
		end
		label.Visible = true
		savedShownAt = os.clock()
		local shownAt = savedShownAt
		task.delay(SAVED_SECONDS, function()
			if savedShownAt == shownAt then
				label.Visible = false
			end
		end)
	end)
end

return UIController
