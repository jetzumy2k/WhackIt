--!strict
--[[
	HUD (Stress Meter, score, hint), HP bars over bosses and the Victory Card.
	Display only: every number shown comes from server-written attributes,
	leaderstats or server messages; nothing here changes game state.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local Attributes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attributes"))
local BossConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BossConfig"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local GameplayController = require(script.Parent.GameplayController)
local HudFormat = require(script.Parent.Parent.Lib.HudFormat)
local LevelRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LevelRules"))
local StressRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StressRules"))
local ProgressController = require(script.Parent.ProgressController)
local Responsive = require(script.Parent.Parent.Lib.Responsive)
local UiTokens = require(script.Parent.Parent.Lib.UiTokens)

local UIController = {}

local VICTORY_CARD_SECONDS = 3
local PANEL_COLOR = Color3.fromRGB(30, 30, 40)
local HEALTH_COLOR = Color3.fromRGB(90, 210, 110)
local XP_COLOR = Color3.fromRGB(110, 150, 255)
local TEXT_COLOR = Color3.fromRGB(255, 255, 255)
-- The Stress Meter in the top bar strip (pixels tall).
local TOP_METER_HEIGHT = 34
local TOAST_COLOR = Color3.fromRGB(255, 230, 80)
local TOAST_SECONDS = 2.5
local SAVED_SECONDS = 2
local SHOUT_SECONDS = 4.5
-- On phones the how-to-play line fades after this long, freeing the bottom of the screen.
local PHONE_HINT_SECONDS = 20
-- A boss's short line to this player (BossVisualController) shows this long.
local LOCAL_LINE_SECONDS = 2
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

	-- The top of the HUD (visual overhaul V4a): a Stress Meter card with a
	-- mood face, a row of stat chips under it, and boost chips under those.
	local CARD = UiTokens.Color.Window
	local function pill(name: string, parent: Instance): Frame
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.BackgroundColor3 = CARD
		frame.BackgroundTransparency = 0.12
		frame.BorderSizePixel = 0
		frame.Parent = parent
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = frame
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Transparency = 0.85
		stroke.Thickness = 1
		stroke.Parent = frame
		return frame
	end
	local function text(name: string, parent: Instance, size: number, font: Enum.Font?): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.TextColor3 = TEXT_COLOR
		label.Font = font or UiTokens.Font.Bold
		label.TextSize = math.floor(size * Responsive.textScale())
		label.Parent = parent
		return label
	end

	-- Stress Meter: mood face, a track with a colour-shifting fill, the value.
	-- It sits in Roblox's top bar strip, between the menu buttons (owner
	-- feedback 2026-10-10: under the bar it covered too much of the view), so
	-- it has its own ScreenGui that ignores the top bar inset.
	local topGui = Instance.new("ScreenGui")
	topGui.Name = "HudTop"
	topGui.ResetOnSpawn = false
	topGui.IgnoreGuiInset = true
	topGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	topGui.Parent = localPlayer:WaitForChild("PlayerGui")
	local meter = pill("StressMeter", topGui)
	meter.AnchorPoint = Vector2.new(0.5, 0.5)
	meter.Size = UDim2.new(0.3, 0, 0, TOP_METER_HEIGHT)
	local meterLimit = Instance.new("UISizeConstraint")
	meterLimit.MinSize = Vector2.new(200, 28)
	meterLimit.MaxSize = Vector2.new(380, TOP_METER_HEIGHT)
	meterLimit.Parent = meter
	-- Centred in the top bar's height (it is taller on newer Roblox UIs).
	local function placeMeter(): ()
		local inset = GuiService:GetGuiInset().Y
		local height = if inset >= TOP_METER_HEIGHT + 4 then inset else TOP_METER_HEIGHT + 12
		meter.Position = UDim2.new(0.5, 0, 0, height / 2)
	end
	placeMeter()
	task.delay(2, placeMeter) -- the inset is sometimes reported late
	local mood = text("Mood", meter, 24, UiTokens.Font.Title)
	mood.Size = UDim2.new(0, 36, 1, 0)
	mood.Position = UDim2.fromOffset(4, 0)
	local track = Instance.new("Frame")
	track.Name = "StressTrack"
	track.BackgroundColor3 = UiTokens.Color.Field
	track.BorderSizePixel = 0
	track.Position = UDim2.new(0, 42, 0.5, -7)
	track.Size = UDim2.new(1, -112, 0, 14)
	track.Parent = meter
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track
	local stressFill = Instance.new("Frame")
	stressFill.Name = "Fill"
	stressFill.BorderSizePixel = 0
	stressFill.Size = UDim2.fromScale(1, 1)
	stressFill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = stressFill
	local stressLabel = text("StressValue", meter, 16)
	stressLabel.AnchorPoint = Vector2.new(1, 0)
	stressLabel.Position = UDim2.new(1, -12, 0, 0)
	stressLabel.Size = UDim2.new(0, 60, 1, 0)
	stressLabel.TextXAlignment = Enum.TextXAlignment.Right

	-- The fill eases to each new value (it jumps with Reduced motion); one
	-- short tween per change, replacing the previous one.
	local stressTween: Tween? = nil
	local function refreshStress(): ()
		local stress = localPlayer:GetAttribute(Attributes.Stress)
		local value = if typeof(stress) == "number" then stress else GameConfig.StartingStress
		local ratio = math.clamp(value / GameConfig.MaxStress, 0, 1)
		if stressTween then
			stressTween:Cancel()
		end
		local tween = TweenService:Create(
			stressFill,
			UiTokens.motion(
				TweenInfo.new(UiTokens.Motion.Bar, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			),
			{ Size = UDim2.fromScale(ratio, 1), BackgroundColor3 = HudFormat.stressColor(ratio) }
		)
		stressTween = tween
		tween:Play()
		mood.Text = HudFormat.moodIcon(value)
		stressLabel.Text = string.format("%d", math.ceil(value))
	end
	localPlayer:GetAttributeChangedSignal(Attributes.Stress):Connect(refreshStress)
	refreshStress()

	-- Stat chips: level, score, coins and the Zen bonus.
	local stats = Instance.new("Frame")
	stats.Name = "Stats"
	stats.AnchorPoint = Vector2.new(0.5, 0)
	stats.Position = UDim2.new(0.5, 0, 0, 8)
	stats.Size = UDim2.fromOffset(0, 30)
	stats.AutomaticSize = Enum.AutomaticSize.X
	stats.BackgroundTransparency = 1
	stats.Parent = gui
	local statsLayout = Instance.new("UIListLayout")
	statsLayout.FillDirection = Enum.FillDirection.Horizontal
	statsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	statsLayout.Padding = UDim.new(0, 8)
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Parent = stats
	local function chip(parent: Instance, name: string, icon: string, order: number): TextLabel
		local frame = pill(name, parent)
		frame.LayoutOrder = order
		frame.Size = UDim2.fromOffset(0, 30)
		frame.AutomaticSize = Enum.AutomaticSize.X
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 10)
		padding.PaddingRight = UDim.new(0, 12)
		padding.Parent = frame
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = frame
		local iconLabel = text("Icon", frame, 17, UiTokens.Font.Title)
		iconLabel.Size = UDim2.fromOffset(20, 30)
		iconLabel.Text = icon
		local value = text("Value", frame, 17)
		value.LayoutOrder = 1
		value.Size = UDim2.fromOffset(0, 30)
		value.AutomaticSize = Enum.AutomaticSize.X
		return value
	end
	local levelValue = chip(stats, "LevelChip", "⭐", 1)
	local scoreValue = chip(stats, "ScoreChip", "🏆", 2)
	local coinsValue = chip(stats, "CoinsChip", "🪙", 3)
	local zenValue = chip(stats, "ZenChip", "🧘", 4)
	coinsValue.TextColor3 = Color3.fromRGB(255, 220, 120)

	-- Coins count up to a new total, with a "+N" that floats up from the chip
	-- (shown without moving with Reduced motion).
	local shownCoins = 0
	local coinsTween: Tween? = nil
	local counter = Instance.new("NumberValue")
	counter.Changed:Connect(function(value: number)
		coinsValue.Text = HudFormat.thousands(value)
	end)
	-- A full-screen layer for the floating "+N", so its position is measured
	-- in the same space as the chip whatever the screen insets are.
	local floats = Instance.new("Frame")
	floats.Name = "Floats"
	floats.BackgroundTransparency = 1
	floats.Size = UDim2.fromScale(1, 1)
	floats.ZIndex = 5
	floats.Parent = gui
	local function floatGain(amount: number): ()
		local chipFrame = coinsValue.Parent :: Frame
		local gain = text("CoinGain", floats, 18)
		gain.Text = "+" .. HudFormat.thousands(amount)
		gain.TextColor3 = Color3.fromRGB(255, 220, 120)
		gain.TextStrokeTransparency = 0.4
		gain.AnchorPoint = Vector2.new(0.5, 0)
		gain.Size = UDim2.fromOffset(80, 22)
		local start = chipFrame.AbsolutePosition
			- floats.AbsolutePosition
			+ Vector2.new(chipFrame.AbsoluteSize.X / 2, chipFrame.AbsoluteSize.Y + 2)
		gain.Position = UDim2.fromOffset(start.X, start.Y)
		local info =
			UiTokens.motion(TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
		TweenService:Create(gain, info, {
			Position = UDim2.fromOffset(start.X, start.Y + 18),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
		task.delay(1, function()
			gain:Destroy()
		end)
	end
	local function showCoins(total: number): ()
		if coinsTween then
			coinsTween:Cancel()
		end
		local gained = total - shownCoins
		shownCoins = total
		if gained > 0 and counter.Value > 0 then
			floatGain(gained)
			local tween = TweenService:Create(
				counter,
				UiTokens.motion(TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)),
				{ Value = total }
			)
			coinsTween = tween
			tween:Play()
		else
			counter.Value = total
			coinsValue.Text = HudFormat.thousands(total)
		end
	end

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
			levelValue.Text = string.format("Lv %d", if typeof(level) == "number" then level else 1)
			scoreValue.Text = HudFormat.thousands(score.Value)
			zenValue.Text = string.format(
				"+%d%%%s",
				StressRules.zenBonusPercent(zenLevel),
				if StressRules.zenBonusIsMax(zenLevel) then " max" else ""
			)
		end
		score.Changed:Connect(refreshStats)
		coins.Changed:Connect(function()
			showCoins(coins.Value)
		end)
		ProgressController.Changed:Connect(refreshStats)
		localPlayer:GetAttributeChangedSignal(Attributes.Level):Connect(refreshStats)
		refreshStats()
		showCoins(coins.Value)
	end)

	-- Active boosts as chips with time left, under the stats. One chip per
	-- kind, reused (shown or hidden), text updated once a second.
	local boosts = Instance.new("Frame")
	boosts.Name = "Boosts"
	boosts.AnchorPoint = Vector2.new(0.5, 0)
	boosts.Position = UDim2.new(0.5, 0, 0, 44)
	boosts.Size = UDim2.fromOffset(0, 26)
	boosts.AutomaticSize = Enum.AutomaticSize.X
	boosts.BackgroundTransparency = 1
	boosts.Parent = gui
	local boostsLayout = Instance.new("UIListLayout")
	boostsLayout.FillDirection = Enum.FillDirection.Horizontal
	boostsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	boostsLayout.Padding = UDim.new(0, 6)
	boostsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	boostsLayout.Parent = boosts
	local boostChips: { [string]: TextLabel } = {}
	local boostIcons: { [string]: string } =
		{ Zen = "🧘", Xp = "✨", Damage = "💥", CritDamage = "🎯" }
	for order, kind in { "Zen", "Xp", "Damage", "CritDamage" } do
		local value = chip(boosts, kind .. "Boost", boostIcons[kind], order)
		local frame = value.Parent :: Frame
		frame.Size = UDim2.fromOffset(0, 26)
		value.TextSize = math.floor(14 * Responsive.textScale())
		value.TextColor3 = Color3.fromRGB(150, 230, 255)
		frame.Visible = false
		boostChips[kind] = value
	end
	task.spawn(function()
		local receivedAt = os.clock()
		local lastSnapshot = ProgressController.get()
		ProgressController.Changed:Connect(function()
			lastSnapshot = ProgressController.get()
			receivedAt = os.clock()
		end)
		while gui.Parent ~= nil do
			local shown: { [string]: string } = {}
			local zenEnds = localPlayer:GetAttribute(Attributes.ZenBuffEnds)
			if typeof(zenEnds) == "number" then
				local left = zenEnds - Workspace:GetServerTimeNow()
				if left > 0 then
					shown.Zen = string.format(
						"+%d dmg +%d%% crit · %s",
						GameConfig.ZenBuffFlatDamage,
						GameConfig.ZenBuffCritChance * 100,
						formatTime(left)
					)
				end
			end
			if lastSnapshot then
				-- Buffs only count down while playing, so local elapsed time matches the server.
				local elapsed = os.clock() - receivedAt
				for _, kind in BUFF_ORDER do
					local buff = lastSnapshot.Buffs[kind]
					if buff and buff.SecondsLeft - elapsed > 0 then
						shown[kind] = string.format(
							"%s +%d%% · %s",
							BUFF_LABELS[kind],
							buff.Percent,
							formatTime(buff.SecondsLeft - elapsed)
						)
					end
				end
			end
			for kind, label in boostChips do
				local line = shown[kind]
				local frame = label.Parent :: Frame
				frame.Visible = line ~= nil
				if line then
					label.Text = line
				end
			end
			task.wait(1)
		end
	end)

	-- XP bar along the bottom edge (out of the way of the Stress Meter, the
	-- buttons on the right and the mobile thumbstick/jump): a level badge and
	-- a gradient fill.
	local xpCard = pill("XpBar", gui)
	xpCard.AnchorPoint = Vector2.new(0.5, 1)
	xpCard.Position = UDim2.new(0.5, 0, 1, -6)
	xpCard.Size = UDim2.new(0.36, 0, 0, 22)
	local xpLimit = Instance.new("UISizeConstraint")
	xpLimit.MinSize = Vector2.new(200, 20)
	xpLimit.MaxSize = Vector2.new(460, 22)
	xpLimit.Parent = xpCard
	local badge = Instance.new("TextLabel")
	badge.Name = "LevelBadge"
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.Position = UDim2.new(0, -6, 0.5, 0)
	badge.Size = UDim2.fromOffset(30, 30)
	badge.BackgroundColor3 = XP_COLOR
	badge.TextColor3 = TEXT_COLOR
	badge.Font = UiTokens.Font.Title
	badge.TextSize = math.floor(14 * Responsive.textScale())
	badge.ZIndex = 3
	badge.Parent = xpCard
	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(1, 0)
	badgeCorner.Parent = badge
	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Color = Color3.new(1, 1, 1)
	badgeStroke.Transparency = 0.5
	badgeStroke.Thickness = 1.5
	badgeStroke.Parent = badge
	local xpTrack = Instance.new("Frame")
	xpTrack.Name = "Track"
	xpTrack.BackgroundTransparency = 1
	xpTrack.Position = UDim2.fromOffset(28, 4)
	xpTrack.Size = UDim2.new(1, -34, 1, -8)
	xpTrack.Parent = xpCard
	local xpFill = Instance.new("Frame")
	xpFill.Name = "Fill"
	xpFill.BackgroundColor3 = Color3.new(1, 1, 1)
	xpFill.BorderSizePixel = 0
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.Parent = xpTrack
	local xpFillCorner = Instance.new("UICorner")
	xpFillCorner.CornerRadius = UDim.new(1, 0)
	xpFillCorner.Parent = xpFill
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(XP_COLOR, Color3.fromRGB(170, 120, 255))
	gradient.Parent = xpFill
	local xpLabel = text("Label", xpCard, 12)
	xpLabel.Position = UDim2.fromOffset(28, 0)
	xpLabel.Size = UDim2.new(1, -34, 1, 0)
	xpLabel.ZIndex = 2
	xpLabel.TextStrokeTransparency = 0.6
	local function refreshXp(): ()
		local snapshot = ProgressController.get()
		if snapshot == nil then
			xpFill.Size = UDim2.fromScale(0, 1)
			xpLabel.Text = ""
			badge.Text = ""
			return
		end
		local level = LevelRules.levelFor(snapshot.Xp)
		badge.Text = tostring(level)
		if LevelRules.isMax(level) then
			-- The cap: a full bar; XP keeps counting for the leaderboard.
			setFill(xpFill, 1, 1)
			xpLabel.Text =
				string.format("👑 MAX LEVEL · %s XP", HudFormat.thousands(snapshot.Xp))
			return
		end
		local floor = LevelRules.scoreForLevel(level)
		local nextAt = LevelRules.scoreForLevel(level + 1)
		setFill(xpFill, snapshot.Xp - floor, nextAt - floor)
		xpLabel.Text = string.format(
			"%s / %s XP to Lv %d",
			HudFormat.thousands(snapshot.Xp - floor),
			HudFormat.thousands(nextAt - floor),
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
	Responsive.capText(hint, 20)
	if Responsive.formFactor() == "Phone" then
		task.delay(PHONE_HINT_SECONDS, function()
			TweenService:Create(hint, TweenInfo.new(1), { TextTransparency = 1 }):Play()
		end)
	end

	-- "Progress saved" note, bottom-left, shown briefly after each save.
	local saved = makeLabel("Saved", gui)
	saved.AnchorPoint = Vector2.new(0, 1)
	saved.Position = UDim2.new(0, 16, 1, -16)
	saved.Size = UDim2.fromOffset(170, 22)
	saved.TextXAlignment = Enum.TextXAlignment.Left
	saved.TextColor3 = Color3.fromRGB(150, 230, 150)
	saved.Text = "Progress saved"
	saved.Visible = false
	Responsive.capText(saved, 18)
	savedLabel = saved

	-- Short-lived tips (e.g. "Get closer to the boss!"), just above the hint.
	local toast = makeLabel("Toast", gui)
	toast.AnchorPoint = Vector2.new(0.5, 1)
	toast.Position = UDim2.new(0.5, 0, 1, -64)
	toast.Size = UDim2.new(0.5, 0, 0, 32)
	toast.TextColor3 = TOAST_COLOR
	toast.TextStrokeTransparency = 0.3
	toast.TextWrapped = true
	toast.Visible = false
	Responsive.capText(toast, 24)
	toastLabel = toast

	-- Victory Card, centre, hidden until a boss you fought is defeated.
	local card = Instance.new("Frame")
	card.Name = "VictoryCard"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.4)
	card.Size = UDim2.fromScale(0.45, 0.18)
	card.BackgroundColor3 = UiTokens.Color.Window
	card.BackgroundTransparency = 0.04
	card.Visible = false
	card.Parent = gui
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, UiTokens.Radius.Window)
	cardCorner.Parent = card
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = UiTokens.Color.Heading
	cardStroke.Thickness = 2
	cardStroke.Parent = card
	local cardScale = Instance.new("UIScale")
	cardScale.Parent = card
	local cardConstraint = Instance.new("UISizeConstraint")
	cardConstraint.MinSize = Vector2.new(260, 90)
	cardConstraint.MaxSize = Vector2.new(560, 180)
	cardConstraint.Parent = card
	-- Phones get a wider, taller card so its several lines stay readable.
	Responsive.onChanged(function()
		card.Size = if Responsive.formFactor() == "Phone"
			then UDim2.fromScale(0.62, 0.36)
			else UDim2.fromScale(0.45, 0.18)
	end)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = card
	-- An icon disc on the left, a gold title line and the details beside it.
	local disc = Instance.new("TextLabel")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0, 0.5)
	disc.Position = UDim2.fromScale(0, 0.5)
	disc.Size = UDim2.fromOffset(56, 56)
	disc.BackgroundColor3 = Color3.fromRGB(190, 140, 50)
	disc.Font = UiTokens.Font.Title
	disc.TextSize = 30
	disc.TextColor3 = TEXT_COLOR
	disc.Parent = card
	local discCorner = Instance.new("UICorner")
	discCorner.CornerRadius = UDim.new(1, 0)
	discCorner.Parent = disc
	local title = makeLabel("Title", card)
	title.Position = UDim2.fromOffset(66, 0)
	title.Size = UDim2.new(1, -66, 0.36, 0)
	title.TextColor3 = UiTokens.Color.Heading
	title.TextXAlignment = Enum.TextXAlignment.Left
	Responsive.capText(title, 26)
	local details = makeLabel("Text", card)
	details.Position = UDim2.new(0, 66, 0.38, 0)
	details.Size = UDim2.new(1, -66, 0.62, 0)
	details.Font = UiTokens.Font.Body
	details.TextXAlignment = Enum.TextXAlignment.Left
	details.TextYAlignment = Enum.TextYAlignment.Top
	details.TextWrapped = true
	Responsive.capText(details, 18)

	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	return gui, card
