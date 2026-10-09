--!strict
--[[
	Robux store UI (docs/STORE.md). Display only: buttons send a product key on
	Store.RequestPurchase; the server decides whether to open Roblox's purchase
	prompt, and PurchaseService delivers what was paid for.

	Store.State (from the server) says whether the store is open, whether this
	player may be offered the Mystery Hammer (PolicyService), and whether they
	are an admin, who also gets an "Admin" tab to open, close or schedule the
	store for every server.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BagRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BagRules"))
local PetConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("PetConfig"))
local StoreConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StoreConfig"))

local LocalTime = require(script.Parent.Parent.Lib.LocalTime)
local GamepadNav = require(script.Parent.Parent.Lib.GamepadNav)
local Responsive = require(script.Parent.Parent.Lib.Responsive)

local StoreController = {}

-- Set once the panel exists (start); lets the Player Panel open it.
local openPanel: (() -> ())? = nil

local PANEL_COLOR = Color3.fromRGB(30, 30, 40)
local ROW_COLOR = Color3.fromRGB(48, 48, 62)
local TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local ROBUX_COLOR = Color3.fromRGB(80, 190, 90)
local TAB_COLOR = Color3.fromRGB(70, 70, 90)
local TAB_ACTIVE_COLOR = Color3.fromRGB(70, 140, 230)
local STORE_COLOR = Color3.fromRGB(230, 170, 40)
local MUTED_COLOR = Color3.fromRGB(90, 90, 100)
local ROW_HEIGHT = 56
local MIN_TOUCH_SIZE = 44
-- Fixed tab width: the tab strip scrolls when they don't all fit.
local TAB_WIDTH = 96
local GIFT_COLOR = Color3.fromRGB(220, 90, 150)
-- Friends shown in the gift picker (the friends list is read once per session).
local MAX_FRIENDS = 200

type Friend = { Id: number, Username: string, DisplayName: string }
local friendsCache: { Friend }? = nil

-- The local player's Roblox friends, sorted by display name. Yields the first time.
local function loadFriends(): { Friend }
	local cached = friendsCache
	if cached then
		return cached
	end
	local friends: { Friend } = {}
	local ok, pages = pcall(function()
		return Players:GetFriendsAsync(Players.LocalPlayer.UserId)
	end)
	if ok and pages then
		while #friends < MAX_FRIENDS do
			for _, entry in pages:GetCurrentPage() do
				if
					typeof(entry) == "table"
					and typeof(entry.Id) == "number"
					and typeof(entry.Username) == "string"
				then
					table.insert(friends, {
						Id = entry.Id,
						Username = entry.Username,
						DisplayName = if typeof(entry.DisplayName) == "string"
							then entry.DisplayName
							else entry.Username,
					})
				end
			end
			if pages.IsFinished then
				break
			end
			local advanced = pcall(function()
				pages:AdvanceToNextPageAsync()
			end)
			if not advanced then
				break
			end
		end
		table.sort(friends, function(a, b)
			return string.lower(a.DisplayName) < string.lower(b.DisplayName)
		end)
		friendsCache = friends
	end
	return friends
end

local openFriendPicker: (product: StoreConfig.Product, text: string) -> ()

local TABS = {
	{ Id = "Xp", Label = "XP Boost" },
	{ Id = "Damage", Label = "Damage" },
	{ Id = "CritDamage", Label = "Crit Dmg" },
	{ Id = "Bundle", Label = "Bundles" },
	{ Id = "Egg", Label = "Eggs" },
	{ Id = "MysteryHammer", Label = "Mystery" },
	{ Id = "Admin", Label = "Admin" },
}

local KIND_TEXT: { [string]: string } = { Xp = "XP", Damage = "Damage", CritDamage = "Crit Damage" }

type State = {
	Open: boolean,
	MysteryAllowed: boolean,
	IsAdmin: boolean,
	Mode: string,
	StartsAt: number,
	EndsAt: number,
}

local localPlayer = Players.LocalPlayer

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

local function parseState(payload: unknown): State?
	if typeof(payload) ~= "table" then
		return nil
	end
	local data = payload :: { [string]: unknown }
	return {
		Open = data.Open == true,
		MysteryAllowed = data.MysteryAllowed == true,
		IsAdmin = data.IsAdmin == true,
		Mode = if typeof(data.Mode) == "string" then data.Mode else "Off",
		StartsAt = if typeof(data.StartsAt) == "number" then data.StartsAt else 0,
		EndsAt = if typeof(data.EndsAt) == "number" then data.EndsAt else 0,
	}
end

-- The live Creator Hub price, falling back to the suggested price.
local priceCache: { [number]: number } = {}
local function priceOf(product: StoreConfig.Product): number
	local cached = priceCache[product.ProductId]
	if cached then
		return cached
	end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfoAsync(product.ProductId, Enum.InfoType.Product)
	end)
	local price = if ok
			and typeof(info) == "table"
			and typeof(info.PriceInRobux) == "number"
		then info.PriceInRobux
		else product.SuggestedPrice
	priceCache[product.ProductId] = price
	return price
