--!strict
--[[
	Screen awareness for the HUD and panels (2026-10-08, docs/UI.md).

	  * classify(): Phone / Tablet / Desktop from the viewport (short side) and
	    whether the device has touch controls. Pure, so it is unit-tested.
	  * onChanged(): runs a callback now and whenever the viewport changes
	    (rotation, window resize). One camera listener for the whole client.
	  * capText(): caps a TextScaled label so long rows can't blow text up, and
	    lets it shrink (down to a readable minimum) instead of clipping.
	  * fitPopup(): sizes a popup panel to the screen: most of a phone screen,
	    the panel's normal share on bigger ones.
	  * dockButton(): the shared column of HUD buttons (Hammers, Store, Bag,
	    Admin, Social, Quests). Desktop: one column bottom-right, as before.
	    Touch screens: top-right, in as many columns as it takes to end above
	    Roblox's jump button (owner phone screenshots 2026-10-10: one column
	    ran under the jump button and off the screen).

	Display only: nothing here touches game state.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local UiTokens = require(script.Parent.UiTokens)

export type FormFactor = "Phone" | "Tablet" | "Desktop"

export type DockLayout = {
	AnchorPoint: Vector2,
	Position: UDim2,
	VerticalAlignment: Enum.VerticalAlignment,
	ButtonSize: Vector2,
	Gap: number,
	MaxTextSize: number,
	-- Buttons per column before the next column starts (to the left).
	Rows: number,
}

local Responsive = {}

-- A screen whose short side is under this many pixels is a phone (landscape
-- phones report roughly 320-430; small desktop windows count too, so they get
-- the same compact layout).
Responsive.PHONE_SHORT_SIDE = 500
-- Smallest text a capped label may shrink to before it clips instead.
Responsive.MIN_TEXT_SIZE = 11
-- Popup share of the screen on phones (width, height).
Responsive.PHONE_POPUP_SCALE = Vector2.new(0.96, 0.9)
-- Below this the HUD lines (score, boosts) under the Stress Meter stop at the
-- dock on touch screens in portrait.
local PORTRAIT_DOCK_TOP = 112
local DOCK_EDGE = 12
-- Roblox's top bar (newest UI); ScreenGuis start below it.
Responsive.TOP_INSET = 58

-- Where Roblox's touch jump button starts from the top (approximate, from the
-- touch controls' layout): 70 px on phones, 120 px on bigger screens.
function Responsive.jumpTop(viewport: Vector2): number
	local small = math.min(viewport.X, viewport.Y) <= Responsive.PHONE_SHORT_SIDE
	local size = if small then 70 else 120
	return viewport.Y - (if small then size + 20 else size * 1.75)
end

function Responsive.classify(viewport: Vector2, touch: boolean): FormFactor
	local shortSide = math.min(viewport.X, viewport.Y)
	if shortSide < Responsive.PHONE_SHORT_SIDE then
		return "Phone"
	end
	return if touch then "Tablet" else "Desktop"
end

-- Where the HUD button column goes and how big its buttons are.
function Responsive.dockLayout(
	formFactor: FormFactor,
	viewport: Vector2,
	touch: boolean
): DockLayout
	-- Phones: compact icon tiles (icon over a tiny caption); bigger screens:
	-- icon + label.
	local buttonSize = if formFactor == "Phone"
		then Vector2.new(52, 42)
		elseif formFactor == "Tablet" then Vector2.new(130, 46)
		else Vector2.new(140, 48)
	local gap = if formFactor == "Phone" then 6 else 8
	local maxText = if formFactor == "Phone" then 18 else 22
	if not touch then
		-- Desktop (and small desktop windows): bottom-right, as it always was.
		return {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -16, 1, -72),
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			ButtonSize = buttonSize,
			Gap = gap,
			MaxTextSize = maxText,
			Rows = 20,
		}
	end
	-- Touch: the jump button owns the bottom-right corner, so stack from the
	-- top. In portrait the HUD lines under the Stress Meter reach the right
	-- edge, so start below them.
	local top = if viewport.Y > viewport.X then PORTRAIT_DOCK_TOP else DOCK_EDGE
	-- As many rows as fit between the top and the jump button.
	local room = Responsive.jumpTop(viewport) - 8 - Responsive.TOP_INSET - top
	local rows = math.max(1, math.floor((room + gap) / (buttonSize.Y + gap)))
	return {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -DOCK_EDGE, 0, top),
		VerticalAlignment = Enum.VerticalAlignment.Top,
		ButtonSize = buttonSize,
		Gap = gap,
		MaxTextSize = maxText,
		Rows = rows,
	}
