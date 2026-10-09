--!strict
--[[
	Hammer shop UI: a "Hammers" button opens a panel listing every hammer with
	a small 3D preview (Shared/HammerModel, built once per row, no effects), its
	damage and price, and a Buy / Equip / Equipped button. Display only:
	clicking sends the hammer id; the server checks coins and ownership and
	answers with a fresh Profile.Sync, which redraws the panel.

	During a Hammer Shop sale (docs/EVENTS.md) rows show the sale price, and
	Buy also sends the price shown: the server charges its own price and
	refuses if that is higher than what the player saw.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HammerConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("HammerConfig"))
local StoreConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StoreConfig"))
local EventRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EventRules"))
local HammerModel = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HammerModel"))
local EventController = require(script.Parent.EventController)
local ProgressController = require(script.Parent.ProgressController)
local GamepadNav = require(script.Parent.Parent.Lib.GamepadNav)
local Responsive = require(script.Parent.Parent.Lib.Responsive)

local ShopController = {}

local PANEL_COLOR = Color3.fromRGB(30, 30, 40)
local ROW_COLOR = Color3.fromRGB(48, 48, 62)
local TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local BUY_COLOR = Color3.fromRGB(80, 190, 90)
local EQUIP_COLOR = Color3.fromRGB(70, 140, 230)
local DISABLED_COLOR = Color3.fromRGB(90, 90, 100)
local ROW_HEIGHT = 64
local PREVIEW_SIZE = 56
local PREVIEW_COLOR = Color3.fromRGB(36, 36, 48)
-- Shown tilted, head up, so every hammer reads at a glance.
local PREVIEW_TILT = CFrame.Angles(math.rad(40), 0, 0)
local PREVIEW_FOV = 40
local MIN_TOUCH_SIZE = 44 -- recommended minimum tap target

local localPlayer = Players.LocalPlayer
-- Set once the panel exists (start); lets other controllers open it.
local openPanel: (() -> ())? = nil

type Row = {
	Hammer: HammerConfig.HammerDefinition,
	IsMystery: boolean, -- a Robux Mystery Hammer (always owned, rolled stats)
	BonusPercent: number,
	CritPercent: number,
	Price: number, -- the price shown on the Buy button (sale included)
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
	Responsive.capText(text, 22)
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
	Responsive.capText(clickable, 20)
	return clickable
end

-- A still 3D view of the hammer (static: built once, no camera updates).
local function buildPreview(hammer: HammerConfig.HammerDefinition, parent: Instance): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.BackgroundColor3 = PREVIEW_COLOR
	viewport.Position = UDim2.fromOffset(6, (ROW_HEIGHT - PREVIEW_SIZE) / 2)
	viewport.Size = UDim2.fromOffset(PREVIEW_SIZE, PREVIEW_SIZE)
	viewport.Ambient = Color3.fromRGB(170, 170, 180)
	viewport.LightColor = Color3.fromRGB(255, 250, 240)
	viewport.LightDirection = Vector3.new(-1, -1, -0.6)
	viewport.Parent = parent
	corner(viewport)

	local model = Instance.new("Model")
	model.Name = "Hammer"
	local style = HammerModel.styleFor(hammer.Style, hammer.HeadColor, hammer.HandleColor)
	HammerModel.build(style, model, PREVIEW_TILT, false)
	model.Parent = viewport

	local center, extents = model:GetBoundingBox()
	local radius = extents.Magnitude / 2
	local distance = radius / math.tan(math.rad(PREVIEW_FOV / 2)) * 1.05
	local camera = Instance.new("Camera")
	camera.FieldOfView = PREVIEW_FOV
	-- From the side the head's faces point to: shaft across, head upright.
	camera.CFrame = CFrame.lookAt(center.Position + Vector3.new(distance, 0, 0), center.Position)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport
end

local function buildRow(hammer: HammerConfig.HammerDefinition, order: number, list: Instance): Row
	local row = Instance.new("Frame")
	row.Name = hammer.Id
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3 = ROW_COLOR
	row.Parent = list
	corner(row)

	buildPreview(hammer, row)
	local textLeft = PREVIEW_SIZE + 14

	local name = label("Name", row)
	name.Position = UDim2.fromOffset(textLeft, 6)
	name.Size = UDim2.new(0.55, -textLeft, 0, 28)
	name.Text = hammer.DisplayName

	local status = label("Status", row)
	status.Position = UDim2.fromOffset(textLeft, 34)
	status.Size = UDim2.new(0.55, -textLeft, 0, 24)
	status.TextTransparency = 0.25
	status.TextWrapped = true
	Responsive.capText(status, 16)

	local action = button("Action", row)
	action.AnchorPoint = Vector2.new(1, 0.5)
	action.Position = UDim2.new(1, -10, 0.5, 0)
	action.Size = UDim2.new(0.35, 0, 0, MIN_TOUCH_SIZE)

	return {
		Hammer = hammer,
		IsMystery = false,
		BonusPercent = 0,
		CritPercent = 0,
		Price = hammer.Price,
		Status = status,
		Button = action,
	}
end

local function refreshRow(row: Row): ()
	local snapshot = ProgressController.get()
	local hammer = row.Hammer
	local owned = row.IsMystery or ProgressController.ownsHammer(hammer.Id)
	local equipped = snapshot ~= nil and snapshot.EquippedHammerId == hammer.Id
	local coins = if snapshot then snapshot.Coins else 0

	row.Status.Text = if row.IsMystery
		then string.format(
			"Damage %d   +%d%% damage   +%d%% crit damage",
			hammer.Damage,
			row.BonusPercent,
			row.CritPercent
		)
		else string.format("Damage %d   %s", hammer.Damage, hammer.Description)
	if equipped then
		row.Button.Text = "Equipped"
		row.Button.BackgroundColor3 = DISABLED_COLOR
		row.Button.Active = false
	elseif owned then
		row.Button.Text = "Equip"
		row.Button.BackgroundColor3 = EQUIP_COLOR
		row.Button.Active = true
	end
	if equipped or owned then
		return
	end
	local percent = EventController.discountPercent(hammer.Id)
	row.Price = EventRules.discountedPrice(hammer.Price, percent)
	local sale = if percent > 0 then string.format(" (-%d%%)", percent) else ""
	if coins >= row.Price then
		row.Button.Text = string.format("Buy %d%s", row.Price, sale)
		row.Button.BackgroundColor3 = BUY_COLOR
		row.Button.Active = true
	else
		row.Button.Text = string.format("Need %d%s", row.Price, sale)
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

	-- HUD button in the shared column (Lib/Responsive), lowest of the four.
	local open = Responsive.dockButton("OpenShop", "🔨", "Hammers", EQUIP_COLOR, 4)

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
	Responsive.fitPopup(panel, sizeLimit, Vector2.new(0.6, 0.65))

	local title = label("Title", panel)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -90, 0, 34)
	title.Text = "Hammers"
	Responsive.capText(title, 30)

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
				buyRemote:FireServer(hammer.Id, row.Price)
			end
		end)
	end

	-- Mystery Hammers appear as they are bought, each with its rolled stats.
	local mysteryRows: { [string]: boolean } = {}
	local function addMysteryRows(): ()
		local snapshot = ProgressController.get()
		if snapshot == nil then
			return
		end
		for _, owned in snapshot.MysteryHammers do
			if mysteryRows[owned.Id] then
				continue
			end
			mysteryRows[owned.Id] = true
			local look: HammerConfig.HammerDefinition = {
				Id = owned.Id,
				DisplayName = StoreConfig.Mystery.DisplayName,
				Description = "",
				Damage = owned.Damage,
				Price = 0,
				HeadColor = StoreConfig.Mystery.HeadColor,
				HandleColor = StoreConfig.Mystery.HandleColor,
				Style = StoreConfig.Mystery.Style,
			}
			local row = buildRow(look, 100 + #rows, list)
			row.IsMystery = true
			row.BonusPercent = owned.BonusDamagePercent
			row.CritPercent = owned.CritDamagePercent
			table.insert(rows, row)
			row.Button.Activated:Connect(function()
				if row.Button.Active then
					equipRemote:FireServer(owned.Id)
				end
			end)
		end
	end

	local function refresh(): ()
		addMysteryRows()
		for _, row in rows do
			refreshRow(row)
		end
	end
	ProgressController.Changed:Connect(refresh)
	EventController.Changed:Connect(refresh)
	refresh()

	open.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)
	openPanel = function()
		panel.Visible = true
	end
	close.Activated:Connect(function()
		panel.Visible = false
	end)
	GamepadNav.watch(panel, function()
		panel.Visible = false
	end)

	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

-- Opens the hammer shop (e.g. from the vending machine, StoreMachineController).
-- Display only: buying still goes through Shop.BuyHammer, checked by the server.
function ShopController.open(): ()
	if openPanel then
		openPanel()
	end
end

return ShopController
