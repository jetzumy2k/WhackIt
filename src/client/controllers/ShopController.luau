--!strict
--[[
	Hammer shop UI: a "Hammers" button opens a panel (since the visual
	overhaul V4b a PanelKit window with item cards in a grid) showing every
	hammer with a 3D preview (Shared/HammerModel, built once per card, no
	effects), its damage, a badge (Equipped, Owned, SALE) and a Buy / Equip /
	Equipped button. Display only: clicking sends the hammer id; the server
	checks coins and ownership and answers with a fresh Profile.Sync, which
	refreshes the cards in place.

	During a Hammer Shop sale (docs/EVENTS.md) cards show the sale price, and
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
local PanelKit = require(script.Parent.Parent.Lib.PanelKit)
local ProgressController = require(script.Parent.ProgressController)
local Responsive = require(script.Parent.Parent.Lib.Responsive)

local ShopController = {}

local C = PanelKit.Colors
local EQUIP_COLOR = Color3.fromRGB(70, 140, 230)
local SALE_COLOR = Color3.fromRGB(230, 90, 90)
local MYSTERY_COLOR = Color3.fromRGB(255, 120, 170)
local CARD_WIDTH = 170
local CARD_HEIGHT = 236
-- Shown tilted, head up, so every hammer reads at a glance.
local PREVIEW_TILT = CFrame.Angles(math.rad(40), 0, 0)
local PREVIEW_FOV = 40

local localPlayer = Players.LocalPlayer
-- Set once the panel exists (start); lets other controllers open it.
local openPanel: (() -> ())? = nil

type Card = {
	Hammer: HammerConfig.HammerDefinition,
	IsMystery: boolean, -- a Robux Mystery Hammer (always owned, rolled stats)
	BonusPercent: number,
	CritPercent: number,
	Price: number, -- the price shown on the Buy button (sale included)
	View: PanelKit.ItemCard,
}

-- A still 3D view of the hammer filling the card's picture (static: built
-- once, no camera updates).
local function buildPreview(hammer: HammerConfig.HammerDefinition, parent: Frame): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Ambient = Color3.fromRGB(170, 170, 180)
	viewport.LightColor = Color3.fromRGB(255, 250, 240)
	viewport.LightDirection = Vector3.new(-1, -1, -0.6)
	viewport.Parent = parent

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

local function buildCard(hammer: HammerConfig.HammerDefinition, grid: Frame, accent: Color3): Card
	local view = PanelKit.itemCard(grid, hammer.DisplayName, "", nil, accent)
	view.Frame.Name = hammer.Id
	buildPreview(hammer, view.Picture)
	return {
		Hammer = hammer,
		IsMystery = false,
		BonusPercent = 0,
		CritPercent = 0,
		Price = hammer.Price,
		View = view,
	}
end

local function refreshCard(card: Card): ()
	local snapshot = ProgressController.get()
	local hammer = card.Hammer
	local view = card.View
	local owned = card.IsMystery or ProgressController.ownsHammer(hammer.Id)
	local equipped = snapshot ~= nil and snapshot.EquippedHammerId == hammer.Id
	local coins = if snapshot then snapshot.Coins else 0

	view.Detail.Text = if card.IsMystery
		then string.format(
			"Damage %d · +%d%% damage · +%d%% crit damage",
			hammer.Damage,
			card.BonusPercent,
			card.CritPercent
		)
		else string.format("Damage %d · %s", hammer.Damage, hammer.Description)
	local button = view.Button
	if equipped then
		button.Text = "Equipped"
		PanelKit.setDisabled(button, true)
		PanelKit.setBadge(view, "✓ Equipped", C.Good)
		return
	elseif owned then
		button.Text = "Equip"
		PanelKit.setColor(button, EQUIP_COLOR)
		PanelKit.setDisabled(button, false)
		PanelKit.setBadge(view, "Owned", EQUIP_COLOR)
		return
	end
	local percent = EventController.discountPercent(hammer.Id)
	card.Price = EventRules.discountedPrice(hammer.Price, percent)
	PanelKit.setBadge(
		view,
		if percent > 0 then string.format("SALE -%d%%", percent) else "",
		SALE_COLOR
	)
	local level = if snapshot then snapshot.Level else 1
	if hammer.MinLevel and level < hammer.MinLevel then
		-- The server checks the level too (ProgressionRules.checkPurchase).
		button.Text = string.format("🔒 Reach Lv %d", hammer.MinLevel)
		PanelKit.setDisabled(button, true)
	elseif coins >= card.Price then
		button.Text = string.format("Buy · 🪙 %d", card.Price)
		PanelKit.setColor(button, C.Good)
		PanelKit.setDisabled(button, false)
	else
		button.Text = string.format("Need 🪙 %d", card.Price)
		PanelKit.setDisabled(button, true)
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

	-- HUD button in the shared column (Lib/Responsive), lowest of the four.
	local open = Responsive.dockButton("OpenShop", "🔨", "Hammers", EQUIP_COLOR, 4)

	local window = PanelKit.window({
		Name = "Shop",
		Title = "🔨 Hammers",
		Subtitle = "Better hammers hit harder and relieve stress a little faster.",
		Accent = EQUIP_COLOR,
		DisplayOrder = 5,
	}, localPlayer:WaitForChild("PlayerGui"))
	-- Built once (the 3D previews too) and refreshed in place.
	local grid = PanelKit.grid(window.Content, CARD_WIDTH, CARD_HEIGHT)

	local cards: { Card } = {}
	for _, hammer in HammerConfig.List do
		local card = buildCard(hammer, grid, EQUIP_COLOR)
		table.insert(cards, card)
		card.View.Button.Activated:Connect(function()
			if not card.View.Button.Active then
				return
			end
			if ProgressController.ownsHammer(hammer.Id) then
				equipRemote:FireServer(hammer.Id)
			else
				buyRemote:FireServer(hammer.Id, card.Price)
			end
		end)
	end

	-- Mystery Hammers appear as they are bought, each with its rolled stats.
	local mysteryCards: { [string]: boolean } = {}
	local function addMysteryCards(): ()
		local snapshot = ProgressController.get()
		if snapshot == nil then
			return
		end
		for _, owned in snapshot.MysteryHammers do
			if mysteryCards[owned.Id] then
				continue
			end
			mysteryCards[owned.Id] = true
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
			local card = buildCard(look, grid, MYSTERY_COLOR)
			card.IsMystery = true
			card.BonusPercent = owned.BonusDamagePercent
			card.CritPercent = owned.CritDamagePercent
			table.insert(cards, card)
			card.View.Button.Activated:Connect(function()
				if card.View.Button.Active then
					equipRemote:FireServer(owned.Id)
				end
			end)
		end
	end

	local function refresh(): ()
		addMysteryCards()
		for _, card in cards do
			refreshCard(card)
		end
	end
	ProgressController.Changed:Connect(refresh)
	EventController.Changed:Connect(refresh)
	refresh()

	open.Activated:Connect(function()
		window:toggle()
	end)
	openPanel = function()
		if not window:isOpen() then
			window:open()
		end
	end
end

-- Opens the hammer shop (e.g. from the vending machine, StoreMachineController).
-- Display only: buying still goes through Shop.BuyHammer, checked by the server.
function ShopController.open(): ()
	if openPanel then
		openPanel()
	end
end

return ShopController
