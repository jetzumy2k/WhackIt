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
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BuffService = require(script.Parent.BuffService)
local HammerRules = require(ReplicatedStorage.Shared.HammerRules)
local HammerService = require(script.Parent.HammerService)
local PlayerDataSchema = require(ServerScriptService.Lib.PlayerDataSchema)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)
local SessionService = require(script.Parent.SessionService)
local StoreAdminConfig = require(ServerScriptService.Config.StoreAdminConfig)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)

local ToastRemote = ReplicatedStorage.Remotes.Notify.Toast

local PurchaseService = {}

local rollRandom = Random.new()

local BUFF_NAMES: { [string]: string } =
	{ Xp = "XP", Damage = "Damage", CritDamage = "Crit Damage" }

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
	table.insert(data.ProcessedPurchases, purchaseId)
	while #data.ProcessedPurchases > PlayerDataSchema.MAX_PROCESSED_PURCHASES do
		table.remove(data.ProcessedPurchases, 1)
	end
end

-- Applies the product. Never yields, so granting and recording are atomic.
local function grant(
	player: Player,
	data: PlayerDataSchema.PlayerData,
	product: StoreConfig.Product
): string
	if product.Kind == "MysteryHammer" then
		local hammerId = HammerRules.mysteryId(data.NextMysteryNumber)
		data.NextMysteryNumber += 1
		local roll = HammerRules.rollMystery(rollRandom)
		data.MysteryHammers[hammerId] = roll
		SessionService.setEquippedHammer(player, hammerId)
		HammerService.reequip(player)
		ProgressService.sync(player)
		return string.format(
			"Mystery Hammer unboxed: %d damage, +%d%% crit damage!",
			roll.Damage,
			roll.CritDamagePercent
		)
	end
	BuffService.grantTimed(player, product.Kind, product.Percent, product.Seconds)
	return string.format(
		"+%d%% %s boost added (%d min of play time).",
		product.Percent,
		BUFF_NAMES[product.Kind] or product.Kind,
		product.Seconds // 60
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
		local message = grant(player, data, product)
		recordPurchase(data, purchaseId)
		ToastRemote:FireClient(player, message)
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
