--!strict
--[[
	The Synthesis Machine window (docs/SYNTHESIS.md). Opened by the machine's
	"Synthesize" prompt in the lobby, or by a Synthesis Pick in the Bag.

	  * Tabs per category: Boosts, Eggs, Office Supplies, Hammers (Hammers
	    only explains why there is nothing to combine yet).
	  * A chamber at the top that charges while the server works and then
	    shows the result in its tier's colour (the last result stays on show).
	  * 1 · Choose items: cards for every eligible item the player owns (Add),
	    with Auto-fill and Clear; office supplies count unplaced copies only.
	  * 2 · Preview: what was picked (each with a remove button), what will
	    come out (guaranteed, or every possible result with equal odds), the
	    Synthesis Pick choice on random recipes, the coin fee, a message
	    saying what's missing, and the SYNTHESIZE button (only lit for a
	    valid recipe, with the coins, at the machine).
	  * How it works (open until the first synthesis) and a recipe list.
	The preview uses the same Shared/SynthesisRules.plan as the server, but
	the server checks everything again and picks the result
	(SynthesisService); this only asks and shows. Items leave the Bag only
	when the server says it's done (the next snapshot).

	Also: a one-time tip per recipe and session when the player newly has
	everything for it, and the window closes when the character dies.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BagRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BagRules"))
local FurnitureConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("FurnitureConfig"))
local StoreConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StoreConfig"))
local SynthesisConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("SynthesisConfig"))
local SynthesisRules =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SynthesisRules"))

local AnnouncementController = require(script.Parent.AnnouncementController)
local PanelKit = require(script.Parent.Parent.Lib.PanelKit)
local ProgressController = require(script.Parent.ProgressController)
local SynthesisMachineController = require(script.Parent.SynthesisMachineController)
local UIController = require(script.Parent.UIController)
local UiTokens = require(script.Parent.Parent.Lib.UiTokens)

local SynthesisController = {}

local C = PanelKit.Colors
local ACCENT = Color3.fromRGB(150, 110, 255)
local CARD_WIDTH = 160
local CARD_HEIGHT = 214
local REVEAL_SECONDS = 1.4
local ANSWER_TIMEOUT = 6
local NEAR_CHECK_SECONDS = 0.5
local PROMPT_NAME = "SynthesisPrompt"

local KIND_ACCENT: { [string]: Color3 } = {
	Xp = Color3.fromRGB(110, 150, 255),
	Damage = Color3.fromRGB(230, 110, 80),
	CritDamage = Color3.fromRGB(240, 185, 70),
	Egg = Color3.fromRGB(150, 210, 120),
}

local localPlayer = Players.LocalPlayer
local openWindow: (() -> ())? = nil

type Shown = { Icon: string, Label: string, Tier: string, Detail: string }

local function remote(folder: string, name: string): RemoteEvent
	local found = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(folder):WaitForChild(name)
	assert(found:IsA("RemoteEvent"), folder .. "." .. name .. " must be a RemoteEvent")
	return found
end

local function text(value: unknown): string
	return if typeof(value) == "string" then value else ""
end

local function tierColor(tier: string): Color3
	local info = SynthesisConfig.Tiers[tier]
	return if info then info.Color else ACCENT
end

local function corner(object: Instance, radius: number): ()
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = object
end

local function inventory(): SynthesisRules.Inventory?
	local snapshot = ProgressController.get()
	if snapshot == nil then
		return nil
	end
	return {
		Bag = snapshot.Bag,
		Furniture = snapshot.Furniture,
		Layout = snapshot.OfficeLayout,
		Coins = snapshot.Coins,
	}
end

-- Is this character standing at the machine (the server checks again)?
local function nearMachine(): boolean
	local position = SynthesisMachineController.promptPosition()
	local character = localPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if position == nil or root == nil or not root:IsA("BasePart") then
		return false
	end
	-- A little inside the server's reach, so a press here is never refused for it.
	return (root.Position - position).Magnitude <= SynthesisConfig.Reach - 1
end

local function itemName(key: string): string
	local product = StoreConfig.ByKey[key]
	if product then
		return BagRules.itemText(product)
	end
	local item = FurnitureConfig.ByKey[key]
	return if item then item.Name else key
end

