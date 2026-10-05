--!strict
--[[
	Hammer shop UI: a "Hammers" button opens a panel listing every hammer with
	its damage and price, and a Buy / Equip / Equipped button. Display only:
	clicking sends the hammer id; the server checks coins and ownership and
	answers with a fresh Profile.Sync, which redraws the panel.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HammerConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("HammerConfig"))
local ProgressController = require(script.Parent.ProgressController)

local ShopController = {}

local PANEL_COLOR = Color3.fromRGB(30, 30, 40)
local ROW_COLOR = Color3.fromRGB(48, 48, 62)
local TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local BUY_COLOR = Color3.fromRGB(80, 190, 90)
local EQUIP_COLOR = Color3.fromRGB(70, 140, 230)
local DISABLED_COLOR = Color3.fromRGB(90, 90, 100)
local ROW_HEIGHT = 64
local MIN_TOUCH_SIZE = 44 -- recommended minimum tap target

local localPlayer = Players.LocalPlayer

type Row = {
	Hammer: HammerConfig.HammerDefinition,
	Status: TextLabel,
	Button: TextButton,
}

local function corner(parent: Instance): ()
	Instance.new("UICorner").Parent = parent
end

local function label(name: string, parent: Instance): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.TextColor3 = TEXT_COLOR
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Parent = parent
	return text
end

local function button(name: string, parent: Instance): TextButton
	local clickable = Instance.new("TextButton")
	clickable.Name = name
	clickable.TextColor3 = TEXT_COLOR
	clickable.Font = Enum.Font.FredokaOne
	clickable.TextScaled = true
	clickable.AutoButtonColor = true
	clickable.Parent = parent
	corner(clickable)
	return clickable
end

local function buildRow(hammer: HammerConfig.HammerDefinition, order: number, list: Instance): Row
	local row = Instance.new("Frame")
	row.Name = hammer.Id
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3 = ROW_COLOR
	row.Parent = list
	corner(row)

	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.BackgroundColor3 = hammer.HeadColor
	swatch.Position = UDim2.fromOffset(10, 12)
	swatch.Size = UDim2.fromOffset(40, 40)
	swatch.Parent = row
	corner(swatch)

	local name = label("Name", row)
	name.Position = UDim2.fromOffset(60, 6)
	name.Size = UDim2.new(0.55, -60, 0, 28)
	name.Text = hammer.DisplayName

	local status = label("Status", row)
	status.Position = UDim2.fromOffset(60, 34)
	status.Size = UDim2.new(0.55, -60, 0, 22)
	status.TextTransparency = 0.25

	local action = button("Action", row)
	action.AnchorPoint = Vector2.new(1, 0.5)
	action.Position = UDim2.new(1, -10, 0.5, 0)
	action.Size = UDim2.new(0.35, 0, 0, MIN_TOUCH_SIZE)

	return { Hammer = hammer, Status = status, Button = action }
end

local function refreshRow(row: Row): ()
	local snapshot = ProgressController.get()
	local hammer = row.Hammer
	local owned = ProgressController.ownsHammer(hammer.Id)
	local equipped = snapshot ~= nil and snapshot.EquippedHammerId == hammer.Id
	local coins = if snapshot then snapshot.Coins else 0

	row.Status.Text = string.format("Damage %d   %s", hammer.Damage, hammer.Description)
	if equipped then
		row.Button.Text = "Equipped"
		row.Button.BackgroundColor3 = DISABLED_COLOR
		row.Button.Active = false
	elseif owned then
		row.Button.Text = "Equip"
		row.Button.BackgroundColor3 = EQUIP_COLOR
		row.Button.Active = true
	elseif coins >= hammer.Price then
		row.Button.Text = string.format("Buy %d", hammer.Price)
		row.Button.BackgroundColor3 = BUY_COLOR
		row.Button.Active = true
	else
		row.Button.Text = string.format("Need %d", hammer.Price)
		row.Button.BackgroundColor3 = DISABLED_COLOR
		row.Button.Active = false
	end
end

function ShopController.start(): ()
	local remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Shop")
	local buyRemote = remotes:WaitForChild("BuyHammer")
	local equipRemote = remotes:WaitForChild("EquipHammer")
	assert(
		buyRemote:IsA("RemoteEvent") and equipRemote:IsA("RemoteEvent"),
		"Shop remotes must be RemoteEvents"
	)

	local gui = Instance.new("ScreenGui")
	gui.Name = "Shop"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local open = button("OpenShop", gui)
	open.Text = "Hammers"
	open.BackgroundColor3 = EQUIP_COLOR
	open.AnchorPoint = Vector2.new(1, 1)
	open.Position = UDim2.new(1, -16, 1, -72)
	open.Size = UDim2.fromOffset(140, MIN_TOUCH_SIZE + 4)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.6, 0.65)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.Visible = false
	panel.Parent = gui
	corner(panel)
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MinSize = Vector2.new(300, 260)
	sizeLimit.MaxSize = Vector2.new(560, 480)
	sizeLimit.Parent = panel

	local title = label("Title", panel)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -90, 0, 34)
	title.Text = "Hammers"

	local close = button("Close", panel)
	close.Text = "X"
	close.BackgroundColor3 = DISABLED_COLOR
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 8)
	close.Size = UDim2.fromOffset(MIN_TOUCH_SIZE, MIN_TOUCH_SIZE)

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(10, 60)
	list.Size = UDim2.new(1, -20, 1, -70)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = 6
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local rows: { Row } = {}
	for order, hammer in HammerConfig.List do
		local row = buildRow(hammer, order, list)
		table.insert(rows, row)
		row.Button.Activated:Connect(function()
			if not row.Button.Active then
				return
			end
			if ProgressController.ownsHammer(hammer.Id) then
				equipRemote:FireServer(hammer.Id)
			else
				buyRemote:FireServer(hammer.Id)
			end
		end)
	end

	local function refresh(): ()
		for _, row in rows do
			refreshRow(row)
		end
	end
	ProgressController.Changed:Connect(refresh)
	refresh()

	open.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)
	close.Activated:Connect(function()
		panel.Visible = false
	end)

	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

return ShopController