end

-- Boss model -> shows a local line in its speech bubble (weak keys).
local localLineShowers: { [Model]: (text: string) -> () } = setmetatable({}, { __mode = "k" }) :: any

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

	-- Server shouts (everyone sees them) win over local lines (just this
	-- player): a local line never covers a shout that is still showing.
	local shown = 0
	local shoutShowing = false
	local function showLine(text: string, seconds: number, isShout: boolean): ()
		bubble.Text = text
		bubble.Visible = true
		shoutShowing = isShout
		shown += 1
		local token = shown
		task.delay(seconds, function()
			if shown == token then
				bubble.Visible = false
				shoutShowing = false
			end
		end)
	end
	local function showShout(): ()
		local text = model:GetAttribute(Attributes.ShoutText)
		local seq = model:GetAttribute(Attributes.ShoutSeq)
		if typeof(text) ~= "string" or typeof(seq) ~= "number" then
			return
		end
		showLine(text, SHOUT_SECONDS, true)
	end
	model:GetAttributeChangedSignal(Attributes.ShoutSeq):Connect(showShout)
	localLineShowers[model] = function(text: string)
		if not shoutShowing then
			showLine(text, LOCAL_LINE_SECONDS, false)
		end
	end

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

-- Shows the centre card: the first line as its title, the rest under it, and
-- `icon` in the disc; it pops in (instantly with Reduced motion). A newer card
-- resets the timer instead of being hidden by the older one.
local function showCard(card: Frame, text: string, icon: string): ()
	local firstLine, rest = string.match(text, "^([^\n]*)\n?(.*)$")
	local title = card:FindFirstChild("Title") :: TextLabel
	local details = card:FindFirstChild("Text") :: TextLabel
	local disc = card:FindFirstChild("Disc") :: TextLabel
	title.Text = firstLine or text
	details.Text = rest or ""
	disc.Text = icon
	local scale = card:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = if UiTokens.reducedMotion() then 1 else 0.75
		TweenService:Create(
			scale,
			UiTokens.motion(TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)),
			{ Scale = 1 }
		):Play()
	end
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
				"ZEN ACHIEVED!\n+%d coins   %s\nYour hammer glows while you stay Zen.",
				if typeof(bonus) == "number" then bonus else 0,
				if StressRules.zenBonusIsMax(level)
					then string.format(
						"Zen bonus +%d%% boss coins (max)",
						StressRules.zenBonusPercent(level)
					)
					else string.format(
						"Zen bonus now +%d%% boss coins",
						StressRules.zenBonusPercent(level)
					)
			),
			"🧘"
		)
	else
		UIController.showToast(string.format("%s reached Zen!", name))
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
		showCard(card, table.concat(lines, "\n"), "🛡️")
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
	local eventDrop = data.EventDropText
	if typeof(eventDrop) == "string" and #eventDrop <= 160 then
		table.insert(lines, "EVENT DROP: " .. eventDrop .. ", in your Bag!")
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
	showCard(card, table.concat(lines, "\n"), if data.LastHit == true then "🏆" else "🎉")
end

-- Shows a short tip; a newer tip replaces the current one. No-op before the HUD exists.
-- Shows a boss's short line to this player only, in its speech bubble
-- (BossVisualController). Skipped while the boss is shouting.
function UIController.showBossLine(model: Model, text: string): ()
	local show = localLineShowers[model]
	if show then
		show(text)
	end
end

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