local function itemLook(key: string): (string, Color3)
	local product = StoreConfig.ByKey[key]
	if product then
		local icon = if product.Kind == "Egg"
			then "🥚"
			elseif product.Kind == "Xp" then "✨"
			elseif product.Kind == "Damage" then "💥"
			elseif product.Kind == "CritDamage" then "🎯"
			else "🎒"
		return icon, KIND_ACCENT[product.Kind] or ACCENT
	end
	return "📦", Color3.fromRGB(120, 190, 200)
end

-- Eligible keys for `recipe` in a stable order (store order, or the supply pool).
local function candidateKeys(recipe: SynthesisRules.Recipe): { string }
	local keys: { string } = {}
	if recipe.Category == "Supplies" then
		for _, key in SynthesisConfig.SupplyPool do
			table.insert(keys, key)
		end
		return keys
	end
	for _, product in StoreConfig.Products do
		if SynthesisRules.accepts(recipe, product.Key) then
			table.insert(keys, product.Key)
		end
	end
	return keys
end

local function where(category: string): string
	if category == "Eggs" then
		return "Eggs come from the outdoor egg hunts, boss drops, the Lucky Capsule and the Store."
	elseif category == "Supplies" then
		return "Office supplies come from pickleball drops and the Lucky Capsule. Only supplies in storage (not placed in your office) can be used."
	end
	return "Boosts come from the Store, gifts, boss drops and the Lucky Capsule."
end

