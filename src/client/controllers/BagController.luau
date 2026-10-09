--!strict
--[[
	The Bag (docs/STORE.md "Bag and gifts"): store items the player owns but
	hasn't used yet (bought, gifted by friends, or dropped by custom bosses).
	"Use" starts a boost; "Open" opens a Mystery Hammer. Display only: the
	server checks the player really has the item (BagService).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BagRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BagRules"))
local ProgressController = require(script.Parent.ProgressController)
local Responsive = require(script.Parent.Parent.Lib.Responsive)
local StoreConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StoreConfig"))

local BagController = {}

-- Set once the panel exists (start); lets the Player Panel open it.
local openPanel: (() -> ())? = nil

local PANEL_COLOR = Color3.fromRGB(30, 30, 40)
local ROW_COLOR = Color3.fromRGB(48, 48, 62)
local TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local BAG_COLOR = Color3.fromRGB(60, 160, 150)
local USE_COLOR = Color3.fromRGB(80, 190, 90)
local MUTED_COLOR = Color3.fromRGB(90, 90, 100)
local ROW_HEIGHT = 56
local MIN_TOUCH_SIZE = 44

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

function BagController.start(): ()
	local useRemote =
		ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Bag"):WaitForChild("Use")
	assert(useRemote:IsA("RemoteEvent"), "Bag.Use must be a RemoteEvent")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Bag"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- HUD button in the shared column (Lib/Responsive), above the Store.
	local open = Responsive.dockButton("OpenBag", "🎒", "Bag", BAG_COLOR, 2)

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
	title.Text = "Bag"
	Responsive.capText(title, 30)

	local close = button("Close", panel)
	close.Text = "X"
	close.BackgroundColor3 = MUTED_COLOR
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 8)
	close.Size = UDim2.fromOffset(MIN_TOUCH_SIZE, MIN_TOUCH_SIZE)

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(10, 56)
	list.Size = UDim2.new(1, -20, 1, -66)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = 6
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local function note(text: string, order: number, height: number): ()
		local line = label("Note", list)
		line.LayoutOrder = order
		line.Size = UDim2.new(1, 0, 0, height)
		-- Grows when the text wraps onto more lines (narrow phone screens).
		line.AutomaticSize = Enum.AutomaticSize.Y
		line.TextScaled = false
		line.TextSize = 16
		line.TextWrapped = true
		line.TextYAlignment = Enum.TextYAlignment.Top
		line.TextTransparency = 0.15
		line.Text = text
	end

	local function render(): ()
		for _, child in list:GetChildren() do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
		local snapshot = ProgressController.get()
		local bag: { [string]: number } = if snapshot then snapshot.Bag else {}
		local total = 0
		for _, count in bag do
			total += count
		end
		Responsive.setButtonLabel(
			open,
			if total > 0 then string.format("Bag (%d)", total) else "Bag"
		)

		note(
			"Items you bought, got as gifts or won wait here. Use a boost when it suits you: it then counts down while you play, and the strongest boost of each kind applies. Eggs hatch at the Pet Incubation Center outside: stand by an incubator and tap Incubate.",
			1,
			62
		)
		-- Store order, so the list is stable.
		local order = 10
		for _, product in StoreConfig.Products do
			local count = bag[product.Key]
			if count == nil or count < 1 then
				continue
			end
			order += 1
			local row = Instance.new("Frame")
			row.Name = product.Key
			row.LayoutOrder = order
			row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
			row.BackgroundColor3 = ROW_COLOR
			row.Parent = list
			corner(row)

			local name = label("Name", row)
			name.Position = UDim2.fromOffset(12, 10)
			name.Size = UDim2.new(0.66, -12, 0, ROW_HEIGHT - 20)
			name.Text = string.format("%s  x%d", BagRules.itemText(product), count)

			local use = button("Use", row)
			use.AnchorPoint = Vector2.new(1, 0.5)
			use.Position = UDim2.new(1, -10, 0.5, 0)
			use.Size = UDim2.new(0.28, 0, 0, MIN_TOUCH_SIZE)
			use.BackgroundColor3 = USE_COLOR
			use.Text = if product.Kind == "Egg"
				then "Incubate"
				elseif product.Kind == "MysteryHammer" or product.Kind == "Bundle" then "Open"
				else "Use"
			use.Activated:Connect(function()
				useRemote:FireServer(product.Key)
			end)
		end
		if order == 10 then
			note(
				"Your Bag is empty. Items from the Store and gifts from friends show up here.",
				2,
				44
			)
		end
	end

	ProgressController.Changed:Connect(render)
	render()

	open.Activated:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			render()
		end
	end)
	close.Activated:Connect(function()
		panel.Visible = false
	end)
	openPanel = function()
		panel.Visible = true
		render()
	end

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- Opens the Bag panel (e.g. from the Player Panel). Using an item still
-- goes through Bag.Use and the server's checks.
function BagController.open(): ()
	if openPanel then
		openPanel()
	end
end

return BagController
