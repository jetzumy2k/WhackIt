--!strict
--[[
	A small UI kit for the game's big panels (Admin, Player): one window shell
	plus the pieces pages are built from, so both panels look and behave alike.

	Window (PanelKit.window):
	  * header with title, subtitle and a close X; a coloured accent strip;
	  * navigation: a sidebar on wide windows, a scrollable tab strip on top
	    when the window is narrow (phones, small windows);
	  * a scrolling content area (UIListLayout + UIPadding, AutomaticCanvasSize),
	    so content never shrinks to fit: it scrolls;
	  * sized by scale with min/max limits, re-fitted when the screen changes;
	  * quick open/close animation (UIScale 0.94 <-> 1, ~0.12 s);
	  * optional keyboard shortcut (ignored while typing in a text box).
	Pieces: buttons (hover, press, selected and disabled states), collapsible
	section cards, rows, text, stat tiles, on/off switches, progress bars,
	empty / loading / error / locked notices, tooltips and a confirm dialog. Paragraph text uses fixed, readable
	sizes and wraps; button and row captions shrink to fit their box (never
	grow past their normal size, Lib/Responsive) instead of clipping.
	Short windows (phones in landscape) get a slimmer header and tab strip so
	more of the page shows.

	Colours, fonts and sizes come from Lib/UiTokens. Motion honours Reduced
	motion (UiTokens.motion): windows, dialogs and bars change instantly.
	Gamepad: every window and dialog is watched by Lib/GamepadNav (first
	control selected on open, B closes).

	Nothing here runs per frame: hover/press tweens only play on input, and
	layout only reacts to size changes.
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GamepadNav = require(script.Parent.GamepadNav)
local Responsive = require(script.Parent.Responsive)
local UiTokens = require(script.Parent.UiTokens)

local PanelKit = {}

PanelKit.Colors = UiTokens.Color
local C = PanelKit.Colors

PanelKit.FONT = UiTokens.Font.Body
PanelKit.FONT_BOLD = UiTokens.Font.Bold
PanelKit.TITLE_FONT = UiTokens.Font.Title
PanelKit.TEXT_SIZE = UiTokens.Text.Body
PanelKit.SMALL_SIZE = UiTokens.Text.Small
PanelKit.ROW_HEIGHT = UiTokens.Size.Row
local HEADER_HEIGHT = 64
local SHORT_HEADER_HEIGHT = 48
local SIDEBAR_WIDTH = 176
local TOPNAV_HEIGHT = 48
local SHORT_TOPNAV_HEIGHT = 42
local COMPACT_BELOW = 640 -- window width (px) under which the nav moves to the top
local SHORT_BELOW = 440 -- window height (px) under which the header and tabs slim down
local SMALL_SCREEN_BELOW = 900 -- screen width (px) under which the window fills more of it
local OPEN_SECONDS = UiTokens.Motion.Open

export type Tab = { Id: string, Label: string }

export type Window = {
	Gui: ScreenGui,
	Frame: Frame,
	Content: ScrollingFrame,
	Subtitle: TextLabel,
	isOpen: (self: Window) -> boolean,
	open: (self: Window) -> (),
	close: (self: Window) -> (),
	toggle: (self: Window) -> (),
	setTabs: (self: Window, tabs: { Tab }, onSelect: (id: string) -> ()) -> (),
	selectTab: (self: Window, id: string) -> (),
	clear: (self: Window) -> (),
	onOpen: (self: Window, callback: () -> ()) -> (),
}

-- An on/off switch row: `set` changes what it shows without calling onChange.
export type Toggle = {
	Frame: Frame,
	Button: TextButton,
	set: (value: boolean) -> (),
}

export type ProgressBar = {
	Frame: Frame,
	-- `fraction` is clamped to 0..1; `text` is drawn over the bar.
	set: (fraction: number, text: string) -> (),
}

export type NoticeKind = "Empty" | "Loading" | "Error" | "Locked"

export type ConfirmDialog = {
	Frame: Frame,
	-- Shows `message` with [Cancel] [confirmLabel]; `action` runs on confirm.
	ask: (message: string, confirmLabel: string?, action: () -> ()) -> (),
	hide: () -> (),
}

export type Section = {
	Frame: Frame,
	Body: Frame,
}

local function corner(parent: Instance, radius: number?): ()
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or UiTokens.Radius.Tile)
	c.Parent = parent
end

local function padding(parent: Instance, pixels: number): ()
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, pixels)
	p.PaddingRight = UDim.new(0, pixels)
	p.PaddingTop = UDim.new(0, pixels)
	p.PaddingBottom = UDim.new(0, pixels)
	p.Parent = parent
