--!strict
--[[
	The Lucky Capsule Machine on the client (docs/CAPSULE.md).

	  * Window (the machine at the Recreation Center, or 🏢 Social): a
	    capsule that wobbles, spins and pops open to show the prize in its
	    tier's colour (the last prize stays on show), one dot per daily spin
	    (the lucky last one gold) with the reset countdown, a big SPIN button
	    that says why when it can't spin, and an odds table with a switch
	    between the normal and the lucky spin.
	  * The machine's handle turns on your screen when you spin.
	  * Rare and better prizes also get a celebration card.
	The server takes the coins and picks the prize (CapsuleService); this
	only asks and shows.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CapsuleConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("CapsuleConfig"))
local CapsuleRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CapsuleRules"))
local LevelRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LevelRules"))
local QuestRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("QuestRules"))

local AnnouncementController = require(script.Parent.AnnouncementController)
local PanelKit = require(script.Parent.Parent.Lib.PanelKit)
local ProgressController = require(script.Parent.ProgressController)
local UiTokens = require(script.Parent.Parent.Lib.UiTokens)

local CapsuleController = {}

local C = PanelKit.Colors
local ACCENT = Color3.fromRGB(255, 120, 150)
local REVEAL_SECONDS = 1.3

local localPlayer = Players.LocalPlayer
local openWindow: (() -> ())? = nil
local spinning = false

local function remote(name: string): RemoteEvent
	local found =
		ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Capsule"):WaitForChild(name)
	assert(found:IsA("RemoteEvent"), "Capsule." .. name .. " must be a RemoteEvent")
	return found
end

local function text(value: unknown): string
	return if typeof(value) == "string" then value else ""
end

local function tierColor(tier: string): Color3
	local info = CapsuleConfig.Tiers[tier]
	return if info then info.Color else C.Muted
end

-- Turns the machine's handle round once (on this screen only).
local function turnHandle(): ()
	local center = Workspace:FindFirstChild("RecreationCenter")
	local machine = if center then center:FindFirstChild("LuckyCapsule") else nil
	local handle = if machine then machine:FindFirstChild("CapsuleHandle") else nil
	if handle == nil or not handle:IsA("BasePart") or UiTokens.reducedMotion() then
		return
	end
	local rest = handle.CFrame
	local turn = TweenService:Create(
		handle,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true),
		{ CFrame = rest * CFrame.Angles(0, 0, math.rad(160)) }
	)
	turn:Play()
end

function CapsuleController.open(): ()
	local opener = openWindow
	if opener then
		opener()
	end
end