end

local function durationText(seconds: number): string
	if seconds >= 3600 then
		return string.format("%d hour%s", seconds // 3600, if seconds >= 7200 then "s" else "")
	end
	return string.format("%d min", seconds // 60)
end

local function oddsText(): string
	local mystery = StoreConfig.Mystery
	local bonusCount = mystery.BonusDamageMaxPercent - mystery.BonusDamageMinPercent + 1
	local critCount = mystery.CritDamageMaxPercent - mystery.CritDamageMinPercent + 1
	return string.format(
		"Base damage %d (always). Odds: bonus damage +%d%% to +%d%%, each value 1 in %d (%.1f%%).  Crit damage +%d%% to +%d%%, each 1 in %d (%.1f%%). It waits in your Bag; the bonuses are rolled once when you open it and never change, and it's yours to keep.",
		mystery.BaseDamage,
		mystery.BonusDamageMinPercent,
		mystery.BonusDamageMaxPercent,
		bonusCount,
		100 / bonusCount,
		mystery.CritDamageMinPercent,
		mystery.CritDamageMaxPercent,
		critCount,
		100 / critCount
	)
end

-- Odds for each egg, as Roblox requires for paid random items.
local function eggOddsText(): string
	local lines: { string } = {}
	for _, rarity in PetConfig.Rarities do
		local parts: { string } = {}
		local odds = PetConfig.EggOdds[rarity]
		for _, species in PetConfig.Species do
			local weight = if odds then odds[species.Id] else nil
			if weight and weight > 0 then
				table.insert(parts, string.format("%s %d%%", species.Name, weight))
			end
		end
		table.insert(lines, string.format("%s Egg: %s.", rarity, table.concat(parts, ", ")))
	end
	local random = PetConfig.RareRandomBuff
	table.insert(
		lines,
		string.format(
			"Rare pets also get one extra buff of another kind, equally likely: +%d-%d%% XP, +%d-%d%% Damage or +%d-%d%% Crit Damage (each whole value equally likely). Eggs wait in your Bag and hatch in an incubator outside in %d seconds.",
			random.Xp.Min,
			random.Xp.Max,
			random.Damage.Min,
			random.Damage.Max,
			random.CritDamage.Min,
			random.CritDamage.Max,
			PetConfig.IncubationSeconds
		)
	)
	return "Odds: " .. table.concat(lines, "  ")
end

function StoreController.start(): ()
	local remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Store")
	local requestRemote = remotes:WaitForChild("RequestPurchase")
	local giftRemote = remotes:WaitForChild("RequestGift")
	local adminRemote = remotes:WaitForChild("AdminSetMode")
	local stateRemote = remotes:WaitForChild("State")
	assert(
		requestRemote:IsA("RemoteEvent")
			and giftRemote:IsA("RemoteEvent")
			and adminRemote:IsA("RemoteEvent")
			and stateRemote:IsA("RemoteEvent"),
		"Store remotes must be RemoteEvents"
	)

	local state: State = {
		Open = false,
		MysteryAllowed = false,
		IsAdmin = false,
		Mode = "Off",
		StartsAt = 0,
		EndsAt = 0,
	}
	local activeTab = "Xp"

	local gui = Instance.new("ScreenGui")
	gui.Name = "Store"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- HUD button in the shared column (Lib/Responsive), above Hammers.
	local open = Responsive.dockButton("OpenStore", "🛒", "Store", STORE_COLOR, 3)
	open.Visible = false

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.65, 0.7)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.Visible = false
	panel.Parent = gui
	corner(panel)
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MinSize = Vector2.new(320, 300)
	sizeLimit.MaxSize = Vector2.new(620, 520)
	sizeLimit.Parent = panel
	Responsive.fitPopup(panel, sizeLimit, Vector2.new(0.65, 0.7))

	local title = label("Title", panel)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -90, 0, 34)
	title.Text = "Store"
	Responsive.capText(title, 30)

	local close = button("Close", panel)
	close.Text = "X"
	close.BackgroundColor3 = MUTED_COLOR
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 8)
	close.Size = UDim2.fromOffset(MIN_TOUCH_SIZE, MIN_TOUCH_SIZE)

	-- Scrolls sideways when the tabs don't all fit (narrow phone screens).
	local tabBar = Instance.new("ScrollingFrame")
	tabBar.Name = "Tabs"
	tabBar.BackgroundTransparency = 1
	tabBar.BorderSizePixel = 0
	tabBar.Position = UDim2.fromOffset(10, 56)
	tabBar.Size = UDim2.new(1, -20, 0, MIN_TOUCH_SIZE)
	tabBar.ScrollingDirection = Enum.ScrollingDirection.X
	tabBar.ScrollBarThickness = 0
	tabBar.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabBar.CanvasSize = UDim2.new()
	tabBar.Parent = panel
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabBar

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(10, 108)
	list.Size = UDim2.new(1, -20, 1, -118)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = 6
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local function note(text: string, order: number, height: number): TextLabel
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
		return line
	end

	-- Friend picker for gifts, drawn over the store list.
	local picker = Instance.new("Frame")
	picker.Name = "GiftPicker"
	picker.BackgroundColor3 = PANEL_COLOR
	picker.Position = UDim2.fromOffset(0, 0)
	picker.Size = UDim2.fromScale(1, 1)
	picker.ZIndex = 5
	picker.Visible = false
	picker.Parent = panel
	corner(picker)
	local pickerTitle = label("Title", picker)
	pickerTitle.Position = UDim2.fromOffset(16, 10)
	pickerTitle.Size = UDim2.new(1, -90, 0, 30)
	pickerTitle.ZIndex = 6
	local pickerClose = button("Cancel", picker)
	pickerClose.Text = "X"
	pickerClose.BackgroundColor3 = MUTED_COLOR
	pickerClose.AnchorPoint = Vector2.new(1, 0)
	pickerClose.Position = UDim2.new(1, -10, 0, 8)
	pickerClose.Size = UDim2.fromOffset(MIN_TOUCH_SIZE, MIN_TOUCH_SIZE)
	pickerClose.ZIndex = 6
	pickerClose.Activated:Connect(function()
		picker.Visible = false
	end)
	local search = Instance.new("TextBox")
	search.Name = "Search"
	search.Position = UDim2.fromOffset(10, 56)
	search.Size = UDim2.new(1, -20, 0, MIN_TOUCH_SIZE)
	search.BackgroundColor3 = ROW_COLOR
	search.TextColor3 = TEXT_COLOR
	search.PlaceholderText = "Search friends"
	search.Font = Enum.Font.FredokaOne
	search.TextSize = 18
	search.ClearTextOnFocus = false
	search.Text = ""
	search.ZIndex = 6
	search.Parent = picker
	corner(search)
	local friendList = Instance.new("ScrollingFrame")
	friendList.Name = "Friends"
	friendList.BackgroundTransparency = 1
	friendList.BorderSizePixel = 0
	friendList.Position = UDim2.fromOffset(10, 108)
	friendList.Size = UDim2.new(1, -20, 1, -118)
	friendList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	friendList.CanvasSize = UDim2.new()
	friendList.ScrollBarThickness = 6
	friendList.ZIndex = 6
	friendList.Parent = picker
	local friendLayout = Instance.new("UIListLayout")
	friendLayout.Padding = UDim.new(0, 6)
	friendLayout.SortOrder = Enum.SortOrder.LayoutOrder
	friendLayout.Parent = friendList

	local giftProduct: StoreConfig.Product? = nil
	local function showFriends(): ()
		for _, child in friendList:GetChildren() do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
		local friends = loadFriends()
		local query = string.lower(search.Text)
		local shown = 0
		for index, friend in friends do
			local matches = query == ""
				or string.find(string.lower(friend.DisplayName), query, 1, true) ~= nil
				or string.find(string.lower(friend.Username), query, 1, true) ~= nil
			if matches then
				shown += 1
				local choice = button("Friend", friendList)
				choice.LayoutOrder = index
				choice.Size = UDim2.new(1, -8, 0, MIN_TOUCH_SIZE)
				choice.BackgroundColor3 = ROW_COLOR
				choice.TextXAlignment = Enum.TextXAlignment.Left
				choice.ZIndex = 7
				choice.Text = string.format("  %s (@%s)", friend.DisplayName, friend.Username)
				choice.Activated:Connect(function()
					local productToGift = giftProduct
					if productToGift then
						picker.Visible = false
						giftRemote:FireServer(productToGift.Key, friend.Id)
					end
				end)
			end
		end
		if shown == 0 then
			local empty = label("Empty", friendList)
			empty.Size = UDim2.new(1, 0, 0, 30)
			empty.ZIndex = 7
			empty.Text = if #friends == 0
				then "No Roblox friends found."
				else "No friend matches that name."
		end
	end
	search:GetPropertyChangedSignal("Text"):Connect(function()
		if picker.Visible then
			showFriends()
		end
	end)

	function openFriendPicker(product: StoreConfig.Product, text: string): ()
		giftProduct = product
		pickerTitle.Text = "Gift " .. text .. " to..."
		search.Text = ""
		picker.Visible = true
		showFriends()
	end

	local function productRow(product: StoreConfig.Product, text: string, order: number): ()
		local row = Instance.new("Frame")
		row.Name = product.Key
		row.LayoutOrder = order
		row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		row.BackgroundColor3 = ROW_COLOR
		row.Parent = list
		corner(row)

		local giftable = BagRules.isGiftable(product)
		local name = label("Name", row)
		name.Position = UDim2.fromOffset(12, 10)
		name.Size = UDim2.new(if giftable then 0.46 else 0.62, -12, 0, ROW_HEIGHT - 20)
		name.Text = text

		if giftable then
			local gift = button("Gift", row)
			gift.AnchorPoint = Vector2.new(1, 0.5)
			gift.Position = UDim2.new(0.7, -14, 0.5, 0)
			gift.Size = UDim2.new(0.2, 0, 0, MIN_TOUCH_SIZE)
			gift.BackgroundColor3 = GIFT_COLOR
			gift.Text = "Gift"
			gift.Activated:Connect(function()
				openFriendPicker(product, text)
			end)
		end

		local buy = button("Buy", row)
		buy.AnchorPoint = Vector2.new(1, 0.5)
		buy.Position = UDim2.new(1, -10, 0.5, 0)
		buy.Size = UDim2.new(if giftable then 0.28 else 0.33, 0, 0, MIN_TOUCH_SIZE)
		buy.BackgroundColor3 = ROBUX_COLOR
		buy.Text = "R$ " .. product.SuggestedPrice
		buy.Activated:Connect(function()
			requestRemote:FireServer(product.Key)
		end)
		task.spawn(function()
			local price = priceOf(product)
			if buy.Parent ~= nil then
				buy.Text = "R$ " .. price
			end
		end)
	end

	-- A bundle card: name, what it contains, and one purchase button.
	local function bundleRow(product: StoreConfig.Product, order: number): ()
		local card = Instance.new("Frame")
		card.Name = product.Key
		card.LayoutOrder = order
		card.Size = UDim2.fromScale(1, 0)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.BackgroundColor3 = ROW_COLOR
		card.Parent = list
		corner(card)
		local inset = Instance.new("UIPadding")
		inset.PaddingLeft = UDim.new(0, 12)
		inset.PaddingRight = UDim.new(0, 12)
		inset.PaddingTop = UDim.new(0, 10)
		inset.PaddingBottom = UDim.new(0, 10)
		inset.Parent = card
		local cardLayout = Instance.new("UIListLayout")
		cardLayout.Padding = UDim.new(0, 6)
		cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
		cardLayout.Parent = card

		local name = label("Name", card)
		name.LayoutOrder = 1
		name.Size = UDim2.new(1, 0, 0, 30)
		name.Text = string.upper(BagRules.itemText(product))
		name.TextColor3 = STORE_COLOR
		Responsive.capText(name, 24)

		local contents = label("Contents", card)
		contents.LayoutOrder = 2
		contents.Size = UDim2.fromScale(1, 0)
		contents.AutomaticSize = Enum.AutomaticSize.Y
		contents.TextScaled = false
		contents.TextSize = 17
		contents.TextWrapped = true
		contents.TextYAlignment = Enum.TextYAlignment.Top
		contents.Text = table.concat(BagRules.contentsLines(product), "\n")

		local buy = button("Buy", card)
		buy.LayoutOrder = 3
		buy.Size = UDim2.new(1, 0, 0, MIN_TOUCH_SIZE)
		buy.BackgroundColor3 = ROBUX_COLOR
		buy.Text = "PURCHASE  R$ " .. product.SuggestedPrice
		buy.Activated:Connect(function()
			requestRemote:FireServer(product.Key)
		end)
		task.spawn(function()
			local price = priceOf(product)
			if buy.Parent ~= nil then
				buy.Text = "PURCHASE  R$ " .. price
			end
		end)
	end

	local function adminPage(): ()
		local scheduleText = if state.Mode == "Schedule"
			then string.format(
				"Schedule: %s to %s (your local time)",
				LocalTime.format(state.StartsAt),
				LocalTime.format(state.EndsAt)
			)
			else "Mode: " .. state.Mode
		note(
			string.format(
				"Store is %s for players right now. %s\nChanges apply to every server. Purchases already paid for are always delivered.",
				if state.Open then "OPEN" else "CLOSED",
				scheduleText
			),
			1,
			66
		)

		local modeRow = Instance.new("Frame")
		modeRow.Name = "Modes"
		modeRow.LayoutOrder = 2
		modeRow.BackgroundTransparency = 1
		modeRow.Size = UDim2.new(1, 0, 0, MIN_TOUCH_SIZE)
		modeRow.Parent = list
		local onButton = button("TurnOn", modeRow)
		onButton.Text = "Open now"
		onButton.BackgroundColor3 = ROBUX_COLOR
		onButton.Size = UDim2.fromScale(0.48, 1)
		onButton.Activated:Connect(function()
			adminRemote:FireServer({ Mode = "On" })
		end)
		local offButton = button("TurnOff", modeRow)
		offButton.Text = "Close now"
		offButton.BackgroundColor3 = Color3.fromRGB(200, 80, 80)
		offButton.AnchorPoint = Vector2.new(1, 0)
		offButton.Position = UDim2.fromScale(1, 0)
		offButton.Size = UDim2.fromScale(0.48, 1)
		offButton.Activated:Connect(function()
			adminRemote:FireServer({ Mode = "Off" })
		end)

		note("Or open it only between two times (YYYY-MM-DD HH:MM, your local time):", 3, 22)

		local function timeBox(name: string, order: number, value: number): TextBox
			local box = Instance.new("TextBox")
			box.Name = name
			box.LayoutOrder = order
			box.Size = UDim2.new(1, 0, 0, MIN_TOUCH_SIZE)
			box.BackgroundColor3 = ROW_COLOR
			box.TextColor3 = TEXT_COLOR
			box.PlaceholderText = name .. "  e.g. 2026-12-24 18:00"
			box.Font = Enum.Font.FredokaOne
			box.TextSize = 18
			box.ClearTextOnFocus = false
			box.Text = LocalTime.format(value)
			box.Parent = list
			corner(box)
			return box
		end
		local startBox = timeBox("Start", 4, state.StartsAt)
		local endBox = timeBox("End", 5, state.EndsAt)
		local errorLine = note("", 7, 22)
		errorLine.TextColor3 = Color3.fromRGB(255, 140, 120)

		local scheduleButton = button("SetSchedule", list)
		scheduleButton.LayoutOrder = 6
		scheduleButton.Size = UDim2.new(1, 0, 0, MIN_TOUCH_SIZE)
		scheduleButton.BackgroundColor3 = TAB_ACTIVE_COLOR
		scheduleButton.Text = "Set schedule"
		scheduleButton.Activated:Connect(function()
			local startsAt, endsAt = LocalTime.parse(startBox.Text), LocalTime.parse(endBox.Text)
			if startsAt == nil or endsAt == nil then
				errorLine.Text = "Use the format YYYY-MM-DD HH:MM for both times."
				return
			end
			errorLine.Text = ""
			adminRemote:FireServer({ Mode = "Schedule", StartsAt = startsAt, EndsAt = endsAt })
		end)
	end

	local tabButtons: { [string]: TextButton } = {}

	local function render(): ()
		for _, child in list:GetChildren() do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
		open.Visible = state.Open or state.IsAdmin
		tabButtons.MysteryHammer.Visible = state.MysteryAllowed
		tabButtons.Egg.Visible = state.MysteryAllowed
		tabButtons.Admin.Visible = state.IsAdmin
		if
			((activeTab == "MysteryHammer" or activeTab == "Egg") and not state.MysteryAllowed)
			or (activeTab == "Admin" and not state.IsAdmin)
		then
			activeTab = "Xp"
		end
		for id, tab in tabButtons do
			tab.BackgroundColor3 = if id == activeTab then TAB_ACTIVE_COLOR else TAB_COLOR
		end

		if activeTab == "Admin" then
			adminPage()
			return
		end
		if not state.Open then
			note("The store is closed right now. Check back later!", 1, 40)
			return
		end

		local order = 10
		if activeTab == "Bundle" then
			note(
				"Each bundle puts its boosts in your Bag as separate items. Use them one at a time, whenever you like. Bundles can't be gifted.",
				1,
				44
			)
			local any = false
			for _, product in StoreConfig.Products do
				if product.Kind == "Bundle" and product.ProductId ~= 0 then
					any = true
					order += 1
					bundleRow(product, order)
				end
			end
			if not any then
				note("Coming soon.", order, 30)
			end
			return
		end
		if activeTab == "Egg" then
			note(eggOddsText(), 1, 120)
			local any = false
			for _, product in StoreConfig.Products do
				if product.Kind == "Egg" and product.ProductId ~= 0 then
					any = true
					order += 1
					productRow(product, "🥚 " .. BagRules.itemText(product), order)
				end
			end
			if not any then
				note("Coming soon.", order, 30)
			end
			return
		end
		if activeTab == "MysteryHammer" then
			local mystery = StoreConfig.ByKey.mystery_hammer
			note(oddsText(), 1, 80)
			if mystery and mystery.ProductId ~= 0 then
				productRow(mystery, StoreConfig.Mystery.DisplayName, order)
			else
				note("Coming soon.", order, 30)
			end
			return
		end

		note(
			"Bought boosts go to your Bag: use them when you like. Gift sends one to a Roblox friend (it waits for them if they're offline). Active boosts count down only while you play.",
			1,
			62
		)
		local any = false
		for _, product in StoreConfig.Products do
			if product.Kind == activeTab and product.ProductId ~= 0 then
				any = true
				order += 1
				productRow(
					product,
					string.format(
						"+%d%% %s  -  %s",
						product.Percent,
						KIND_TEXT[product.Kind],
						durationText(product.Seconds)
					),
					order
				)
			end
		end
		if not any then
			note("Coming soon.", order, 30)
		end
	end

	for order, tab in TABS do
		local tabButton = button(tab.Id, tabBar)
		tabButton.LayoutOrder = order
		tabButton.Text = tab.Label
		tabButton.Size = UDim2.new(0, TAB_WIDTH, 1, 0)
		tabButton.Activated:Connect(function()
			activeTab = tab.Id
			render()
		end)
		tabButtons[tab.Id] = tabButton
	end

	stateRemote.OnClientEvent:Connect(function(payload: unknown)
		local parsed = parseState(payload)
		if parsed then
			state = parsed
			if not state.Open and not state.IsAdmin then
				panel.Visible = false
			end
			render()
		end
	end)
	render()

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
	GamepadNav.watch(picker, function()
		picker.Visible = false
	end)

	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

-- Opens the Robux Store panel (e.g. from the Player Panel). Display only:
-- purchases still go through Roblox's prompt and the server's checks.
function StoreController.open(): ()
	if openPanel then
		openPanel()
	end
end

return StoreController