end

local function list(parent: Instance, gap: number, horizontal: boolean?): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	if horizontal then
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
	end
	layout.Parent = parent
	return layout
end

local function nextOrder(parent: Instance): number
	return #parent:GetChildren()
end

local function lighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

-- Text --------------------------------------------------------------------

-- Caption size for a button or one-line label: it shrinks to fit its box but
-- never grows past `size`.
-- `object` is a TextLabel or TextButton.
function PanelKit.setTextSize(object: GuiObject, size: number): ()
	(object :: TextLabel).TextSize = size
	Responsive.capText(object, size)
end

-- A text line that wraps and grows downward (never shrinks to fit).
function PanelKit.text(parent: Instance, content: string, kind: string?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = kind or "Text"
	label.LayoutOrder = nextOrder(parent)
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Font = if kind == "Heading" or kind == "Value" then PanelKit.FONT_BOLD else PanelKit.FONT
	-- Phones read slightly smaller text (Responsive.textScale), never below 12.
	label.TextSize = math.max(
		12,
		math.floor(
			(
				if kind == "Value"
					then 22
					elseif kind == "Muted" then PanelKit.SMALL_SIZE
					else PanelKit.TEXT_SIZE
			) * Responsive.textScale()
		)
	)
	label.TextColor3 = if kind == "Muted"
		then C.Muted
		elseif kind == "Heading" then C.Heading
		else C.Text
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Text = content
	label.Parent = parent
	return label
end

-- Buttons -----------------------------------------------------------------

-- Remembers a button's colour so hover / disabled can return to it.
function PanelKit.setColor(button: GuiButton, color: Color3): ()
	button:SetAttribute("BaseColor", color)
	if button.Active then
		button.BackgroundColor3 = color
	end
end

function PanelKit.setDisabled(button: GuiButton, disabled: boolean): ()
	button.Active = not disabled
	button.AutoButtonColor = false
	local base = button:GetAttribute("BaseColor")
	button.BackgroundColor3 = if disabled
		then C.Disabled
		elseif typeof(base) == "Color3" then base
		else C.Neutral
	if button:IsA("TextButton") then
		button.TextTransparency = if disabled then 0.45 else 0
	end
end

-- A rounded button with hover (brighter), press (slightly smaller), and
-- disabled states. `color` is its normal colour.
function PanelKit.button(parent: Instance, content: string, color: Color3?): TextButton
	local button = Instance.new("TextButton")
	button.Name = "Button"
	button.LayoutOrder = nextOrder(parent)
	button.Size = UDim2.new(1, 0, 0, PanelKit.ROW_HEIGHT)
	button.AutoButtonColor = false
	button.Font = PanelKit.FONT_BOLD
	button.TextColor3 = C.Text
	button.TextWrapped = true
	button.Text = content
	button.Parent = parent
	PanelKit.setTextSize(button, PanelKit.TEXT_SIZE)
	corner(button, UiTokens.Radius.Button)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	PanelKit.setColor(button, color or C.Neutral)

	local hoverInfo = TweenInfo.new(UiTokens.Motion.Hover)
	local function base(): Color3
		local value = button:GetAttribute("BaseColor")
		return if typeof(value) == "Color3" then value else C.Neutral
	end
	button.MouseEnter:Connect(function()
		if button.Active then
			TweenService:Create(button, hoverInfo, { BackgroundColor3 = lighten(base(), 0.15) })
				:Play()
		end
	end)
	button.MouseLeave:Connect(function()
		if button.Active then
			TweenService:Create(button, hoverInfo, { BackgroundColor3 = base() }):Play()
		end
		scale.Scale = 1
	end)
	button.MouseButton1Down:Connect(function()
		if button.Active then
			TweenService:Create(scale, hoverInfo, { Scale = 0.96 }):Play()
		end
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, hoverInfo, { Scale = 1 }):Play()
	end)
	return button
end

-- Layout pieces -----------------------------------------------------------

