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
	section cards, rows, text, stat tiles. Text uses fixed, readable sizes and
	wraps instead of scaling down.

	Nothing here runs per frame: hover/press tweens only play on input, and
	layout only reacts to size changes.
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local PanelKit = {}

PanelKit.Colors = table.freeze({
	Window = Color3.fromRGB(26, 29, 41),
	Header = Color3.fromRGB(34, 38, 55),
	Nav = Color3.fromRGB(31, 34, 49),
	Card = Color3.fromRGB(40, 44, 63),
	Field = Color3.fromRGB(52, 57, 80),
	Text = Color3.fromRGB(240, 242, 248),
	Muted = Color3.fromRGB(170, 176, 198),
	Heading = Color3.fromRGB(255, 214, 120),
	Primary = Color3.fromRGB(70, 140, 230),
	Good = Color3.fromRGB(70, 175, 95),
	Danger = Color3.fromRGB(205, 75, 80),
	Neutral = Color3.fromRGB(78, 84, 108),
	Disabled = Color3.fromRGB(70, 72, 84),
})
local C = PanelKit.Colors

PanelKit.FONT = Enum.Font.GothamMedium
PanelKit.FONT_BOLD = Enum.Font.GothamBold
PanelKit.TITLE_FONT = Enum.Font.FredokaOne
PanelKit.TEXT_SIZE = 17
PanelKit.SMALL_SIZE = 15
PanelKit.ROW_HEIGHT = 46 -- comfortable to tap
local HEADER_HEIGHT = 64
local SIDEBAR_WIDTH = 176
local TOPNAV_HEIGHT = 48
local COMPACT_BELOW = 640 -- window width (px) under which the nav moves to the top
local SMALL_SCREEN_BELOW = 900 -- screen width (px) under which the window fills more of it
local OPEN_SECONDS = 0.12

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

export type Section = {
	Frame: Frame,
	Body: Frame,
}

local function corner(parent: Instance, radius: number?): ()
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
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

-- A text line that wraps and grows downward (never shrinks to fit).
function PanelKit.text(parent: Instance, content: string, kind: string?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = kind or "Text"
	label.LayoutOrder = nextOrder(parent)
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Font = if kind == "Heading" or kind == "Value" then PanelKit.FONT_BOLD else PanelKit.FONT
	label.TextSize = if kind == "Value"
		then 22
		elseif kind == "Muted" then PanelKit.SMALL_SIZE
		else PanelKit.TEXT_SIZE
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
	button.TextSize = PanelKit.TEXT_SIZE
	button.TextColor3 = C.Text
	button.TextWrapped = true
	button.Text = content
	button.Parent = parent
	corner(button, 8)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	PanelKit.setColor(button, color or C.Neutral)

	local hoverInfo = TweenInfo.new(0.08)
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
	corner(card, 12)
	padding(card, 12)
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
	headerText.TextSize = 18
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
	name.TextSize = PanelKit.SMALL_SIZE
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
	valueLabel.TextSize = 24
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

-- Window ------------------------------------------------------------------

export type WindowOptions = {
	Name: string,
	Title: string,
	Subtitle: string,
	Accent: Color3,
	DisplayOrder: number?,
	Key: Enum.KeyCode?, -- desktop shortcut that toggles the window
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
	corner(frame, 16)
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
	close.TextSize = 20

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

	local function layoutFor(compact: boolean): ()
		if compact then
			nav.Position = UDim2.fromOffset(0, HEADER_HEIGHT)
			nav.Size = UDim2.new(1, 0, 0, TOPNAV_HEIGHT + 12)
			nav.ScrollingDirection = Enum.ScrollingDirection.X
			navLayout.FillDirection = Enum.FillDirection.Horizontal
			content.Position = UDim2.fromOffset(0, HEADER_HEIGHT + TOPNAV_HEIGHT + 12)
			content.Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + TOPNAV_HEIGHT + 12))
		else
			nav.Position = UDim2.fromOffset(0, HEADER_HEIGHT)
			nav.Size = UDim2.new(0, SIDEBAR_WIDTH, 1, -HEADER_HEIGHT)
			nav.ScrollingDirection = Enum.ScrollingDirection.Y
			navLayout.FillDirection = Enum.FillDirection.Vertical
			content.Position = UDim2.fromOffset(SIDEBAR_WIDTH, HEADER_HEIGHT)
			content.Size = UDim2.new(1, -SIDEBAR_WIDTH, 1, -HEADER_HEIGHT)
		end
		for _, button in navButtons do
			button.Size = if compact
				then UDim2.fromOffset(math.max(96, 14 + #button.Text * 9), TOPNAV_HEIGHT - 4)
				else UDim2.new(1, 0, 0, PanelKit.ROW_HEIGHT)
		end
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
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		layoutFor(frame.AbsoluteSize.X < COMPACT_BELOW)
	end)
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
	layoutFor(false)

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
			if not frame.Visible then
				scale.Scale = 0.94
				frame.Visible = true
				for _, callback in openCallbacks do
					callback()
				end
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
			layoutFor(frame.AbsoluteSize.X > 0 and frame.AbsoluteSize.X < COMPACT_BELOW)
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
	if options.Key then
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if not processed and input.KeyCode == options.Key then
				window:toggle()
			end
		end)
	end

	gui.Parent = parent
	return window
end

return PanelKit
