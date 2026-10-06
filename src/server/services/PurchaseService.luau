--!strict
--[[
	Delivers Robux purchases (MarketplaceService.ProcessReceipt, docs/STORE.md).

	Roblox calls ProcessReceipt until it gets PurchaseGranted, possibly several
	times and on different servers. So for each receipt:
	  1. wait for the buyer's data (ProfileStore session lock: one server owns it);
	  2. if the PurchaseId is already recorded, don't grant again;
	  3. otherwise grant and record the PurchaseId in the same step (no yield);
	  4. return PurchaseGranted only once a save containing that PurchaseId has
	     reached the DataStore; otherwise NotProcessedYet so Roblox retries.
	Delivery never depends on the store being open: paid is paid.

	What is delivered (docs/STORE.md "Bag and gifts"):
	  * normally, one of the item into the buyer's Bag; they use it when they like;
	  * if the buyer chose "Gift" for this product (PendingGift, set by
	    StoreService before the prompt), the item goes to the friend's gift inbox
	    (GiftService) instead. The PendingGift is cleared only after the purchase
	    is recorded, so a retried receipt delivers the same gift again, which
	    GiftService ignores (same GiftId).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BagRules = require(ReplicatedStorage.Shared.BagRules)
local GiftService = require(script.Parent.GiftService)
local PlayerDataSchema = require(ServerScriptService.Lib.PlayerDataSchema)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)
local StoreAdminConfig = require(ServerScriptService.Config.StoreAdminConfig)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)

local ToastRemote = ReplicatedStorage.Remotes.Notify.Toast

local PurchaseService = {}

local function waitForData(player: Player): PlayerDataSchema.PlayerData?
	local deadline = os.clock() + StoreAdminConfig.ReceiptDataWaitSeconds
	while player.Parent == Players and os.clock() < deadline do
		local data = PlayerDataService.get(player)
		if data then
			return data
		end
		task.wait(0.5)
	end
	return PlayerDataService.get(player)
end

local function recordPurchase(data: PlayerDataSchema.PlayerData, purchaseId: string): ()
	if table.find(data.ProcessedPurchases, purchaseId) then
		return
	end
	table.insert(data.ProcessedPurchases, purchaseId)
	while #data.ProcessedPurchases > PlayerDataSchema.MAX_PROCESSED_PURCHASES do
		table.remove(data.ProcessedPurchases, 1)
	end
end

-- Puts the product in the buyer's Bag. Never yields, so granting and
-- recording are atomic.
local function grantToBag(
	player: Player,
	data: PlayerDataSchema.PlayerData,
	product: StoreConfig.Product
): string
	BagRules.add(data.Bag, product.Key, 1)
	ProgressService.sync(player)
	return BagRules.itemText(product) .. " added to your Bag. Use it whenever you like!"
end

-- The gift this receipt is for, if the buyer chose "Gift" for this product.
local function pendingGiftFor(
	data: PlayerDataSchema.PlayerData,
	product: StoreConfig.Product
): PlayerDataSchema.PendingGift?
	local pending = data.PendingGift
	if pending and pending.ProductKey == product.Key and BagRules.isGiftable(product) then
		return pending
	end
	return nil
end

-- Sends the gift to the friend's inbox. Yields; safe to repeat for one receipt.
local function deliverGift(
	player: Player,
	pending: PlayerDataSchema.PendingGift,
	product: StoreConfig.Product,
	purchaseId: string
): string?
	local delivered = GiftService.deliver(pending.RecipientUserId, {
		GiftId = purchaseId,
		ProductKey = product.Key,
		FromUserId = player.UserId,
		FromName = player.DisplayName,
	})
	if not delivered then
		return nil
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(pending.RecipientUserId)
	end)
	return string.format(
		"Gift sent to %s: %s!",
		if ok and typeof(name) == "string" then name else "your friend",
		BagRules.itemText(product)
	)
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local product = StoreConfig.ByProductId[receipt.ProductId]
	local purchaseId = receipt.PurchaseId
	if player == nil or typeof(purchaseId) ~= "string" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if product == nil then
		warn(
			string.format(
				"[Purchase] product %s is not in StoreConfig.PRODUCT_IDS",
				tostring(receipt.ProductId)
			)
		)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local data = waitForData(player)
	if data == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if not table.find(data.ProcessedPurchases, purchaseId) then
		local pending = pendingGiftFor(data, product)
		local message: string
		if pending then
			local sent = deliverGift(player, pending, product, purchaseId)
			if sent == nil then
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
			message = sent
			-- Re-check after the yield: another call may have recorded it meanwhile.
			if data.PendingGift == pending then
				data.PendingGift = nil
			end
		else
			message = grantToBag(player, data, product)
		end
		if not table.find(data.ProcessedPurchases, purchaseId) then
			recordPurchase(data, purchaseId)
			ToastRemote:FireClient(player, message)
		end
	end

	local saved = PlayerDataService.saveAndConfirmAsync(player, function(savedData: any): boolean
		local list = if typeof(savedData) == "table" then savedData.ProcessedPurchases else nil
		return typeof(list) == "table" and table.find(list, purchaseId) ~= nil
	end, StoreAdminConfig.ReceiptSaveWaitSeconds)
	return if saved
		then Enum.ProductPurchaseDecision.PurchaseGranted
		else Enum.ProductPurchaseDecision.NotProcessedYet
end

function PurchaseService.init(): ()
	MarketplaceService.ProcessReceipt = function(receipt)
		local ok, decision = pcall(processReceipt, receipt)
		if not ok then
			warn("[Purchase] receipt error: " .. tostring(decision))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return decision
	end
end

return PurchaseService