end

-- Popup size for a viewport: `desktopScale` of the screen, or most of it on phones.
function Responsive.popupSize(viewport: Vector2, desktopScale: Vector2): UDim2
	local shortSide = math.min(viewport.X, viewport.Y)
	local scale = if shortSide < Responsive.PHONE_SHORT_SIDE
		then Responsive.PHONE_POPUP_SCALE
		else desktopScale
	return UDim2.fromScale(scale.X, scale.Y)
end

-- Runtime --------------------------------------------------------------------

local listeners: { () -> () } = {}
local watching = false

function Responsive.viewport(): Vector2
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

function Responsive.hasTouch(): boolean
	return UserInputService.TouchEnabled
end

function Responsive.formFactor(): FormFactor
	return Responsive.classify(Responsive.viewport(), Responsive.hasTouch())
end

local function notify(): ()
	for _, listener in listeners do
		task.spawn(listener)
	end
end

local function watch(): ()
	if watching then
		return
	end
	watching = true
	local connection: RBXScriptConnection? = nil
	local function follow(camera: Camera?): ()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		if camera then
			connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(notify)
		end
	end
	follow(Workspace.CurrentCamera)
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		follow(Workspace.CurrentCamera)
		notify()
	end)
end

-- Runs `callback` now and after every viewport change.
function Responsive.onChanged(callback: () -> ()): ()
	watch()
	table.insert(listeners, callback)
	callback()
end

-- Phones get slightly smaller text everywhere a size is capped (labels,
-- buttons, PanelKit captions), never below MIN_TEXT_SIZE.
Responsive.PHONE_TEXT_SCALE = 0.85

function Responsive.textScale(): number
	return if Responsive.formFactor() == "Phone" then Responsive.PHONE_TEXT_SCALE else 1
end

-- Text that fits its box: shrinks when it must, never grows past `maxSize`
-- (scaled down a little on phones).
-- `object` is a TextLabel, TextButton or TextBox.
function Responsive.capText(object: GuiObject, maxSize: number, minSize: number?): ()
	-- The three text classes share TextScaled; the checker can't write through a union.
	(object :: TextLabel).TextScaled = true
	local constraint = object:FindFirstChildOfClass("UITextSizeConstraint")
	if constraint == nil then
		local created = Instance.new("UITextSizeConstraint")
		created.Parent = object
		constraint = created
	end
	local cap = constraint :: UITextSizeConstraint
	cap.MaxTextSize =
		math.max(Responsive.MIN_TEXT_SIZE, math.floor(maxSize * Responsive.textScale()))
	cap.MinTextSize = math.min(cap.MaxTextSize, math.floor(minSize or Responsive.MIN_TEXT_SIZE))
end

-- Keeps a centred popup sized to the screen. `limit` is its size constraint;
-- its MinSize is pulled in so the popup never runs off a small screen.
function Responsive.fitPopup(panel: GuiObject, limit: UISizeConstraint, desktopScale: Vector2): ()
	local baseMin = limit.MinSize
	Responsive.onChanged(function()
		local viewport = Responsive.viewport()
		panel.Size = Responsive.popupSize(viewport, desktopScale)
		limit.MinSize = Vector2.new(
			math.min(baseMin.X, math.max(0, viewport.X - 16)),
			math.min(baseMin.Y, math.max(0, viewport.Y - 16))
		)
	end)