local function buildWindow(parent: Instance): ()
	local window = PanelKit.window({
		Name = "LuckyCapsule",
		Title = "🎁 Lucky Capsule Machine",
		Subtitle = "Every spin wins a prize. Coins only, odds shown below.",
		Accent = ACCENT,
		DisplayOrder = 6,
	}, parent)
	local content = window.Content

	-- The reveal: a capsule that wobbles and pops open. The last prize stays
	-- on show until the next spin (the page is rebuilt after each reveal).
	local capsule: TextLabel? = nil
	local prizeLabel: TextLabel? = nil
	local lastPrize: { Icon: string, Label: string, Tier: string }? = nil
	local showLuckyOdds = false

	local function corner(object: Instance, radius: number): ()
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, radius)
		c.Parent = object
	end

	-- "5h 12m" until the daily spins reset (midnight UTC).
	local function resetText(): string
		local seconds = 86400 - os.time() % 86400
		local hours = seconds // 3600
		local minutes = (seconds % 3600) // 60
		return if hours > 0
			then string.format("%dh %dm", hours, minutes)
			else string.format("%dm", math.max(1, minutes))
	end

	-- The spin button's caption when it can't be pressed.
	local function blockedCaption(level: number, coins: number, left: number): string
		if level < CapsuleConfig.MinLevel then
			return string.format("🔒 Reach Level %d", CapsuleConfig.MinLevel)
		elseif left <= 0 then
			return "⏳ No spins left · resets in " .. resetText()
		elseif coins < CapsuleConfig.Cost then
			return string.format("💰 Need %d coins", CapsuleConfig.Cost)
		end
		return "..."
	end

	local function stage(holder: Instance): ()
		local box = Instance.new("Frame")
		box.Name = "Stage"
		box.LayoutOrder = 1
		box.Size = UDim2.new(1, 0, 0, 176)
		box.BackgroundColor3 = C.Field
		box.Parent = holder
		corner(box, UiTokens.Radius.Card)
		local glow = Instance.new("UIGradient")
		glow.Rotation = 90
		local tint = if lastPrize then tierColor(lastPrize.Tier) else ACCENT
		glow.Color = ColorSequence.new(tint:Lerp(C.Field, 0.7), C.Field)
		glow.Parent = box

		local ball = Instance.new("TextLabel")
		ball.Name = "Capsule"
		ball.AnchorPoint = Vector2.new(0.5, 0.5)
		ball.Position = UDim2.fromScale(0.5, 0.42)
		ball.Size = UDim2.fromOffset(92, 92)
		ball.BackgroundColor3 = tint
		ball.Text = if lastPrize then lastPrize.Icon else "?"
		ball.TextScaled = true
		ball.Font = UiTokens.Font.Title
		ball.TextColor3 = Color3.new(1, 1, 1)
		ball.Parent = box
		corner(ball, 999)
		local ballPad = Instance.new("UIPadding")
		ballPad.PaddingTop = UDim.new(0, 16)
		ballPad.PaddingBottom = UDim.new(0, 16)
		ballPad.PaddingLeft = UDim.new(0, 16)
		ballPad.PaddingRight = UDim.new(0, 16)
		ballPad.Parent = ball
		local shine = Instance.new("UIGradient")
		shine.Rotation = 90
		shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 210))
		shine.Parent = ball
		local ring = Instance.new("UIStroke")
		ring.Color = Color3.new(1, 1, 1)
		ring.Thickness = 3
		ring.Transparency = 0.25
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ring.Parent = ball

		local label = Instance.new("TextLabel")
		label.Name = "Prize"
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.new(0.5, 0, 1, -10)
		label.Size = UDim2.new(1, -24, 0, 26)
		label.BackgroundTransparency = 1
		label.Font = PanelKit.FONT_BOLD
		label.TextColor3 = if lastPrize then tint else C.Muted
		label.Text = if lastPrize
			then string.format("%s · %s", lastPrize.Tier:upper(), lastPrize.Label)
			else "Spin to open a capsule!"
		label.Parent = box
		PanelKit.setTextSize(label, 20)
		capsule, prizeLabel = ball, label
	end

	-- One dot per daily spin: filled = still to spin; the last (lucky) one gold.
	local function spinPips(holder: Instance, left: number): ()
		local row = Instance.new("Frame")
		row.Name = "Spins"
		row.LayoutOrder = 2
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 30)
		row.Parent = holder
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 6)
		layout.Parent = row
		local caption = Instance.new("TextLabel")
		caption.LayoutOrder = 0
		caption.BackgroundTransparency = 1
		caption.AutomaticSize = Enum.AutomaticSize.X
		caption.Size = UDim2.fromOffset(0, 30)
		caption.Font = PanelKit.FONT_BOLD
		caption.TextSize = 16
		caption.TextColor3 = C.Text
		caption.Text = string.format("%d / %d spins left  ", left, CapsuleConfig.DailySpins)
		caption.Parent = row
		local used = CapsuleConfig.DailySpins - left
		for index = 1, CapsuleConfig.DailySpins do
			local dot = Instance.new("Frame")
			dot.LayoutOrder = index
			dot.Size = UDim2.fromOffset(14, 14)
			local lucky = index == CapsuleConfig.DailySpins
			local spent = index <= used
			dot.BackgroundColor3 = if spent
				then C.Disabled
				elseif lucky then UiTokens.Color.Gold
				else ACCENT
			dot.Parent = row
			corner(dot, 7)
		end
		local timer = Instance.new("TextLabel")
		timer.LayoutOrder = CapsuleConfig.DailySpins + 1
		timer.BackgroundTransparency = 1
		timer.AutomaticSize = Enum.AutomaticSize.X
		timer.Size = UDim2.fromOffset(0, 30)
		timer.Font = PanelKit.FONT
		timer.TextSize = 14
		timer.TextColor3 = C.Muted
		timer.Text = "   🕒 resets in " .. resetText()
		timer.Parent = row
	end

	-- A table of prizes: icon and name, a tier pill, and the chance with a bar.
	local function oddsTable(holder: Instance, lucky: boolean): ()
		local best = 0
		local entries = CapsuleRules.odds(lucky)
		for _, entry in entries do
			best = math.max(best, entry.Percent)
		end
		for _, entry in entries do
			local color = tierColor(entry.Prize.Tier)
			local row = Instance.new("Frame")
			row.Name = "Odds"
			row.LayoutOrder = #holder:GetChildren()
			row.Size = UDim2.new(1, 0, 0, 38)
			row.BackgroundColor3 = C.Field
			row.BackgroundTransparency = 0.4
			row.Parent = holder
			corner(row, UiTokens.Radius.Button)
			local name = Instance.new("TextLabel")
			name.BackgroundTransparency = 1
			name.Position = UDim2.fromOffset(12, 0)
			name.Size = UDim2.new(1, -240, 1, 0)
			name.Font = PanelKit.FONT
			name.TextColor3 = C.Text
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.Text = entry.Prize.Icon .. "  " .. entry.Prize.Label
			name.Parent = row
			PanelKit.setTextSize(name, 16)
			local pill = Instance.new("TextLabel")
			pill.AnchorPoint = Vector2.new(1, 0.5)
			pill.Position = UDim2.new(1, -132, 0.5, 0)
			pill.Size = UDim2.fromOffset(92, 24)
			pill.BackgroundColor3 = color
			pill.BackgroundTransparency = 0.15
			pill.Font = PanelKit.FONT_BOLD
			pill.TextSize = 13
			pill.TextColor3 = UiTokens.textOn(color)
			pill.Text = entry.Prize.Tier
			pill.Parent = row
			corner(pill, 12)
			local bar = Instance.new("Frame")
			bar.AnchorPoint = Vector2.new(1, 0.5)
			bar.Position = UDim2.new(1, -60, 0.5, 0)
			bar.Size = UDim2.fromOffset(60, 6)
			bar.BackgroundColor3 = C.Window
			bar.Parent = row
			corner(bar, 3)
			local fill = Instance.new("Frame")
			fill.Size = UDim2.fromScale(if best > 0 then entry.Percent / best else 0, 1)
			fill.BackgroundColor3 = color
			fill.Parent = bar
			corner(fill, 3)
			local percent = Instance.new("TextLabel")
			percent.AnchorPoint = Vector2.new(1, 0.5)
			percent.Position = UDim2.new(1, -8, 0.5, 0)
			percent.Size = UDim2.fromOffset(48, 24)
			percent.BackgroundTransparency = 1
			percent.Font = PanelKit.FONT_BOLD
			percent.TextSize = 15
			percent.TextColor3 = C.Text
			percent.TextXAlignment = Enum.TextXAlignment.Right
			percent.Text = string.format("%.1f%%", entry.Percent)
			percent.Parent = row
		end
	end

	local function render(): ()
		if not window:isOpen() then
			return
		end
		window:clear()
		local snapshot = ProgressController.get()
		local dayKey = QuestRules.dayKey(os.time())
		local state = if snapshot then snapshot.Capsule else CapsuleRules.defaultState()
		local left = CapsuleRules.spinsLeft(state, dayKey)
		local lucky = CapsuleRules.nextIsLucky(state, dayKey)
		local level = if snapshot then LevelRules.levelFor(snapshot.Xp) else 0
		local coins = if snapshot then snapshot.Coins else 0
		local ok = CapsuleRules.canSpin(level, coins, state, dayKey)

		local machine = PanelKit.section(content, "🎁 Spin for a prize", false, true)
		stage(machine.Body)
		spinPips(machine.Body, left)

		local spin = PanelKit.button(
			machine.Body,
			if ok
				then string.format("🎁 SPIN  ·  %d coins", CapsuleConfig.Cost)
				else blockedCaption(level, coins, left),
			if lucky then UiTokens.Color.Gold else C.Good
		)
		spin.Name = "Spin"
		spin.LayoutOrder = 3
		spin.Size = UDim2.new(1, 0, 0, 56)
		PanelKit.setTextSize(spin, 22)
		PanelKit.setDisabled(spin, not ok or spinning)
		spin.Activated:Connect(function()
			if spinning or not spin.Active then
				return
			end
			spinning = true
			PanelKit.setDisabled(spin, true)
			spin.Text = "🎲 Spinning..."
			remote("Spin"):FireServer()
			turnHandle()
			-- Wobble while the server answers.
			if capsule and not UiTokens.reducedMotion() then
				TweenService
					:Create(
						capsule,
						TweenInfo.new(
							0.12,
							Enum.EasingStyle.Sine,
							Enum.EasingDirection.InOut,
							6,
							true
						),
						{ Rotation = 18 }
					)
					:Play()
			end
			task.delay(4, function()
				if spinning then
					spinning = false -- never stuck if no answer comes
					render()
				end
			end)
		end)
		local luckyLine = PanelKit.text(
			machine.Body,
			if lucky
				then "🍀 This is today's LUCKY spin: Rare or better guaranteed!"
				else "🍀 The last spin of each day is guaranteed Rare or better.",
			if lucky then "Heading" else "Muted"
		)
		luckyLine.LayoutOrder = 4
		luckyLine.TextXAlignment = Enum.TextXAlignment.Center

		-- Odds: one table, with a switch between the normal and the lucky spin.
		local odds = PanelKit.section(content, "📊 Prize odds", false, true)
		local switch = PanelKit.row(odds.Body, 40)
		local options: { { Lucky: boolean, Label: string } } = {
			{ Lucky = false, Label = "Every spin" },
			{ Lucky = true, Label = "🍀 Lucky spin" },
		}
		for _, option in options do
			local isLucky = option.Lucky
			local tab = PanelKit.button(
				switch,
				option.Label,
				if showLuckyOdds == isLucky then ACCENT else C.Field
			)
			tab.Size = UDim2.new(0.5, -4, 1, 0)
			tab.Activated:Connect(function()
				if showLuckyOdds ~= isLucky then
					showLuckyOdds = isLucky
					render()
				end
			end)
		end
		oddsTable(odds.Body, showLuckyOdds)

		local rules = PanelKit.section(content, "📜 Fair play", true, false)
		for _, line in
			{
				"No bets: a spin always costs the same and always wins a prize.",
				"Coins only. Coins can't be bought, and the machine never takes Robux.",
				string.format(
					"%d spins a day (UTC). The last one only gives Rare, Epic or Jackpot prizes.",
					CapsuleConfig.DailySpins
				),
				"Boosts and eggs go to your 🎒 Bag; office supplies to your office storage.",
			}
		do
			PanelKit.text(rules.Body, "• " .. line, "Muted")
		end
	end

	-- The prize pops out of the capsule.
	local function reveal(payload: { [string]: unknown }): ()
		local tier = text(payload.Tier)
		local color = tierColor(tier)
		lastPrize = { Icon = text(payload.Icon), Label = text(payload.Label), Tier = tier }
		local ball, label = capsule, prizeLabel
		if ball and label and window:isOpen() then
			ball.Rotation = 0
			local quick = UiTokens.reducedMotion()
			if not quick then
				TweenService
					:Create(
						ball,
						TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.In),
						{
							Size = UDim2.fromOffset(20, 20),
						}
					)
					:Play()
			end
			task.delay(if quick then 0 else 0.5, function()
				ball.BackgroundColor3 = color
				ball.Text = text(payload.Icon)
				ball.Size = UDim2.fromOffset(20, 20)
				TweenService:Create(
					ball,
					TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{
						Size = UDim2.fromOffset(92, 92),
					}
				):Play()
				label.Text = string.format("%s · %s", tier:upper(), text(payload.Label))
				label.TextColor3 = color
			end)
		end
		local order = (CapsuleConfig.Tiers[tier] or { Order = 1 }).Order
		task.delay(REVEAL_SECONDS, function()
			spinning = false
			local detail = text(payload.Detail)
			if order >= 3 or not window:isOpen() then
				AnnouncementController.show({
					Title = (if tier == "Jackpot"
						then "🎉 JACKPOT!"
						else "🎁 " .. tier:upper() .. " PRIZE!"),
					Body = text(payload.Label),
					Detail = if detail ~= "" then detail else nil,
					Accent = color,
					Celebrate = order >= 3,
					Seconds = 5,
				})
			end
			render()
		end)
	end

	window:onOpen(function()
		task.defer(render)
	end)
	ProgressController.Changed:Connect(function()
		if window:isOpen() and not spinning then
			render()
		end
	end)
	remote("Result").OnClientEvent:Connect(function(payload: unknown)
		if typeof(payload) == "table" then
			reveal(payload :: { [string]: unknown })
		end
	end)
	openWindow = function()
		window:open()
		render()
	end
end

function CapsuleController.start(): ()
	buildWindow(localPlayer:WaitForChild("PlayerGui"))
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name == "CapsulePrompt" then
			CapsuleController.open()
		end
	end)
end

return CapsuleController