-- A horizontal row of controls (children size themselves by scale).
function PanelKit.row(parent: Instance, height: number?): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Row"
	frame.LayoutOrder = nextOrder(parent)
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, height or PanelKit.ROW_HEIGHT)
	frame.Parent = parent
	list(frame, 8, true)
	return frame
end

-- A card with a title. Collapsible cards toggle their body when the title is
-- clicked; `onToggle` hears the new expanded state (to remember it).
function PanelKit.section(
	parent: Instance,
	title: string,
	collapsible: boolean,
	expanded: boolean,
	onToggle: ((expanded: boolean) -> ())?
): Section
	local card = Instance.new("Frame")
	card.Name = "Section"
	card.LayoutOrder = nextOrder(parent)
	card.BackgroundColor3 = C.Card
	card.Size = UDim2.fromScale(1, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Parent = parent
	corner(card, UiTokens.Radius.Card)
	padding(card, UiTokens.Space.M)
	list(card, 10)

	local header: GuiObject
	if collapsible then
		local toggle = Instance.new("TextButton")
		toggle.BackgroundTransparency = 1
		toggle.AutoButtonColor = false
		header = toggle
	else
		header = Instance.new("TextLabel")
	end
	header.Name = "Title"
	header.LayoutOrder = 0
	header.Size = UDim2.new(1, 0, 0, 26)
	header.BackgroundTransparency = 1
	local headerText = header :: TextLabel
	headerText.Font = PanelKit.FONT_BOLD
	headerText.TextSize = math.floor(UiTokens.Text.Section * Responsive.textScale())
	headerText.TextColor3 = C.Heading
	headerText.TextXAlignment = Enum.TextXAlignment.Left
	headerText.TextTruncate = Enum.TextTruncate.AtEnd
	header.Parent = card

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.LayoutOrder = 1
	body.BackgroundTransparency = 1
	body.Size = UDim2.fromScale(1, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Parent = card
	list(body, 8)

	local function show(isExpanded: boolean): ()
		body.Visible = isExpanded
		headerText.Text = if collapsible
			then (if isExpanded then "v  " else ">  ") .. title
			else title
	end
	show(expanded or not collapsible)
	if collapsible then
		local isExpanded = expanded
		local toggle = header :: TextButton
		toggle.Activated:Connect(function()
			isExpanded = not isExpanded
			show(isExpanded)
			if onToggle then
				onToggle(isExpanded)
			end
		end)
	end
	return { Frame = card, Body = body }
end

-- A small tile: a label over a big value. Returns the value label to update.
function PanelKit.statTile(
	parent: Instance,
	labelText: string,
	value: string,
	accent: Color3?
): TextLabel
	local tile = Instance.new("Frame")
	tile.Name = "Stat"
	tile.LayoutOrder = nextOrder(parent)
	tile.BackgroundColor3 = C.Field
	tile.Parent = parent
	corner(tile, 10)
	padding(tile, 10)
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 18)
	name.Font = PanelKit.FONT
	name.TextSize = math.max(12, math.floor(PanelKit.SMALL_SIZE * Responsive.textScale()))
	name.TextColor3 = C.Muted
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = labelText
	name.Parent = tile
	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "Value"
	valueLabel.BackgroundTransparency = 1
	valueLabel.Position = UDim2.fromOffset(0, 22)
	valueLabel.Size = UDim2.new(1, 0, 1, -22)
	valueLabel.Font = PanelKit.FONT_BOLD
	PanelKit.setTextSize(valueLabel, 24)
	valueLabel.TextColor3 = accent or C.Text
	valueLabel.TextXAlignment = Enum.TextXAlignment.Left
	valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
	valueLabel.Text = value
	valueLabel.Parent = tile
	return valueLabel
end

-- A grid that fits as many `minWidth` cells per row as there is room for.
function PanelKit.grid(parent: Instance, minWidth: number, height: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Grid"
	frame.LayoutOrder = nextOrder(parent)
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Parent = parent
	local grid = Instance.new("UIGridLayout")
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.CellSize = UDim2.fromOffset(minWidth, height)
	grid.Parent = frame
	local function fit(): ()
		local width = frame.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local columns = math.max(1, math.floor((width + 8) / (minWidth + 8)))
		grid.CellSize = UDim2.new(1 / columns, -8 * (columns - 1) / columns, 0, height)
	end
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	task.defer(fit)
	return frame
end

-- An item card for grids (visual overhaul V4b): a picture area on top (an
-- emoji `Icon`, or the caller puts a ViewportFrame in `Picture`), a title,
-- a muted detail line, an optional badge in the corner and an action
-- button at the bottom. `Accent` tints the outline and the picture area.
export type ItemCard = {
	Frame: Frame,
	Picture: Frame,
	Title: TextLabel,
	Detail: TextLabel,
	Badge: TextLabel,
	Button: TextButton,
}

function PanelKit.itemCard(
	parent: Instance,
	title: string,
	detail: string,
	icon: string?,
	accent: Color3?
): ItemCard
	local tint = accent or C.Primary
	local card = Instance.new("Frame")
	card.Name = "ItemCard"
	card.LayoutOrder = nextOrder(parent)
	card.BackgroundColor3 = C.Card
	card.Parent = parent
	corner(card, UiTokens.Radius.Card)
	local stroke = Instance.new("UIStroke")
	stroke.Color = tint
	stroke.Transparency = 0.55
	stroke.Thickness = 1.5
	stroke.Parent = card
	padding(card, 8)

	local picture = Instance.new("Frame")
	picture.Name = "Picture"
	picture.BackgroundColor3 = tint:Lerp(C.Window, 0.7)
	picture.Size = UDim2.new(1, 0, 0, 72)
	picture.Parent = card
	corner(picture, UiTokens.Radius.Tile)
	if icon then
		local glyph = Instance.new("TextLabel")
		glyph.Name = "Icon"
		glyph.BackgroundTransparency = 1
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.Font = UiTokens.Font.Title
		glyph.TextScaled = true
		glyph.Text = icon
		glyph.TextColor3 = C.Text
		glyph.Parent = picture
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 44
		limit.Parent = glyph
	end

	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, -4, 0, 4)
	badge.Size = UDim2.fromOffset(0, 20)
	badge.AutomaticSize = Enum.AutomaticSize.X
	badge.BackgroundColor3 = tint
	badge.Font = PanelKit.FONT_BOLD
	badge.TextColor3 = C.Text
	badge.TextSize = 13
	badge.Text = ""
	badge.Visible = false
	badge.ZIndex = 3
	badge.Parent = picture
	corner(badge, 10)
	local badgePad = Instance.new("UIPadding")
	badgePad.PaddingLeft = UDim.new(0, 6)
	badgePad.PaddingRight = UDim.new(0, 6)
	badgePad.Parent = badge

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.fromOffset(0, 78)
	titleLabel.Size = UDim2.new(1, 0, 0, 22)
	titleLabel.Font = PanelKit.FONT_BOLD
	titleLabel.TextColor3 = C.Text
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Text = title
	titleLabel.Parent = card
	PanelKit.setTextSize(titleLabel, PanelKit.TEXT_SIZE)

	local detailLabel = Instance.new("TextLabel")
	detailLabel.Name = "Detail"
	detailLabel.BackgroundTransparency = 1
	detailLabel.Position = UDim2.fromOffset(0, 100)
	detailLabel.Size = UDim2.new(1, 0, 1, -100 - PanelKit.ROW_HEIGHT - 6)
	detailLabel.Font = PanelKit.FONT
	detailLabel.TextColor3 = C.Muted
	detailLabel.TextXAlignment = Enum.TextXAlignment.Left
	detailLabel.TextYAlignment = Enum.TextYAlignment.Top
	detailLabel.TextWrapped = true
	detailLabel.TextTruncate = Enum.TextTruncate.AtEnd
	detailLabel.Text = detail
	detailLabel.Parent = card
	PanelKit.setTextSize(detailLabel, PanelKit.SMALL_SIZE)

	local button = PanelKit.button(card, "", tint)
	button.AnchorPoint = Vector2.new(0, 1)
	button.Position = UDim2.fromScale(0, 1)
	button.Size = UDim2.new(1, 0, 0, PanelKit.ROW_HEIGHT)
	return {
		Frame = card,
		Picture = picture,
		Title = titleLabel,
		Detail = detailLabel,
		Badge = badge,
		Button = button,
	}
end

-- Shows `text` in an item card's corner badge, or hides it ("").
function PanelKit.setBadge(card: ItemCard, text: string, color: Color3?): ()
	card.Badge.Text = text
	card.Badge.Visible = text ~= ""
	if color then
		card.Badge.BackgroundColor3 = color
	end
end

-- An on/off switch: the setting's name and description on the left, an
-- "On" / "Off" button on the right. Clicking flips it at once and calls
-- `onChange`; the caller may correct it later with `set` (e.g. the server's
-- saved value).
function PanelKit.toggle(
	parent: Instance,
	label: string,
	description: string?,
	value: boolean,
	onChange: (value: boolean) -> ()
): Toggle
	local frame = Instance.new("Frame")
	frame.Name = "Toggle"
	frame.LayoutOrder = nextOrder(parent)
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Parent = parent

	local textColumn = Instance.new("Frame")
	textColumn.Name = "Text"
	textColumn.BackgroundTransparency = 1
	textColumn.Size = UDim2.new(1, -112, 0, 0)
	textColumn.AutomaticSize = Enum.AutomaticSize.Y
	textColumn.Parent = frame
	list(textColumn, UiTokens.Space.XS)
	PanelKit.text(textColumn, label, "Heading")
	if description then
		PanelKit.text(textColumn, description, "Muted")
	end

	local button = PanelKit.button(frame, "", C.Neutral)
	button.Name = "Switch"
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.fromScale(1, 0)
	button.Size = UDim2.fromOffset(100, PanelKit.ROW_HEIGHT)

	local current = value
	local function show(on: boolean): ()
		current = on
		button.Text = if on then "On" else "Off"
		PanelKit.setColor(button, if on then C.Good else C.Neutral)
	end
	show(value)
	button.Activated:Connect(function()
		show(not current)
		onChange(current)
	end)
	return { Frame = frame, Button = button, set = show }
end

-- A bar that fills to a fraction, with text over it. Fill changes ease
-- (instantly with reduced motion), one tween at a time.
function PanelKit.progressBar(parent: Instance, accent: Color3?): ProgressBar
	local track = Instance.new("Frame")
	track.Name = "ProgressBar"
	track.LayoutOrder = nextOrder(parent)
	track.BackgroundColor3 = C.Field
	track.Size = UDim2.new(1, 0, 0, UiTokens.Size.ProgressBar)
	track.ClipsDescendants = true
	track.Parent = parent
	corner(track, UiTokens.Radius.Button)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = accent or C.Primary
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track
	corner(fill, UiTokens.Radius.Button)
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 2
	label.Font = PanelKit.FONT_BOLD
	label.TextColor3 = C.Text
	label.TextStrokeTransparency = 0.6
	label.Text = ""
	label.Parent = track
	PanelKit.setTextSize(label, PanelKit.SMALL_SIZE)

	local tween: Tween? = nil
	local barInfo =
		TweenInfo.new(UiTokens.Motion.Bar, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function set(fraction: number, text: string): ()
		local clamped = if fraction == fraction then math.clamp(fraction, 0, 1) else 0
		label.Text = text
		if tween then
			tween:Cancel()
		end
		local target = UDim2.fromScale(clamped, 1)
		if UiTokens.reducedMotion() then
			fill.Size = target
			return
		end
		local created = TweenService:Create(fill, barInfo, { Size = target })
		tween = created
		created:Play()
	end
	return { Frame = track, set = set }
end

local NOTICE_ICONS: { [NoticeKind]: string } = {
	Empty = "📭",
	Loading = "⏳",
	Error = "⚠️",
	Locked = "🔒",
}

-- A card for a page with nothing to show yet: one short sentence and at most
-- one action button.
function PanelKit.notice(
	parent: Instance,
	kind: NoticeKind,
	message: string,
	actionLabel: string?,
	onAction: (() -> ())?
): Frame
	local card = Instance.new("Frame")
	card.Name = "Notice" .. kind
	card.LayoutOrder = nextOrder(parent)
	card.BackgroundColor3 = C.Card
	card.Size = UDim2.fromScale(1, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Parent = parent
	corner(card, UiTokens.Radius.Card)
	padding(card, UiTokens.Space.L)
	list(card, UiTokens.Space.S)
	local line = PanelKit.text(card, NOTICE_ICONS[kind] .. "  " .. message, "Muted")
	if kind == "Error" then
		line.TextColor3 = C.Danger:Lerp(C.Text, 0.35)
	end
	if actionLabel and onAction then
		local button = PanelKit.button(card, actionLabel, C.Primary)
		button.Activated:Connect(onAction)
	end
	return card
end

-- A short hint shown above `object`: on hover (mouse), while selected
-- (gamepad), and for a moment after a long press (touch). Built once and
-- only shown or hidden afterwards. Inside a clipping frame it may be cut
-- off, so use it on HUD buttons and other unclipped controls.
function PanelKit.tooltip(object: GuiObject, text: string): TextLabel
	local tip = Instance.new("TextLabel")
	tip.Name = "Tooltip"
	tip.AnchorPoint = Vector2.new(0, 1)
	tip.Position = UDim2.fromOffset(0, -6)
	tip.AutomaticSize = Enum.AutomaticSize.XY
	tip.Size = UDim2.new()
	tip.BackgroundColor3 = C.Header
	tip.BackgroundTransparency = 0.05
	tip.Font = PanelKit.FONT
	tip.TextSize =
		math.max(Responsive.MIN_TEXT_SIZE, math.floor(PanelKit.SMALL_SIZE * Responsive.textScale()))
	tip.TextColor3 = C.Text
	tip.Text = text
	tip.ZIndex = object.ZIndex + 10
	tip.Visible = false
	tip.Parent = object
	corner(tip, UiTokens.Radius.Button)
	padding(tip, UiTokens.Space.S)

	-- A long press hides its tip after a moment, unless something showed it
	-- again in the meantime.
	local shownCount = 0
	local function show(): ()
		shownCount += 1
		tip.Visible = true
	end
	local function hide(): ()
		tip.Visible = false
	end
	object.MouseEnter:Connect(show)
	object.MouseLeave:Connect(hide)
	object.SelectionGained:Connect(show)
	object.SelectionLost:Connect(hide)
	object.TouchLongPress:Connect(function()
		show()
		local token = shownCount
		task.delay(2, function()
			if shownCount == token then
				hide()
			end
		end)
	end)
	return tip
end

-- Window ------------------------------------------------------------------

export type WindowOptions = {
	Name: string,
	Title: string,
	Subtitle: string,
	Accent: Color3,
	DisplayOrder: number?,
	Key: Enum.KeyCode?, -- desktop shortcut that toggles the window
	GamepadKey: Enum.KeyCode?, -- gamepad button that toggles the window
}

function PanelKit.window(options: WindowOptions, parent: Instance): Window
	local gui = Instance.new("ScreenGui")
	gui.Name = options.Name
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = options.DisplayOrder or 5

	local frame = Instance.new("Frame")
	frame.Name = "Window"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.BackgroundColor3 = C.Window
	frame.Visible = false
	frame.ClipsDescendants = true
	frame.Parent = gui
	corner(frame, UiTokens.Radius.Window)
	local stroke = Instance.new("UIStroke")
	stroke.Color = options.Accent
	stroke.Thickness = 2
	stroke.Transparency = 0.35
	stroke.Parent = frame
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(320, 300)
	limit.MaxSize = Vector2.new(1080, 780)
	limit.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Parent = frame

	-- Header: accent strip, title, subtitle, close.
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundColor3 = C.Header
	header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
	header.Parent = frame
	local strip = Instance.new("Frame")
	strip.Name = "Accent"
	strip.BackgroundColor3 = options.Accent
	strip.BorderSizePixel = 0
	strip.Size = UDim2.new(1, 0, 0, 4)
	strip.Parent = header
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(20, 10)
	title.Size = UDim2.new(1, -90, 0, 30)
	title.Font = PanelKit.TITLE_FONT
	title.TextSize = 26
	title.TextColor3 = C.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = options.Title
	title.Parent = header
	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromOffset(20, 40)
	subtitle.Size = UDim2.new(1, -90, 0, 18)
	subtitle.Font = PanelKit.FONT
	subtitle.TextSize = 14
	subtitle.TextColor3 = C.Muted
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextTruncate = Enum.TextTruncate.AtEnd
	subtitle.Text = options.Subtitle
	subtitle.Parent = header
	local close = PanelKit.button(header, "X", C.Neutral)
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -14, 0.5, 2)
	close.Size = UDim2.fromOffset(44, 44)
	PanelKit.setTextSize(close, 20)

	-- Navigation (sidebar or top strip) and the scrolling content.
	local nav = Instance.new("ScrollingFrame")
	nav.Name = "Nav"
	nav.BackgroundColor3 = C.Nav
	nav.BorderSizePixel = 0
	nav.ScrollBarThickness = 0
	nav.AutomaticCanvasSize = Enum.AutomaticSize.XY
	nav.CanvasSize = UDim2.new()
	nav.Parent = frame
	padding(nav, 10)
	local navLayout = list(nav, 8)

	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 6
	content.ScrollBarImageColor3 = C.Muted
	content.ScrollBarImageTransparency = 0.4
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.new()
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.Parent = frame
	padding(content, 16)
	list(content, 12)

	local navButtons: { [string]: TextButton } = {}

	-- `compact`: tabs on top instead of a sidebar. `short`: a slimmer header
	-- (no subtitle) and tab strip, for windows with little height.
	local function layoutFor(compact: boolean, short: boolean): ()
		local headerHeight = if short then SHORT_HEADER_HEIGHT else HEADER_HEIGHT
		local topnavHeight = if short then SHORT_TOPNAV_HEIGHT else TOPNAV_HEIGHT
		header.Size = UDim2.new(1, 0, 0, headerHeight)
		title.Position = UDim2.fromOffset(20, if short then 9 else 10)
		title.TextSize = if short then 22 else 26
		subtitle.Visible = not short
		close.Size = if short then UDim2.fromOffset(40, 40) else UDim2.fromOffset(44, 44)
		if compact then
			nav.Position = UDim2.fromOffset(0, headerHeight)
			nav.Size = UDim2.new(1, 0, 0, topnavHeight + 12)
			nav.ScrollingDirection = Enum.ScrollingDirection.X
			navLayout.FillDirection = Enum.FillDirection.Horizontal
			content.Position = UDim2.fromOffset(0, headerHeight + topnavHeight + 12)
			content.Size = UDim2.new(1, 0, 1, -(headerHeight + topnavHeight + 12))
		else
			nav.Position = UDim2.fromOffset(0, headerHeight)
			nav.Size = UDim2.new(0, SIDEBAR_WIDTH, 1, -headerHeight)
			nav.ScrollingDirection = Enum.ScrollingDirection.Y
			navLayout.FillDirection = Enum.FillDirection.Vertical
			content.Position = UDim2.fromOffset(SIDEBAR_WIDTH, headerHeight)
			content.Size = UDim2.new(1, -SIDEBAR_WIDTH, 1, -headerHeight)
		end
		for _, button in navButtons do
			button.Size = if compact
				then UDim2.fromOffset(math.max(96, 14 + #button.Text * 9), topnavHeight - 4)
				else UDim2.new(1, 0, 0, PanelKit.ROW_HEIGHT)
		end
	end
	local function relayout(): ()
		local size = frame.AbsoluteSize
		layoutFor(size.X > 0 and size.X < COMPACT_BELOW, size.Y > 0 and size.Y < SHORT_BELOW)
	end

	-- Fits the window to the screen: a share of it, bigger on small screens.
	local function fit(): ()
		local camera = Workspace.CurrentCamera
		local screen = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		frame.Size = if screen.X < SMALL_SCREEN_BELOW
			then UDim2.fromScale(0.96, 0.9)
			else UDim2.fromScale(0.62, 0.78)
		limit.MinSize = Vector2.new(math.min(320, screen.X - 16), math.min(300, screen.Y - 16))
	end
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	local function watchCamera(camera: Camera?): ()
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
		end
	end
	watchCamera(Workspace.CurrentCamera)
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		watchCamera(Workspace.CurrentCamera)
		fit()
	end)
	fit()
	layoutFor(false, false)

	local openCallbacks: { () -> () } = {}
	local closing = 0

	local window: Window = {
		Gui = gui,
		Frame = frame,
		Content = content,
		Subtitle = subtitle,
		isOpen = function(_self: Window): boolean
			return frame.Visible
		end,
		open = function(_self: Window): ()
			closing += 1
			local reduced = UiTokens.reducedMotion()
			if not frame.Visible then
				scale.Scale = if reduced then 1 else 0.94
				frame.Visible = true
				for _, callback in openCallbacks do
					callback()
				end
			end
			if reduced then
				scale.Scale = 1
				return
			end
			TweenService:Create(
				scale,
				TweenInfo.new(OPEN_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{
					Scale = 1,
				}
			):Play()
		end,
		close = function(_self: Window): ()
			if not frame.Visible then
				return
			end
			closing += 1
			if UiTokens.reducedMotion() then
				frame.Visible = false
				return
			end
			local token = closing
			local tween = TweenService:Create(
				scale,
				TweenInfo.new(OPEN_SECONDS * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Scale = 0.94 }
			)
			tween.Completed:Connect(function()
				if closing == token then
					frame.Visible = false
				end
			end)
			tween:Play()
		end,
		toggle = function(self: Window): ()
			if frame.Visible then
				self:close()
			else
				self:open()
			end
		end,
		setTabs = function(_self: Window, tabs: { Tab }, onSelect: (id: string) -> ()): ()
			for index, tab in tabs do
				local button = PanelKit.button(nav, tab.Label, C.Neutral)
				button.Name = tab.Id
				button.LayoutOrder = index
				button.TextXAlignment = Enum.TextXAlignment.Left
				local inset = Instance.new("UIPadding")
				inset.PaddingLeft = UDim.new(0, 14)
				inset.Parent = button
				button.Activated:Connect(function()
					onSelect(tab.Id)
				end)
				navButtons[tab.Id] = button
			end
			relayout()
		end,
		selectTab = function(_self: Window, id: string): ()
			for tabId, button in navButtons do
				PanelKit.setColor(button, if tabId == id then options.Accent else C.Neutral)
			end
		end,
		clear = function(_self: Window): ()
			for _, child in content:GetChildren() do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
		end,
		onOpen = function(_self: Window, callback: () -> ()): ()
			table.insert(openCallbacks, callback)
		end,
	}

	close.Activated:Connect(function()
		window:close()
	end)
	GamepadNav.watch(frame, function()
		window:close()
	end)
	if options.Key or options.GamepadKey then
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			local key = options.Key and input.KeyCode == options.Key and not processed
			-- Gamepad buttons count as processed while a control is selected,
			-- so for them `processed` can't be trusted; a focused text box can.
			local gamepadKey = options.GamepadKey
				and input.KeyCode == options.GamepadKey
				and UserInputService:GetFocusedTextBox() == nil
			if key or gamepadKey then
				window:toggle()
			end
		end)
	end

	gui.Parent = parent
	return window
end

-- A small "Are you sure?" dialog over a window: the message, [Cancel] and a
-- confirm button. Built once per window and reused. On a gamepad, Cancel is
-- selected first, so pressing A by habit never confirms; B cancels.
function PanelKit.confirmDialog(window: Window, accent: Color3?): ConfirmDialog
	local color = accent or C.Danger
	local dialog = Instance.new("Frame")
	dialog.Name = "ConfirmDialog"
	dialog.AnchorPoint = Vector2.new(0.5, 0.5)
	dialog.Position = UDim2.fromScale(0.5, 0.5)
	dialog.Size = UDim2.fromScale(0.8, 0)
	dialog.AutomaticSize = Enum.AutomaticSize.Y
	dialog.BackgroundColor3 = C.Header
	dialog.ZIndex = 20
	dialog.Visible = false
	dialog.Parent = window.Frame
	corner(dialog, UiTokens.Radius.Card)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(420, math.huge)
	limit.Parent = dialog
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2
	stroke.Parent = dialog
	padding(dialog, UiTokens.Space.M)
	list(dialog, 10)
	local message = PanelKit.text(dialog, "", "Heading")
	message.ZIndex = 21
	local row = PanelKit.row(dialog)
	row.ZIndex = 21
	local cancel = PanelKit.button(row, "Cancel", C.Neutral)
	cancel.Name = "Cancel"
	cancel.Size = UDim2.new(0.5, -4, 1, 0)
	cancel.ZIndex = 22
	local confirm = PanelKit.button(row, "Confirm", color)
	confirm.Name = "Confirm"
	confirm.Size = UDim2.new(0.5, -4, 1, 0)
	confirm.ZIndex = 22

	local pending: (() -> ())? = nil
	local function hide(): ()
		pending = nil
		dialog.Visible = false
	end
	cancel.Activated:Connect(hide)
	confirm.Activated:Connect(function()
		local action = pending
		hide()
		if action then
			action()
		end
	end)
	GamepadNav.watch(dialog, hide, cancel)

	return {
		Frame = dialog,
		ask = function(text: string, confirmLabel: string?, action: () -> ()): ()
			message.Text = text
			confirm.Text = confirmLabel or "Confirm"
			pending = action
			dialog.Visible = true
		end,
		hide = hide,
	}
end

return PanelKit