end

-- Dock ------------------------------------------------------------------------

local dockFrame: Frame? = nil
local dockLayout: UIGridLayout? = nil
local dockButtons: { TextButton } = {}

local function applyDock(): ()
	local frame, layout = dockFrame, dockLayout
	if frame == nil or layout == nil then
		return
	end
	local viewport = Responsive.viewport()
	local touch = Responsive.hasTouch()
	local spec = Responsive.dockLayout(Responsive.classify(viewport, touch), viewport, touch)
	frame.AnchorPoint = spec.AnchorPoint
	frame.Position = spec.Position
	layout.VerticalAlignment = spec.VerticalAlignment
	layout.CellSize = UDim2.fromOffset(spec.ButtonSize.X, spec.ButtonSize.Y)
	layout.CellPadding = UDim2.fromOffset(spec.Gap, spec.Gap)
	layout.FillDirectionMaxCells = spec.Rows
	local compact = spec.ButtonSize.X < 80
	for _, button in dockButtons do
		button.Size = UDim2.fromOffset(spec.ButtonSize.X, spec.ButtonSize.Y)
		Responsive.styleIconButton(button, compact, spec.MaxTextSize)
	end
end

local function dock(): Frame
	local existing = dockFrame
	if existing then
		return existing
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "ActionDock"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local frame = Instance.new("Frame")
	frame.Name = "Buttons"
	frame.BackgroundTransparency = 1
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.Size = UDim2.new()
	frame.Parent = gui
	-- Top to bottom, then the next column to the left.
	local layout = Instance.new("UIGridLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.StartCorner = Enum.StartCorner.TopRight
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Parent = frame

	dockFrame = frame
	dockLayout = layout
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	Responsive.onChanged(applyDock)
	return frame
end

-- Icon buttons ----------------------------------------------------------------

-- A compact button showing an icon and a short label (the label doubles as
-- its tooltip on phones, where it's a tiny caption under the icon). Since
-- the visual overhaul (V4a) it's a dark card like the panels, with `color`
-- as a round icon disc, and it squishes a little when pressed (not with
-- Reduced motion).
function Responsive.iconButton(
	parent: Instance,
	name: string,
	icon: string,
	label: string,
	color: Color3
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = ""
	button.BackgroundColor3 = UiTokens.Color.Window
	button.BackgroundTransparency = 0.1
	button.AutoButtonColor = true
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UiTokens.Radius.Card)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Transparency = 0.35
	stroke.Thickness = 1.5
	stroke.Parent = button
	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.BackgroundColor3 = color
	disc.BorderSizePixel = 0
	disc.Parent = button
	local discCorner = Instance.new("UICorner")
	discCorner.CornerRadius = UDim.new(1, 0)
	discCorner.Parent = disc
	local square = Instance.new("UIAspectRatioConstraint")
	square.AspectRatio = 1
	square.DominantAxis = Enum.DominantAxis.Height
	square.Parent = disc
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = icon
	iconLabel.TextColor3 = Color3.new(1, 1, 1)
	iconLabel.Font = Enum.Font.FredokaOne
	iconLabel.ZIndex = 2
	iconLabel.Parent = button
	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.BackgroundTransparency = 1
	caption.Text = label
	caption.TextColor3 = UiTokens.Color.Text
	caption.Font = UiTokens.Font.Bold
	caption.Parent = button
	local scale = Instance.new("UIScale")
	scale.Parent = button
	local function squish(to: number): ()
		TweenService:Create(
			scale,
			UiTokens.motion(
				TweenInfo.new(
					UiTokens.Motion.Hover,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out
				)
			),
			{ Scale = to }
		):Play()
	end
	button.MouseButton1Down:Connect(function()
		squish(0.94)
	end)
	button.MouseButton1Up:Connect(function()
		squish(1)
	end)
	button.MouseLeave:Connect(function()
		squish(1)
	end)
	Responsive.styleIconButton(button, Responsive.formFactor() == "Phone", 20)
	return button
end

-- Lays out an icon button: `compact` = the disc and icon over a tiny caption
-- (phones), otherwise the disc on the left and the label beside it.
function Responsive.styleIconButton(button: GuiButton, compact: boolean, maxText: number): ()
	local icon = button:FindFirstChild("Icon")
	local caption = button:FindFirstChild("Caption")
	local disc = button:FindFirstChild("Disc")
	if
		icon == nil
		or caption == nil
		or not icon:IsA("TextLabel")
		or not caption:IsA("TextLabel")
	then
		return
	end
	if compact then
		icon.Position = UDim2.fromScale(0, 0.06)
		icon.Size = UDim2.fromScale(1, 0.56)
		caption.Position = UDim2.fromScale(0.04, 0.64)
		caption.Size = UDim2.fromScale(0.92, 0.32)
		caption.TextXAlignment = Enum.TextXAlignment.Center
		if disc and disc:IsA("Frame") then
			disc.AnchorPoint = Vector2.new(0.5, 0)
			disc.Position = UDim2.fromScale(0.5, 0.06)
			disc.Size = UDim2.fromScale(0.56, 0.56)
		end
		Responsive.capText(icon, 24, 14)
		Responsive.capText(caption, 12, 9)
	else
		icon.Position = UDim2.fromScale(0.05, 0.14)
		icon.Size = UDim2.fromScale(0.26, 0.72)
		caption.Position = UDim2.fromScale(0.36, 0.15)
		caption.Size = UDim2.fromScale(0.6, 0.7)
		caption.TextXAlignment = Enum.TextXAlignment.Left
		if disc and disc:IsA("Frame") then
			disc.AnchorPoint = Vector2.new(0, 0.5)
			disc.Position = UDim2.fromScale(0.05, 0.5)
			disc.Size = UDim2.fromScale(0.72, 0.72)
		end
		Responsive.capText(icon, 22, 14)
		Responsive.capText(caption, maxText)
	end
end

-- Changes an icon button's label (e.g. "Bag (3)").
function Responsive.setButtonLabel(button: GuiButton, label: string): ()
	local caption = button:FindFirstChild("Caption")
	if caption and caption:IsA("TextLabel") then
		caption.Text = label
	end
end

-- How wide the HUD button dock is right now (its visible buttons in their
-- columns), so other touch buttons can stand to the left of it.
function Responsive.dockWidth(): number
	local viewport = Responsive.viewport()
	local touch = Responsive.hasTouch()
	local spec = Responsive.dockLayout(Responsive.classify(viewport, touch), viewport, touch)
	local visible = 0
	for _, button in dockButtons do
		if button.Visible then
			visible += 1
		end
	end
	local columns = math.max(1, math.ceil(visible / spec.Rows))
	return columns * spec.ButtonSize.X + (columns - 1) * spec.Gap + DOCK_EDGE
end

-- Where phone HUD cards (match score, team mission) go: under the top HUD's
-- stat and boost chips, in ScreenGui (inset) coordinates.
Responsive.PHONE_CARD_TOP = 36
-- Where the Forfeit / Leave buttons go on phones: on the left, under Menu and Music.
Responsive.PHONE_LEFT_BUTTON_TOP = 60

-- A button in the shared HUD column. `order` sorts top to bottom; hide it
-- with .Visible and the column closes the gap.
function Responsive.dockButton(
	name: string,
	icon: string,
	label: string,
	color: Color3,
	order: number
): TextButton
	local frame = dock()
	local button = Responsive.iconButton(frame, name, icon, label, color)
	button.LayoutOrder = order
	table.insert(dockButtons, button)
	applyDock()
	return button
end

return Responsive
