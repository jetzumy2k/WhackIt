--!strict
--[[
	Robux store UI (docs/STORE.md). Display only: buttons send a product key on
	Store.RequestPurchase; the server decides whether to open Roblox's purchase
	prompt, and PurchaseService delivers what was paid for.

	Store.State (from the server) says whether the store is open, whether this
	player may be offered the Mystery Hammer (PolicyService), and whether they
	are an admin, who also gets an "Admin" tab to open, close or schedule the
	store for every server.

	Since the visual overhaul (V4b) a PanelKit window with tabs and item
	cards (Lib/PanelKit.itemCard), like every newer panel; the friend picker
	for gifts is its own window with a search box.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BagRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BagRules"))
local PetConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("PetConfig"))
local StoreConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StoreConfig"))

local LocalTime = require(script.Parent.Parent.Lib.LocalTime)
local PanelKit = require(script.Parent.Parent.Lib.PanelKit)
local Responsive = require(script.Parent.Parent.Lib.Responsive)

local StoreController = {}

-- Set once the panel exists (start); lets the Player Panel open it.
local openPanel: (() -> ())? = nil

local C = PanelKit.Colors
local STORE_COLOR = Color3.fromRGB(230, 170, 40)
local ROBUX_COLOR = Color3.fromRGB(80, 190, 90)
local GIFT_COLOR = Color3.fromRGB(220, 90, 150)
local CARD_WIDTH = 170
local CARD_HEIGHT = 222
local KIND_LOOK: { [string]: { Icon: string, Accent: Color3 } } = {
	Xp = { Icon = "✨", Accent = Color3.fromRGB(110, 150, 255) },
	Damage = { Icon = "💥", Accent = Color3.fromRGB(230, 110, 80) },
	CritDamage = { Icon = "🎯", Accent = Color3.fromRGB(240, 185, 70) },
}
local RARITY_ACCENT: { [string]: Color3 } = {
	Common = Color3.fromRGB(150, 210, 120),
	Rare = Color3.fromRGB(90, 160, 255),
	Mythical = Color3.fromRGB(220, 120, 255),
}
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

local TABS = {
	{ Id = "Xp", Label = "✨ XP Boost" },
	{ Id = "Damage", Label = "💥 Damage" },
	{ Id = "CritDamage", Label = "🎯 Crit Dmg" },
	{ Id = "Bundle", Label = "📦 Bundles" },
	{ Id = "Egg", Label = "🥚 Eggs" },
	{ Id = "MysteryHammer", Label = "🎁 Mystery" },
	{ Id = "Admin", Label = "🛡️ Admin" },
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
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	-- HUD button in the shared column (Lib/Responsive), above Hammers.
	local open = Responsive.dockButton("OpenStore", "🛒", "Store", STORE_COLOR, 3)
	open.Visible = false

	local window = PanelKit.window({
		Name = "Store",
		Title = "🛒 Store",
		Subtitle = "Boosts, bundles, eggs and the Mystery Hammer. Everything goes to your Bag.",
		Accent = STORE_COLOR,
		DisplayOrder = 5,
	}, playerGui)
	local content = window.Content

	-- The friend picker for gifts: its own window, a search box that keeps
	-- its focus while typing, and the matching friends under it.
	local picker = PanelKit.window({
		Name = "GiftPicker",
		Title = "🎁 Send a gift",
		Subtitle = "Pick a Roblox friend. It waits for them if they're offline.",
		Accent = GIFT_COLOR,
		DisplayOrder = 6,
	}, playerGui)
	local search = Instance.new("TextBox")
	search.Name = "Search"
	search.LayoutOrder = 1
	search.Size = UDim2.new(1, 0, 0, PanelKit.ROW_HEIGHT)
	search.BackgroundColor3 = C.Field
	search.TextColor3 = C.Text
	search.PlaceholderText = "Search friends"
	search.PlaceholderColor3 = C.Muted
	search.Font = PanelKit.FONT_BOLD
	search.TextSize = 18
	search.ClearTextOnFocus = false
	search.Text = ""
	search.Parent = picker.Content
	local searchCorner = Instance.new("UICorner")
	searchCorner.CornerRadius = UDim.new(0, 8)
	searchCorner.Parent = search
	local rows = Instance.new("Frame")
	rows.Name = "Friends"
	rows.LayoutOrder = 2
	rows.BackgroundTransparency = 1
	rows.Size = UDim2.fromScale(1, 0)
	rows.AutomaticSize = Enum.AutomaticSize.Y
	rows.Parent = picker.Content
	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.Padding = UDim.new(0, 6)
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowsLayout.Parent = rows

	local giftProduct: StoreConfig.Product? = nil
	local function showFriends(): ()
		for _, child in rows:GetChildren() do
			if child:IsA("GuiObject") then
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
				local choice = PanelKit.button(
					rows,
					string.format("%s (@%s)", friend.DisplayName, friend.Username),
					C.Card
				)
				choice.LayoutOrder = index
				choice.TextXAlignment = Enum.TextXAlignment.Left
				local inset = Instance.new("UIPadding")
				inset.PaddingLeft = UDim.new(0, 12)
				inset.Parent = choice
				choice.Activated:Connect(function()
					local productToGift = giftProduct
					if productToGift then
						picker:close()
						giftRemote:FireServer(productToGift.Key, friend.Id)
					end
				end)
			end
		end
		if shown == 0 then
			PanelKit.notice(
				rows,
				"Empty",
				if #friends == 0 then "No Roblox friends found." else "No friend matches that name."
			)
		end
	end
	search:GetPropertyChangedSignal("Text"):Connect(function()
		if picker:isOpen() then
			showFriends()
		end
	end)
	local function openFriendPicker(product: StoreConfig.Product, text: string): ()
		giftProduct = product
		picker.Subtitle.Text = "Gift "
			.. text
			.. " to a Roblox friend. It waits for them if they're offline."
		search.Text = ""
		picker:open()
		showFriends()
	end

	-- Buy (and, when giftable, Gift) on a card; the live price fills in.
	local function priceButton(button: TextButton, product: StoreConfig.Product, prefix: string): ()
		button.Text = prefix .. "R$ " .. product.SuggestedPrice
		PanelKit.setColor(button, ROBUX_COLOR)
		button.Activated:Connect(function()
			requestRemote:FireServer(product.Key)
		end)
		task.spawn(function()
			local price = priceOf(product)
			if button.Parent ~= nil then
				button.Text = prefix .. "R$ " .. price
			end
		end)
	end
	local function productCard(
		grid: Frame,
		product: StoreConfig.Product,
		title: string,
		detail: string,
		icon: string,
		accent: Color3
	): ()
		local card = PanelKit.itemCard(grid, title, detail, icon, accent)
		card.Frame.Name = product.Key
		priceButton(card.Button, product, "Buy · ")
		if BagRules.isGiftable(product) then
			local gift = Instance.new("TextButton")
			gift.Name = "Gift"
			gift.AnchorPoint = Vector2.new(0, 0)
			gift.Position = UDim2.fromOffset(4, 4)
			gift.Size = UDim2.fromOffset(64, 26)
			gift.BackgroundColor3 = GIFT_COLOR
			gift.TextColor3 = C.Text
			gift.Font = PanelKit.FONT_BOLD
			gift.TextSize = 14
			gift.Text = "🎁 Gift"
			gift.ZIndex = 3
			gift.Parent = card.Picture
			local giftCorner = Instance.new("UICorner")
			giftCorner.CornerRadius = UDim.new(0, 13)
			giftCorner.Parent = gift
			gift.Activated:Connect(function()
				openFriendPicker(product, title)
			end)
		end
	end

	local function adminPage(): ()
		local section = PanelKit.section(content, "Store for every server", false, true)
		local scheduleText = if state.Mode == "Schedule"
			then string.format(
				"Schedule: %s to %s (your local time)",
				LocalTime.format(state.StartsAt),
				LocalTime.format(state.EndsAt)
			)
			else "Mode: " .. state.Mode
		PanelKit.text(
			section.Body,
			string.format(
				"The store is %s for players right now. %s. Changes apply to every server; purchases already paid for are always delivered.",
				if state.Open then "OPEN" else "CLOSED",
				scheduleText
			)
		)
		local modeRow = PanelKit.row(section.Body)
		local onButton = PanelKit.button(modeRow, "Open now", C.Good)
		onButton.Size = UDim2.new(0.5, -4, 1, 0)
		onButton.Activated:Connect(function()
			adminRemote:FireServer({ Mode = "On" })
		end)
		local offButton = PanelKit.button(modeRow, "Close now", C.Danger)
		offButton.Size = UDim2.new(0.5, -4, 1, 0)
		offButton.Activated:Connect(function()
			adminRemote:FireServer({ Mode = "Off" })
		end)

		local schedule = PanelKit.section(content, "Open it between two times", false, true)
		PanelKit.text(schedule.Body, "YYYY-MM-DD HH:MM, your local time.", "Muted")
		local function timeBox(name: string, value: number): TextBox
			local box = Instance.new("TextBox")
			box.Name = name
			box.Size = UDim2.new(1, 0, 0, PanelKit.ROW_HEIGHT)
			box.BackgroundColor3 = C.Field
			box.TextColor3 = C.Text
			box.PlaceholderText = name .. "  e.g. 2026-12-24 18:00"
			box.PlaceholderColor3 = C.Muted
			box.Font = PanelKit.FONT_BOLD
			box.TextSize = 18
			box.ClearTextOnFocus = false
			box.Text = LocalTime.format(value)
			box.Parent = schedule.Body
			local boxCorner = Instance.new("UICorner")
			boxCorner.CornerRadius = UDim.new(0, 8)
			boxCorner.Parent = box
			return box
		end
		local startBox = timeBox("Start", state.StartsAt)
		local endBox = timeBox("End", state.EndsAt)
		local scheduleButton = PanelKit.button(schedule.Body, "Set schedule", C.Primary)
		local errorLine = PanelKit.text(schedule.Body, "", "Muted")
		errorLine.TextColor3 = Color3.fromRGB(255, 140, 120)
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

	-- Tabs some players don't see (Mystery and eggs need PolicyService, Admin an admin).
	local function setTabVisible(id: string, visible: boolean): ()
		local tab = window.Frame:FindFirstChild(id, true)
		if tab and tab:IsA("GuiObject") then
			tab.Visible = visible
		end
	end

	local function render(): ()
		open.Visible = state.Open or state.IsAdmin
		setTabVisible("MysteryHammer", state.MysteryAllowed)
		setTabVisible("Egg", state.MysteryAllowed)
		setTabVisible("Admin", state.IsAdmin)
		if
			((activeTab == "MysteryHammer" or activeTab == "Egg") and not state.MysteryAllowed)
			or (activeTab == "Admin" and not state.IsAdmin)
		then
			activeTab = "Xp"
		end
		window:selectTab(activeTab)
		if not window:isOpen() then
			return
		end
		window:clear()

		if activeTab == "Admin" then
			adminPage()
			return
		end
		if not state.Open then
			PanelKit.notice(content, "Locked", "The store is closed right now. Check back later!")
			return
		end

		if activeTab == "Bundle" then
			PanelKit.text(
				content,
				"Each bundle puts its boosts in your Bag as separate items. Use them one at a time, whenever you like. Bundles can't be gifted.",
				"Muted"
			)
			local any = false
			for _, product in StoreConfig.Products do
				if product.Kind == "Bundle" and product.ProductId ~= 0 then
					any = true
					local section = PanelKit.section(
						content,
						"📦 " .. BagRules.itemText(product),
						false,
						true
					)
					PanelKit.text(section.Body, table.concat(BagRules.contentsLines(product), "\n"))
					priceButton(
						PanelKit.button(section.Body, "", ROBUX_COLOR),
						product,
						"Purchase · "
					)
				end
			end
			if not any then
				PanelKit.notice(content, "Empty", "Coming soon.")
			end
			return
		end
		if activeTab == "Egg" then
			PanelKit.text(content, eggOddsText(), "Muted")
			local grid = PanelKit.grid(content, CARD_WIDTH, CARD_HEIGHT)
			local any = false
			for _, product in StoreConfig.Products do
				if product.Kind == "Egg" and product.ProductId ~= 0 then
					any = true
					local accent = if product.Rarity and RARITY_ACCENT[product.Rarity]
						then RARITY_ACCENT[product.Rarity]
						else STORE_COLOR
					productCard(
						grid,
						product,
						BagRules.itemText(product),
						"Hatches into a pet at the incubators outside.",
						"🥚",
						accent
					)
				end
			end
			if not any then
				PanelKit.notice(content, "Empty", "Coming soon.")
			end
			return
		end
		if activeTab == "MysteryHammer" then
			PanelKit.text(content, oddsText(), "Muted")
			local mystery = StoreConfig.ByKey.mystery_hammer
			if mystery and mystery.ProductId ~= 0 then
				local grid = PanelKit.grid(content, CARD_WIDTH, CARD_HEIGHT)
				productCard(
					grid,
					mystery,
					StoreConfig.Mystery.DisplayName,
					"A hammer with surprise bonus stats, yours to keep.",
					"🎁",
					Color3.fromRGB(255, 120, 170)
				)
			else
				PanelKit.notice(content, "Empty", "Coming soon.")
			end
			return
		end

		PanelKit.text(
			content,
			"Bought boosts go to your Bag: use them when you like. 🎁 Gift sends one to a Roblox friend (it waits for them if they're offline). Active boosts count down only while you play.",
			"Muted"
		)
		local grid = PanelKit.grid(content, CARD_WIDTH, CARD_HEIGHT)
		local any = false
		local look = KIND_LOOK[activeTab] or { Icon = "🛒", Accent = STORE_COLOR }
		for _, product in StoreConfig.Products do
			if product.Kind == activeTab and product.ProductId ~= 0 then
				any = true
				productCard(
					grid,
					product,
					string.format("+%d%% %s", product.Percent, KIND_TEXT[product.Kind]),
					durationText(product.Seconds) .. " of play · goes to your Bag",
					look.Icon,
					look.Accent
				)
			end
		end
		if not any then
			PanelKit.notice(content, "Empty", "Coming soon.")
		end
	end

	window:setTabs(TABS, function(id: string)
		activeTab = id
		render()
	end)
	window:onOpen(function()
		task.defer(render)
	end)

	stateRemote.OnClientEvent:Connect(function(payload: unknown)
		local parsed = parseState(payload)
		if parsed then
			state = parsed
			if not state.Open and not state.IsAdmin and window:isOpen() then
				window:close()
			end
			render()
		end
	end)
	render()

	open.Activated:Connect(function()
		window:toggle()
	end)
	openPanel = function()
		if window:isOpen() then
			render()
		else
			window:open()
		end
	end
end

-- Opens the Robux Store panel (e.g. from the Player Panel). Display only:
-- purchases still go through Roblox's prompt and the server's checks.
function StoreController.open(): ()
	if openPanel then
		openPanel()
	end
end

return StoreController