local function buildWindow(parent: Instance): ()
	local window = PanelKit.window({
		Name = "Synthesis",
		Title = "⚗️ Synthesis Machine",
		Subtitle = "Combine items to unlock something better!",
		Accent = ACCENT,
		DisplayOrder = 6,
	}, parent)
	local content = window.Content
	local synthesizeRemote = remote("Synthesis", "Synthesize")
	local purchaseRemote = remote("Store", "RequestPurchase")
	local pickProduct = StoreConfig.ByKey[SynthesisConfig.PickKey]

	local activeCategory: string = "Boosts"
	local recipeFor: { [string]: string } = {}
	local selection: SynthesisRules.Selection = {}
	local pickChoice: string? = nil
	local busy = false
	local busyToken = 0
	local message: string? = nil
	local shown: Shown? = nil
	local guideOpen: boolean? = nil
	local storeOpen = true
	local wasNear = false
	local opens = 0
	-- The chamber of the current page, for the charge and reveal.
	local chamber: TextLabel? = nil
	local chamberLabel: TextLabel? = nil

	local function currentRecipe(): SynthesisRules.Recipe?
		local list = SynthesisRules.recipesIn(activeCategory)
		local chosen = recipeFor[activeCategory]
		for _, recipe in list do
			if recipe.Id == chosen then
				return recipe
			end
		end
		return list[1]
	end

	local function selectedTotal(): number
		local total = 0
		for _, count in selection do
			total += count
		end
		return total
	end

	local function resetSelection(): ()
		selection = {}
		pickChoice = nil
		message = nil
	end

	local render: () -> ()

	-- The chamber: a glowing orb that holds the last result.
	local function stage(holder: Instance): ()
		local box = Instance.new("Frame")
		box.Name = "Stage"
		box.LayoutOrder = 1
		box.Size = UDim2.new(1, 0, 0, 150)
		box.BackgroundColor3 = C.Field
		box.Parent = holder
		corner(box, UiTokens.Radius.Card)
		local tint = if shown then tierColor(shown.Tier) else ACCENT
		local glow = Instance.new("UIGradient")
		glow.Rotation = 90
		glow.Color = ColorSequence.new(tint:Lerp(C.Field, 0.65), C.Field)
		glow.Parent = box

		local orb = Instance.new("TextLabel")
		orb.Name = "Chamber"
		orb.AnchorPoint = Vector2.new(0.5, 0.5)
		orb.Position = UDim2.fromScale(0.5, 0.4)
		orb.Size = UDim2.fromOffset(80, 80)
		orb.BackgroundColor3 = tint
		orb.Text = if shown then shown.Icon else "⚗️"
		orb.TextScaled = true
		orb.Font = UiTokens.Font.Title
		orb.TextColor3 = Color3.new(1, 1, 1)
		orb.Parent = box
		corner(orb, 999)
		local inset = Instance.new("UIPadding")
		inset.PaddingTop = UDim.new(0, 14)
		inset.PaddingBottom = UDim.new(0, 14)
		inset.PaddingLeft = UDim.new(0, 14)
		inset.PaddingRight = UDim.new(0, 14)
		inset.Parent = orb
		local ring = Instance.new("UIStroke")
		ring.Color = Color3.new(1, 1, 1)
		ring.Thickness = 3
		ring.Transparency = 0.3
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ring.Parent = orb

		local label = Instance.new("TextLabel")
		label.Name = "Result"
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.new(0.5, 0, 1, -8)
		label.Size = UDim2.new(1, -24, 0, 26)
		label.BackgroundTransparency = 1
		label.Font = PanelKit.FONT_BOLD
		label.TextColor3 = if shown then tint else C.Muted
		label.Text = if busy
			then "⚡ Synthesizing..."
			elseif shown then string.format("%s · %s", shown.Tier:upper(), shown.Label)
			else "Pick items below, then press SYNTHESIZE."
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Parent = box
		PanelKit.setTextSize(label, 19)
		chamber, chamberLabel = orb, label
	end

	local function chips(holder: Instance, inv: SynthesisRules.Inventory): ()
		local row = PanelKit.row(holder, 64)
		row.LayoutOrder = 2
		local picks = inv.Bag[SynthesisConfig.PickKey] or 0
		local values = {
			PanelKit.statTile(row, "Coins", string.format("💰 %d", inv.Coins), C.Gold),
			PanelKit.statTile(row, "Synthesis Picks", string.format("🎯 %d", picks)),
		}
		for _, value in values do
			local tile = value.Parent
			if tile and tile:IsA("Frame") then
				tile.Size = UDim2.new(0.5, -4, 1, 0)
			end
		end
	end

	local function guide(): ()
		local snapshot = ProgressController.get()
		local firstTime = snapshot ~= nil and snapshot.Synthesis.Total == 0
		local expanded = if guideOpen == nil then firstTime else guideOpen
		local section = PanelKit.section(
			content,
			"📜 How it works",
			true,
			expanded,
			function(open)
				guideOpen = open
			end
		)
		for _, line in
			{
				"1. Choose a tab and a recipe, then add the items you want to combine (or press Auto-fill).",
				"2. The preview shows exactly what can come out. GUARANTEED means one fixed result; RANDOM means each listed result is equally likely.",
				"3. Press SYNTHESIZE at the machine. Each synthesis costs a few coins.",
				"Boosts: all one kind gives that kind. Mixed kinds give a random kind. The strength is that of the weakest boost you put in, and only the length grows.",
				"Synthesis Picks (optional, from this window) let you choose the result of a random recipe.",
				"Your items are only used once the machine says it's done. If anything goes wrong, you keep them.",
			}
		do
			PanelKit.text(section.Body, line, "Muted")
		end
	end

	local function recipeChooser(list: { SynthesisRules.Recipe }, recipe: SynthesisRules.Recipe): ()
		if #list < 2 then
			return
		end
		local row = PanelKit.row(content, 44)
		for _, option in list do
			local button = PanelKit.button(
				row,
				SynthesisRules.recipeTitle(option),
				if option.Id == recipe.Id then ACCENT else C.Field
			)
			button.Size = UDim2.new(1 / #list, -8 * (#list - 1) / #list, 1, 0)
			PanelKit.setTextSize(button, 15)
			button.Activated:Connect(function()
				if busy or option.Id == recipe.Id then
					return
				end
				recipeFor[activeCategory] = option.Id
				resetSelection()
				render()
			end)
		end
	end

	local function itemsSection(recipe: SynthesisRules.Recipe, inv: SynthesisRules.Inventory): ()
		local total = selectedTotal()
		local section = PanelKit.section(
			content,
			string.format("1 · Choose items  (%d / %d)", total, recipe.Count),
			false,
			true
		)
		local tools = PanelKit.row(section.Body, 40)
		local auto = PanelKit.button(tools, "✨ Auto-fill", C.Primary)
		auto.Size = UDim2.new(0.5, -4, 1, 0)
		local clear = PanelKit.button(tools, "🧹 Clear selection", C.Neutral)
		clear.Size = UDim2.new(0.5, -4, 1, 0)
		local suggestion = SynthesisRules.suggest(recipe, inv)
		PanelKit.setDisabled(auto, busy or suggestion == nil)
		PanelKit.setDisabled(clear, busy or total == 0)
		auto.Activated:Connect(function()
			if busy or suggestion == nil then
				return
			end
			selection = table.clone(suggestion :: SynthesisRules.Selection)
			pickChoice = nil
			message = nil
			render()
		end)
		clear.Activated:Connect(function()
			if busy then
				return
			end
			resetSelection()
			render()
		end)

		local grid: Frame? = nil
		for _, key in candidateKeys(recipe) do
			local owned = SynthesisRules.owned(recipe, inv, key)
			if owned < 1 then
				continue
			end
			if grid == nil then
				grid = PanelKit.grid(section.Body, CARD_WIDTH, CARD_HEIGHT)
			end
			local icon, accent = itemLook(key)
			local chosen = selection[key] or 0
			local card = PanelKit.itemCard(
				grid :: Frame,
				itemName(key),
				if recipe.Category == "Supplies"
					then string.format("%d in storage", owned)
					else string.format("You have %d", owned),
				icon,
				accent
			)
			if chosen > 0 then
				PanelKit.setBadge(card, string.format("%d selected", chosen), ACCENT)
				card.Frame.BackgroundColor3 = ACCENT:Lerp(C.Card, 0.75)
			end
			local canAdd = chosen < owned and total < recipe.Count
			card.Button.Text = if canAdd
				then "＋ Add"
				elseif chosen > 0 then "－ Remove"
				else "Full"
			PanelKit.setColor(card.Button, if canAdd then C.Good else C.Danger)
			PanelKit.setDisabled(card.Button, busy or (not canAdd and chosen == 0))
			card.Button.Activated:Connect(function()
				if busy then
					return
				end
				if canAdd then
					selection[key] = chosen + 1
				elseif chosen > 1 then
					selection[key] = chosen - 1
				else
					selection[key] = nil
				end
				pickChoice = nil
				message = nil
				render()
			end)
		end
		if grid == nil then
			PanelKit.notice(
				section.Body,
				"Empty",
				"You don't have any items for this recipe yet. " .. where(recipe.Category)
			)
		end
	end

	local function pickArea(
		holder: Instance,
		plan: SynthesisRules.Plan,
		inv: SynthesisRules.Inventory
	): ()
		local picks = inv.Bag[SynthesisConfig.PickKey] or 0
		if picks > 0 then
			PanelKit.text(
				holder,
				string.format(
					"🎯 Choose the result with a Synthesis Pick (you have %d), or leave it to chance:",
					picks
				),
				"Heading"
			)
			local options = PanelKit.grid(holder, 150, 40)
			local chance = PanelKit.button(
				options,
				"🎲 Random",
				if pickChoice == nil then ACCENT else C.Field
			)
			chance.Activated:Connect(function()
				pickChoice = nil
				render()
			end)
			for _, outcome in plan.Outcomes do
				local choice = outcome.Choice
				local button = PanelKit.button(
					options,
					outcome.Icon .. " " .. outcome.Label,
					if pickChoice == choice then ACCENT else C.Field
				)
				PanelKit.setTextSize(button, 14)
				button.Activated:Connect(function()
					if not busy then
						pickChoice = choice
						render()
					end
				end)
			end
		elseif pickProduct and pickProduct.ProductId ~= 0 and storeOpen then
			local buy = PanelKit.button(
				holder,
				string.format(
					"🎯 Want a specific result? Get a Synthesis Pick (%d Robux)",
					pickProduct.SuggestedPrice
				),
				C.Primary
			)
			PanelKit.setTextSize(buy, 15)
			buy.Activated:Connect(function()
				purchaseRemote:FireServer(SynthesisConfig.PickKey)
			end)
			PanelKit.text(
				holder,
				"Optional. A Pick goes to your Bag and is used only when you choose a result here.",
				"Muted"
			)
		end
	end

	local function previewSection(recipe: SynthesisRules.Recipe, inv: SynthesisRules.Inventory): ()
		local section = PanelKit.section(content, "2 · Preview", false, true)
		local total = selectedTotal()

		-- What's in the machine, each with a remove button (stable order).
		local keys: { string } = {}
		for key in selection do
			table.insert(keys, key)
		end
		table.sort(keys)
		for _, key in keys do
			local count = selection[key]
			local row = PanelKit.row(section.Body, 36)
			local icon = itemLook(key)
			local name =
				PanelKit.text(row, string.format("%s  %d × %s", icon, count, itemName(key)))
			name.Size = UDim2.new(1, -52, 1, 0)
			name.AutomaticSize = Enum.AutomaticSize.None
			name.TextYAlignment = Enum.TextYAlignment.Center
			name.TextTruncate = Enum.TextTruncate.AtEnd
			local minus = PanelKit.button(row, "－", C.Danger)
			minus.Size = UDim2.fromOffset(44, 36)
			minus.Activated:Connect(function()
				if busy then
					return
				end
				if count > 1 then
					selection[key] = count - 1
				else
					selection[key] = nil
				end
				pickChoice = nil
				message = nil
				render()
			end)
		end

		local plan: SynthesisRules.Plan? = nil
		local reason: string? = nil
		if total < recipe.Count then
			reason = string.format(
				"Add %d more eligible item%s (%d / %d).",
				recipe.Count - total,
				if recipe.Count - total == 1 then "" else "s",
				total,
				recipe.Count
			)
		else
			plan, reason = SynthesisRules.plan(recipe.Id, selection, inv, pickChoice)
			if plan == nil and pickChoice ~= nil then
				-- The chosen result no longer fits (e.g. the pick was used): drop it.
				pickChoice = nil
				plan, reason = SynthesisRules.plan(recipe.Id, selection, inv, nil)
			end
		end

		if plan then
			local outcomes = plan.Outcomes
			if plan.Picked then
				local picked = plan.Picked :: SynthesisRules.Outcome
				PanelKit.text(
					section.Body,
					string.format(
						"✅ CHOSEN · %s %s (uses 1 Synthesis Pick)",
						picked.Icon,
						picked.Label
					),
					"Heading"
				)
			elseif plan.Random then
				PanelKit.text(
					section.Body,
					string.format("🎲 RANDOM · one of these, 1 in %d each:", #outcomes),
					"Heading"
				)
				for _, outcome in outcomes do
					PanelKit.text(section.Body, "    " .. outcome.Icon .. "  " .. outcome.Label)
				end
			else
				PanelKit.text(
					section.Body,
					string.format("✅ GUARANTEED · %s %s", outcomes[1].Icon, outcomes[1].Label),
					"Heading"
				)
			end
			if plan.Random then
				pickArea(section.Body, plan, inv)
			end
		elseif recipe.Category == "Boosts" then
			PanelKit.text(
				section.Body,
				"Result: all one kind → that kind, GUARANTEED. Mixed kinds → a RANDOM kind.",
				"Muted"
			)
		end

		local fee = PanelKit.text(
			section.Body,
			string.format("💰 Fee: %d coins (you have %d)", recipe.Fee, inv.Coins),
			"Muted"
		)
		if inv.Coins < recipe.Fee then
			fee.TextColor3 = C.Danger:Lerp(C.Text, 0.35)
		end

		local near = nearMachine()
		wasNear = near
		local shownReason = message or reason
		if shownReason then
			local line = PanelKit.text(section.Body, "⚠️ " .. shownReason, "Muted")
			line.TextColor3 = C.Heading
		end
		if not near then
			PanelKit.text(
				section.Body,
				"📍 The Synthesis Machine is in the lobby, next to the Hammer Vending Machine.",
				"Muted"
			)
		end

		local ready = plan ~= nil and near and not busy
		local button = PanelKit.button(
			section.Body,
			if busy
				then "⚡ Synthesizing..."
				elseif not near then "📍 Walk up to the machine"
				elseif plan then string.format("⚗️ SYNTHESIZE  ·  %d coins", recipe.Fee)
				else "⚗️ SYNTHESIZE",
			C.Good
		)
		button.Name = "Synthesize"
		button.Size = UDim2.new(1, 0, 0, 56)
		PanelKit.setTextSize(button, 22)
		PanelKit.setDisabled(button, not ready)
		button.Activated:Connect(function()
			if busy or not button.Active or plan == nil then
				return
			end
			busy = true
			busyToken += 1
			local token = busyToken
			message = nil
			synthesizeRemote:FireServer(recipe.Id, table.clone(selection), pickChoice)
			render()
			if chamber and not UiTokens.reducedMotion() then
				TweenService:Create(
					chamber,
					TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 8, true),
					{ Rotation = 14 }
				):Play()
			end
			task.delay(ANSWER_TIMEOUT, function()
				if busy and busyToken == token then
					busy = false -- never stuck if no answer comes
					message =
						"No answer from the machine. Your items have not been used; try again."
					render()
				end
			end)
		end)
	end

	local function recipeList(): ()
		local section = PanelKit.section(content, "📖 All recipes", true, false)
		for _, recipe in SynthesisRules.recipes() do
			if SynthesisRules.isOn(recipe) then
				PanelKit.text(
					section.Body,
					string.format(
						"• %s  ·  %d coins%s",
						SynthesisRules.recipeTitle(recipe),
						recipe.Fee,
						if recipe.Category == "Eggs" then "  ·  guaranteed" else ""
					),
					"Muted"
				)
			end
		end
		PanelKit.text(
			section.Body,
			"Supply Swap: you never get the supply you put in; the rest are equally likely.",
			"Muted"
		)
	end

	render = function(): ()
		if not window:isOpen() then
			return
		end
		window:clear()
		window:selectTab(activeCategory)
		local inv = inventory()
		if inv == nil then
			PanelKit.notice(content, "Loading", "Loading your items...")
			return
		end
		local top = PanelKit.section(content, "⚗️ Synthesis chamber", false, true)
		stage(top.Body)
		chips(top.Body, inv)
		guide()

		local info: SynthesisConfig.CategoryInfo? = nil
		for _, category in SynthesisConfig.Categories do
			if category.Id == activeCategory then
				info = category
			end
		end
		local recipes = SynthesisRules.recipesIn(activeCategory)
		local recipe = currentRecipe()
		if recipe == nil then
			local switchedOff = false
			for _, other in SynthesisRules.recipes() do
				switchedOff = switchedOff or other.Category == activeCategory
			end
			PanelKit.notice(
				content,
				"Locked",
				(if info then info.Unavailable else nil)
					or (
						if switchedOff
							then "These recipes are switched off for now. Check back later!"
							else "No recipes here yet. No higher-tier version is available."
					)
			)
			recipeList()
			return
		end
		recipeChooser(recipes, recipe)
		itemsSection(recipe, inv)
		previewSection(recipe, inv)
		recipeList()
	end

	-- The result comes out of the chamber.
	local function reveal(payload: { [string]: unknown }): ()
		local tier = text(payload.Tier)
		local color = tierColor(tier)
		shown = {
			Icon = text(payload.Icon),
			Label = text(payload.Label),
			Tier = tier,
			Detail = text(payload.Detail),
		}
		resetSelection()
		local orb, label = chamber, chamberLabel
		local quick = UiTokens.reducedMotion()
		if orb and label and window:isOpen() then
			orb.Rotation = 0
			if not quick then
				TweenService:Create(
					orb,
					TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.In),
					{ Size = UDim2.fromOffset(18, 18) }
				):Play()
			end
			task.delay(if quick then 0 else 0.5, function()
				orb.BackgroundColor3 = color
				orb.Text = text(payload.Icon)
				orb.Size = UDim2.fromOffset(18, 18)
				TweenService:Create(
					orb,
					TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Size = UDim2.fromOffset(80, 80) }
				):Play()
				label.Text = string.format("%s · %s", tier:upper(), text(payload.Label))
				label.TextColor3 = color
			end)
		end
		local info = SynthesisConfig.Tiers[tier]
		local order = if info then info.Order else 1
		task.delay(REVEAL_SECONDS, function()
			busy = false
			local detail = text(payload.Detail)
			AnnouncementController.show({
				Title = if order >= 5
					then "🌟 LEGENDARY SYNTHESIS!"
					elseif order >= 3 then "⚗️ " .. tier:upper() .. " SYNTHESIS!"
					else "⚗️ Synthesis complete",
				Body = text(payload.Label),
				Detail = if detail ~= "" then detail else nil,
				Accent = color,
				Celebrate = order >= 3,
				Seconds = if order >= 3 then 5 else 3,
			})
			render()
		end)
	end

	window:setTabs(
		(function()
			local tabs: { PanelKit.Tab } = {}
			for _, category in SynthesisConfig.Categories do
				table.insert(
					tabs,
					{ Id = category.Id, Label = category.Icon .. " " .. category.Label }
				)
			end
			return tabs
		end)(),
		function(id: string)
			if busy or id == activeCategory then
				return
			end
			activeCategory = id
			resetSelection()
			render()
		end
	)

	window:onOpen(function()
		task.defer(render)
		-- While open, notice walking up to (or away from) the machine. One
		-- watcher per opening: a quick close and reopen ends the old one.
		opens += 1
		local token = opens
		task.spawn(function()
			while window:isOpen() and opens == token do
				task.wait(NEAR_CHECK_SECONDS)
				if window:isOpen() and opens == token and not busy and nearMachine() ~= wasNear then
					render()
				end
			end
		end)
	end)
	ProgressController.Changed:Connect(function()
		if window:isOpen() and not busy then
			render()
		end
	end)
	remote("Synthesis", "Result").OnClientEvent:Connect(function(payload: unknown)
		if typeof(payload) ~= "table" then
			return
		end
		local data = payload :: { [string]: unknown }
		if data.Ok == true then
			reveal(data)
			return
		end
		busy = false
		message = text(data.Message)
		if window:isOpen() then
			render()
		elseif message ~= "" then
			UIController.showToast(message :: string)
		end
	end)
	-- Admin on/off switches (Remotes.Synthesis attributes): a recipe turned
	-- off disappears at once, and the server refuses it anyway.
	local switchFolder = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Synthesis")
	local function readSwitches(): ()
		local before = currentRecipe()
		SynthesisRules.setSwitches(
			SynthesisRules.switchesFromAttributes(switchFolder:GetAttributes())
		)
		local after = currentRecipe()
		if (if before then before.Id else nil) ~= (if after then after.Id else nil) then
			resetSelection()
		end
		if window:isOpen() and not busy then
			render()
		end
	end
	readSwitches()
	switchFolder.AttributeChanged:Connect(readSwitches)
	remote("Store", "State").OnClientEvent:Connect(function(state: unknown)
		if typeof(state) == "table" then
			storeOpen = (state :: { [string]: unknown }).Open == true
			if window:isOpen() and not busy then
				render()
			end
		end
	end)

	-- Close on death; the next character starts fresh.
	local function watchCharacter(character: Model): ()
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(function()
				window:close()
			end)
		end
	end
	if localPlayer.Character then
		task.spawn(watchCharacter, localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(watchCharacter)

	openWindow = function()
		if window:isOpen() then
			render()
		else
			window:open()
		end
	end
end

-- A one-time tip per recipe and session when everything for it is newly there.
local function watchReady(): ()
	local known: { [string]: boolean }? = nil
	ProgressController.Changed:Connect(function()
		local inv = inventory()
		if inv == nil then
			return
		end
		local ready = SynthesisRules.ready(inv)
		if known == nil then
			-- First snapshot: what's ready on joining counts as already seen.
			local seen: { [string]: boolean } = {}
			for _, id in ready do
				seen[id] = true
			end
			known = seen
			return
		end
		local seen = known :: { [string]: boolean }
		for _, id in ready do
			if not seen[id] then
				seen[id] = true
				local recipe = SynthesisRules.recipe(id)
				if recipe then
					UIController.showToast(
						"⚗️ Ready to synthesize: "
							.. SynthesisRules.recipeTitle(recipe)
							.. ". Visit the Synthesis Machine in the lobby!"
					)
				end
				return -- one tip at a time
			end
		end
	end)
end

-- Opens the window (the machine's prompt, a Synthesis Pick in the Bag).
-- Synthesizing still needs the player at the machine and the server's checks.
function SynthesisController.open(): ()
	local opener = openWindow
	if opener then
		opener()
	end
end

function SynthesisController.start(): ()
	buildWindow(localPlayer:WaitForChild("PlayerGui"))
	watchReady()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name == PROMPT_NAME then
			SynthesisController.open()
		end
	end)
end

return SynthesisController
