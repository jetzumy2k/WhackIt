--!strict
--[[
	The Lucky Capsule Machine on the client (docs/CAPSULE.md).

	  * Window (the machine at the Recreation Center, or 🏢 Social): the
	    price, spins left today, the lucky last spin, a big SPIN button, a
	    capsule that wobbles, spins and pops open to show the prize in its
	    tier's colour, and every prize's odds (normal and lucky spin).
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

	-- The reveal: a capsule that wobbles and pops open.
	local capsule: TextLabel? = nil
	local prizeLabel: TextLabel? = nil

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

		local machine = PanelKit.section(content, "🎁 Spin for a prize", false, true)
		PanelKit.text(
			machine.Body,
			string.format(
				"💰 %d coins a spin · %d of %d spins left today",
				CapsuleConfig.Cost,
				left,
				CapsuleConfig.DailySpins
			),
			"Heading"
		)
		PanelKit.text(
			machine.Body,
			if lucky
				then "🍀 Your next spin is today's LUCKY spin: Rare or better guaranteed!"
				else "🍀 The last spin of each day is guaranteed Rare or better.",
			"Muted"
		)

		local box = Instance.new("Frame")
		box.Name = "Stage"
		box.LayoutOrder = 10
		box.Size = UDim2.new(1, 0, 0, 120)
		box.BackgroundColor3 = C.Field
		box.Parent = machine.Body
		Instance.new("UICorner").Parent = box
		local ball = Instance.new("TextLabel")
		ball.Name = "Capsule"
		ball.AnchorPoint = Vector2.new(0.5, 0.5)
		ball.Position = UDim2.fromScale(0.5, 0.42)
		ball.Size = UDim2.fromOffset(70, 70)
		ball.BackgroundColor3 = ACCENT
		ball.Text = "❔"
		ball.TextScaled = true
		ball.Font = Enum.Font.FredokaOne
		ball.TextColor3 = Color3.new(1, 1, 1)
		ball.Parent = box
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = ball
		local ring = Instance.new("UIStroke")
		ring.Color = Color3.new(1, 1, 1)
		ring.Thickness = 3
		ring.Transparency = 0.3
		ring.Parent = ball
		local label = Instance.new("TextLabel")
		label.Name = "Prize"
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.new(0.5, 0, 1, -6)
		label.Size = UDim2.new(1, -16, 0, 24)
		label.BackgroundTransparency = 1
		label.Font = PanelKit.FONT_BOLD
		label.TextColor3 = C.Text
		label.Text = ""
		label.TextScaled = true
		label.Parent = box
		capsule, prizeLabel = ball, label

		local row = PanelKit.row(machine.Body)
		local spin = PanelKit.button(
			row,
			string.format("🎁 SPIN! (%d 💰)", CapsuleConfig.Cost),
			if lucky then Color3.fromRGB(255, 190, 60) else C.Good
		)
		spin.Size = UDim2.fromScale(1, 1)
		local level = if snapshot then LevelRules.levelFor(snapshot.Xp) else 0
		local coins = if snapshot then snapshot.Coins else 0
		local ok, reason = CapsuleRules.canSpin(level, coins, state, dayKey)
		PanelKit.setDisabled(spin, not ok or spinning)
		spin.Activated:Connect(function()
			if spinning then
				return
			end
			spinning = true
			PanelKit.setDisabled(spin, true)
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
				spinning = false -- never stuck if no answer comes
			end)
		end)
		if not ok and reason then
			PanelKit.text(machine.Body, reason, "Muted")
		end

		for _, isLucky in { false, true } do
			local odds = PanelKit.section(
				content,
				if isLucky then "🍀 Lucky spin odds" else "📊 Prize odds (every spin)",
				true,
				not isLucky
			)
			for _, entry in CapsuleRules.odds(isLucky) do
				local line = PanelKit.text(
					odds.Body,
					string.format(
						"%s %s · %s · %.1f%%",
						entry.Prize.Icon,
						entry.Prize.Label,
						entry.Prize.Tier,
						entry.Percent
					)
				)
				line.TextColor3 = tierColor(entry.Prize.Tier)
			end
		end
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
						Size = UDim2.fromOffset(84, 84),
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
