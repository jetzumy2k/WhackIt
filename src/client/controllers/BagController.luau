--!strict
--[[
	The Bag (docs/STORE.md "Bag and gifts"): store items the player owns but
	hasn't used yet (bought, gifted by friends, or dropped by custom bosses).
	"Use" starts a boost; "Open" opens a Mystery Hammer or a bundle;
	"Incubate" sends an egg to an incubator. Display only: the server checks
	the player really has the item (BagService).

	Since the visual overhaul (V4b) a PanelKit window with item cards in a
	grid (Lib/PanelKit.itemCard), like every newer panel.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BagRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BagRules"))
local PanelKit = require(script.Parent.Parent.Lib.PanelKit)
local ProgressController = require(script.Parent.ProgressController)
local Responsive = require(script.Parent.Parent.Lib.Responsive)
local StoreConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StoreConfig"))

local BagController = {}

-- Set once the panel exists (start); lets the Player Panel open it.
local openPanel: (() -> ())? = nil

local C = PanelKit.Colors
local BAG_COLOR = Color3.fromRGB(60, 160, 150)
local CARD_WIDTH = 170
local CARD_HEIGHT = 218

-- An icon and an accent per kind of item.
local KIND_LOOK: { [string]: { Icon: string, Accent: Color3 } } = {
	Xp = { Icon = "✨", Accent = Color3.fromRGB(110, 150, 255) },
	Damage = { Icon = "💥", Accent = Color3.fromRGB(230, 110, 80) },
	CritDamage = { Icon = "🎯", Accent = Color3.fromRGB(240, 185, 70) },
	Egg = { Icon = "🥚", Accent = Color3.fromRGB(150, 210, 120) },
	Bundle = { Icon = "📦", Accent = Color3.fromRGB(190, 140, 255) },
	MysteryHammer = { Icon = "🎁", Accent = Color3.fromRGB(255, 120, 170) },
}
local RARITY_ACCENT: { [string]: Color3 } = {
	Common = Color3.fromRGB(150, 210, 120),
	Rare = Color3.fromRGB(90, 160, 255),
	Mythical = Color3.fromRGB(220, 120, 255),
}

local function actionText(product: StoreConfig.Product): string
	if product.Kind == "Egg" then
		return "Incubate"
	elseif product.Kind == "MysteryHammer" or product.Kind == "Bundle" then
		return "Open"
	end
	return "Use"
end

local function detailText(product: StoreConfig.Product): string
	if product.Kind == "Egg" then
		return "Hatch it at the Pet Incubation Center outside."
	elseif product.Kind == "MysteryHammer" then
		return "A hammer with surprise bonus stats."
	elseif product.Kind == "Bundle" then
		return "Opens into its boosts, ready in your Bag."
	end
	return "Counts down while you play. The strongest boost of each kind applies."
end

function BagController.start(): ()
	local useRemote =
		ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Bag"):WaitForChild("Use")
	assert(useRemote:IsA("RemoteEvent"), "Bag.Use must be a RemoteEvent")

	-- HUD button in the shared column (Lib/Responsive), above the Store.
	local open = Responsive.dockButton("OpenBag", "🎒", "Bag", BAG_COLOR, 2)

	local window = PanelKit.window({
		Name = "Bag",
		Title = "🎒 Bag",
		Subtitle = "Items you bought, got as gifts or won. Use them when it suits you.",
		Accent = BAG_COLOR,
		DisplayOrder = 5,
	}, Players.LocalPlayer:WaitForChild("PlayerGui"))
	local content = window.Content

	local function render(): ()
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
		if not window:isOpen() then
			return
		end
		window:clear()
		local grid: Frame? = nil
		-- Store order, so the grid is stable.
		for _, product in StoreConfig.Products do
			local count = bag[product.Key]
			if count == nil or count < 1 then
				continue
			end
			if grid == nil then
				grid = PanelKit.grid(content, CARD_WIDTH, CARD_HEIGHT)
			end
			local look = KIND_LOOK[product.Kind] or { Icon = "🎒", Accent = BAG_COLOR }
			local rarity = product.Rarity
			local accent = if rarity and RARITY_ACCENT[rarity]
				then RARITY_ACCENT[rarity]
				else look.Accent
			local card = PanelKit.itemCard(
				grid :: Frame,
				BagRules.itemText(product),
				detailText(product),
				look.Icon,
				accent
			)
			PanelKit.setBadge(card, string.format("x%d", count), accent)
			card.Button.Text = actionText(product)
			PanelKit.setColor(card.Button, C.Good)
			card.Button.Activated:Connect(function()
				useRemote:FireServer(product.Key)
			end)
		end
		if grid == nil then
			PanelKit.notice(
				content,
				"Empty",
				"Your Bag is empty. Items from the Store, gifts from friends and boss drops show up here."
			)
		end
	end

	ProgressController.Changed:Connect(render)
	window:onOpen(function()
		task.defer(render)
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

-- Opens the Bag panel (e.g. from the Player Panel). Using an item still
-- goes through Bag.Use and the server's checks.
function BagController.open(): ()
	if openPanel then
		openPanel()
	end
end

return BagController
