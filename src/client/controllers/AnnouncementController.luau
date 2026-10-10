--!strict
--[[
	Notification card (2026-10-08, docs/ADMIN.md "Announce", docs/EVENTS.md):
	  * Notify.Announcement: an admin's message to everyone in this server;
	  * Events.Notice: an event started or ended;
	  * local cards from other controllers (show(), e.g. "Egg hatched!"), which
	    may carry one action button next to OK.
	An announcement may carry its own title (e.g. "🥚 NEW EGG FOUND!").

	One card, top-centre under the HUD lines: it never covers the middle of
	the screen, eases in, closes itself after its time (or with OK), and
	queues the next one so several at once don't stack up. Text is shown as
	plain text (RichText off) and server payloads are re-checked here so a
	malformed one can't break the UI. Display only.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Responsive = require(script.Parent.Parent.Lib.Responsive)
local HudFormat = require(script.Parent.Parent.Lib.HudFormat)
local UiTokens = require(script.Parent.Parent.Lib.UiTokens)

local AnnouncementController = {}

local ANNOUNCE_COLOR = Color3.fromRGB(255, 200, 70)
local EVENT_START_COLOR = Color3.fromRGB(120, 220, 140)
local EVENT_END_COLOR = Color3.fromRGB(170, 176, 198)
local CARD_COLOR = Color3.fromRGB(26, 29, 41)
local TEXT_COLOR = Color3.fromRGB(240, 242, 248)
local MUTED_COLOR = Color3.fromRGB(170, 176, 198)
local MAX_TEXT_LENGTH = 300
local MIN_SECONDS, MAX_SECONDS = 3, 60
local EVENT_NOTICE_SECONDS = 6
-- Waiting cards beyond this are dropped (oldest kept), so a burst can't pile up.
local MAX_QUEUE = 4
local SHOW_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local ICON_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local RAYS = 10
local HIDE_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

type Card = {
	Title: string,
	Body: string,
	Detail: string?,
	Accent: Color3,
	Seconds: number,
	ActionLabel: string?, -- an extra button, e.g. "EQUIP"
	OnAction: (() -> ())?,
	-- The icon in the disc at the top; by default the emoji the title starts
	-- with (taken off the title), else none.
	Icon: string?,
	-- A reward or a win: a slow sunburst behind the icon (not with Reduced motion).
	Celebrate: boolean?,
}

export type CardSpec = Card

local queue: { Card } = {}
-- The icon disc, its rays and the countdown bar (set by build()).
type Parts = {
	IconHolder: Frame,
	Disc: TextLabel,
	DiscScale: UIScale,
	Rays: Frame,
	TimerFill: Frame,
}
local parts: Parts? = nil

local showing = false
local showCard: (card: Card) -> ()

local function text(value: unknown): string?
	if typeof(value) ~= "string" or #value == 0 or #value > MAX_TEXT_LENGTH then
		return nil
	end
	return if utf8.len(value) ~= nil then value else nil
end

local running = false

local function enqueue(card: Card): ()
	if running and not showing then
		showCard(card)
	elseif #queue < MAX_QUEUE then
		table.insert(queue, card)
	end
end

local function build(): (
	Frame,
	TextLabel,
	TextLabel,
	TextLabel,
	TextButton,
	TextButton,
	UIStroke,
	UIScale
)
	local gui = Instance.new("ScreenGui")
	gui.Name = "Announcements"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Above the Player / Admin panels (5, 6) so a message is never hidden.
	gui.DisplayOrder = 8

	local frame = Instance.new("Frame")
	frame.Name = "Card"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.BackgroundColor3 = CARD_COLOR
	frame.BackgroundTransparency = 0.03
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Visible = false
	frame.Parent = gui
	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = UDim.new(0, UiTokens.Radius.Window)
	frameCorner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = frame
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(240, 0)
	limit.MaxSize = Vector2.new(560, math.huge)
	limit.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = frame

	-- The icon disc (layout order 0) with a sunburst of rays behind it.
	local iconHolder = Instance.new("Frame")
	iconHolder.Name = "IconHolder"
	iconHolder.LayoutOrder = 0
	iconHolder.BackgroundTransparency = 1
	iconHolder.Size = UDim2.fromOffset(64, 64)
	iconHolder.Parent = frame
	local rays = Instance.new("Frame")
	rays.Name = "Rays"
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromScale(0.5, 0.5)
	rays.Size = UDim2.fromOffset(120, 120)
	rays.BackgroundTransparency = 1
	rays.Parent = iconHolder
	for index = 1, RAYS do
		local ray = Instance.new("Frame")
		ray.Name = "Ray"
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.new(1, 0, 0, 10)
		ray.Rotation = (index - 1) * 180 / RAYS
		ray.BorderSizePixel = 0
		ray.BackgroundColor3 = Color3.new(1, 1, 1)
		ray.Parent = rays
		local fade = Instance.new("UIGradient")
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = ray
	end
	local disc = Instance.new("TextLabel")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromOffset(56, 56)
	disc.Font = Enum.Font.FredokaOne
	disc.TextSize = 32
	disc.TextColor3 = TEXT_COLOR
	disc.ZIndex = 2
	disc.Parent = iconHolder
	local discCorner = Instance.new("UICorner")
	discCorner.CornerRadius = UDim.new(1, 0)
	discCorner.Parent = disc
	local discStroke = Instance.new("UIStroke")
	discStroke.Color = Color3.new(1, 1, 1)
	discStroke.Transparency = 0.5
	discStroke.Thickness = 2
	discStroke.Parent = disc
	local discScale = Instance.new("UIScale")
	discScale.Parent = disc

	local function line(name: string, order: number): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.LayoutOrder = order
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 0)
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.Font = Enum.Font.GothamMedium
		label.TextColor3 = TEXT_COLOR
		label.TextWrapped = true
		label.RichText = false
		label.Parent = frame
		return label
	end
	local title = line("Title", 1)
	title.Font = Enum.Font.FredokaOne
	local body = line("Body", 2)
	local detail = line("Detail", 3)
	detail.TextColor3 = MUTED_COLOR

	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.LayoutOrder = 4
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, 0, 0, 40)
	buttons.Parent = frame
	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	buttonLayout.Padding = UDim.new(0, 10)
	buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buttonLayout.Parent = buttons

	local action = Instance.new("TextButton")
	action.Name = "Action"
	action.LayoutOrder = 1
	action.Size = UDim2.fromOffset(120, 40)
	action.Font = Enum.Font.FredokaOne
	action.TextColor3 = TEXT_COLOR
	action.TextSize = 20
	action.BackgroundColor3 = Color3.fromRGB(70, 175, 95)
	action.AutoButtonColor = true
	action.Visible = false
	action.Parent = buttons
	Instance.new("UICorner").Parent = action

	local ok = Instance.new("TextButton")
	ok.Name = "Ok"
	ok.LayoutOrder = 2
	ok.Size = UDim2.fromOffset(110, 40)
	ok.Font = Enum.Font.FredokaOne
	ok.Text = "OK"
	ok.TextColor3 = TEXT_COLOR
	ok.TextSize = 20
	ok.BackgroundColor3 = Color3.fromRGB(78, 84, 108)
	ok.AutoButtonColor = true
	ok.Parent = buttons
	Instance.new("UICorner").Parent = ok

	-- How long until the card closes by itself: a thin bar that runs down.
	local timer = Instance.new("Frame")
	timer.Name = "Timer"
	timer.LayoutOrder = 5
	timer.BackgroundTransparency = 1
	timer.Size = UDim2.new(1, 0, 0, 3)
	timer.Parent = frame
	local timerFill = Instance.new("Frame")
	timerFill.Name = "Fill"
	timerFill.BorderSizePixel = 0
	timerFill.Size = UDim2.fromScale(1, 1)
	timerFill.Parent = timer
	local timerCorner = Instance.new("UICorner")
	timerCorner.CornerRadius = UDim.new(1, 0)
	timerCorner.Parent = timerFill

	-- Under the Stress Meter and HUD lines; wider and smaller text on phones.
	Responsive.onChanged(function()
		local phone = Responsive.formFactor() == "Phone"
		local viewport = Responsive.viewport()
		local portrait = viewport.Y > viewport.X
		frame.Position = UDim2.new(0.5, 0, 0, if phone and not portrait then 56 else 104)
		frame.Size = UDim2.fromScale(if phone then 0.62 else 0.42, 0)
		if phone and portrait then
			frame.Size = UDim2.fromScale(0.92, 0)
		end
		title.TextSize = if phone then 20 else 24
		body.TextSize = if phone then 16 else 19
		detail.TextSize = if phone then 14 else 16
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	parts = {
		IconHolder = iconHolder,
		Disc = disc,
		DiscScale = discScale,
		Rays = rays,
		TimerFill = timerFill,
	}
	return frame, title, body, detail, ok, action, stroke, scale
end

-- Shows a card made on this client (queued like the server's).
function AnnouncementController.show(card: CardSpec): ()
	enqueue(card)
end

function AnnouncementController.start(): ()
	local frame, title, body, detail, ok, action, stroke, scale = build()
	local token = 0
	local onAction: (() -> ())? = nil
	running = true
	-- The sunburst's spin while a celebrating card shows.
	local spin: RBXScriptConnection? = nil

	local function hide(expected: number): ()
		if token ~= expected or not frame.Visible then
			return
		end
		local tween = TweenService:Create(scale, UiTokens.motion(HIDE_TWEEN), { Scale = 0.85 })
		tween.Completed:Connect(function()
			if token ~= expected then
				return
			end
			frame.Visible = false
			showing = false
			if spin then
				spin:Disconnect()
				spin = nil
			end
			local nextCard = table.remove(queue, 1)
			if nextCard then
				showCard(nextCard)
			end
		end)
		tween:Play()
	end

	function showCard(card: Card): ()
		showing = true
		token += 1
		local current = token
		local icon, plainTitle = HudFormat.splitIcon(card.Title)
		icon = card.Icon or icon
		title.Text = plainTitle
		title.TextColor3 = card.Accent
		local look = parts :: Parts
		look.IconHolder.Visible = icon ~= nil
		look.Disc.Text = icon or ""
		look.Disc.BackgroundColor3 = card.Accent:Lerp(Color3.new(0, 0, 0), 0.25)
		local reduced = UiTokens.reducedMotion()
		look.Rays.Visible = card.Celebrate == true and icon ~= nil and not reduced
		for _, ray in look.Rays:GetChildren() do
			if ray:IsA("Frame") then
				ray.BackgroundColor3 = card.Accent
			end
		end
		if spin then
			spin:Disconnect()
			spin = nil
		end
		if look.Rays.Visible then
			spin = RunService.RenderStepped:Connect(function(dt: number)
				look.Rays.Rotation = (look.Rays.Rotation + dt * 25) % 360
			end)
		end
		look.DiscScale.Scale = if reduced then 1 else 0.2
		TweenService:Create(look.DiscScale, UiTokens.motion(ICON_TWEEN), { Scale = 1 }):Play()
		look.TimerFill.BackgroundColor3 = card.Accent
		look.TimerFill.Size = UDim2.fromScale(1, 1)
		TweenService:Create(look.TimerFill, TweenInfo.new(card.Seconds, Enum.EasingStyle.Linear), {
			Size = UDim2.fromScale(0, 1),
		}):Play()
		stroke.Color = card.Accent
		body.Text = card.Body
		detail.Text = card.Detail or ""
		detail.Visible = card.Detail ~= nil
		onAction = card.OnAction
		action.Text = card.ActionLabel or ""
		action.Visible = card.ActionLabel ~= nil and card.OnAction ~= nil
		scale.Scale = if reduced then 1 else 0.7
		frame.Visible = true
		TweenService:Create(scale, UiTokens.motion(SHOW_TWEEN), { Scale = 1 }):Play()
		task.delay(card.Seconds, hide, current)
	end

	ok.Activated:Connect(function()
		hide(token)
	end)
	action.Activated:Connect(function()
		local callback = onAction
		onAction = nil
		if callback then
			callback()
		end
		hide(token)
	end)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local announcement = remotes:WaitForChild("Notify"):WaitForChild("Announcement")
	local notice = remotes:WaitForChild("Events"):WaitForChild("Notice")
	assert(
		announcement:IsA("RemoteEvent") and notice:IsA("RemoteEvent"),
		"Notify.Announcement and Events.Notice must be RemoteEvents"
	)

	announcement.OnClientEvent:Connect(function(payload: unknown)
		if typeof(payload) ~= "table" then
			return
		end
		local data = payload :: { [string]: unknown }
		local message = text(data.Text)
		if message == nil then
			return
		end
		local seconds = if typeof(data.Seconds) == "number" then data.Seconds else 10
		local customTitle = data.Title
		enqueue({
			Title = if typeof(customTitle) == "string" and #customTitle <= 60
				then customTitle
				else "📢 ANNOUNCEMENT",
			Body = message,
			Accent = ANNOUNCE_COLOR,
			Seconds = math.clamp(seconds, MIN_SECONDS, MAX_SECONDS),
		})
	end)

	notice.OnClientEvent:Connect(function(payload: unknown)
		if typeof(payload) ~= "table" then
			return
		end
		local data = payload :: { [string]: unknown }
		local name = text(data.Name)
		if name == nil or (data.Kind ~= "Started" and data.Kind ~= "Ended") then
			return
		end
		local started = data.Kind == "Started"
		local summary = text(data.Summary)
		enqueue({
			Title = if started then "🎉 EVENT STARTED!" else "EVENT ENDED",
			Body = if started then name else name .. " has ended.",
			Detail = if started then summary else nil,
			Accent = if started then EVENT_START_COLOR else EVENT_END_COLOR,
			Seconds = EVENT_NOTICE_SECONDS,
		})
	end)

	-- Cards shown before this started.
	local first = table.remove(queue, 1)
	if first and not showing then
		showCard(first)
	end
end

return AnnouncementController
