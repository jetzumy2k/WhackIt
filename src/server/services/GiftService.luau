--!strict
--[[
	Gift inboxes (docs/STORE.md "Bag and gifts"). A gift bought for a friend is
	written to the friend's inbox in DataStore `GiftInbox` (key "Inbox_<UserId>"),
	so it reaches them even if they're offline or in another server.

	Delivering (PurchaseService) is idempotent: a gift is keyed by the buyer's
	PurchaseId and written at most once.

	Claiming moves inbox gifts into the recipient's Bag without ever losing or
	doubling one, even if a server stops halfway:
	  1. read the inbox;
	  2. add each gift not yet in ClaimedGifts to the Bag and record its id
	     (no yield between the two);
	  3. wait until a save containing those ids has reached the DataStore;
	  4. only then remove them from the inbox.
	A crash after 3 leaves gifts in the inbox, but ClaimedGifts stops a second
	claim. Claims run on data load, when another server pings MessagingService
	topic `Gifts`, and every few minutes.
]]

local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BagRules = require(ReplicatedStorage.Shared.BagRules)
local PlayerDataSchema = require(ServerScriptService.Lib.PlayerDataSchema)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)
local StoreAdminConfig = require(ServerScriptService.Config.StoreAdminConfig)

local ToastRemote = ReplicatedStorage.Remotes.Notify.Toast

local STORE_NAME = "GiftInbox"
local TOPIC = "Gifts"
local REFRESH_SECONDS = 300

local GiftService = {}

local inboxStore: DataStore? = nil
-- One claim at a time per player; a request during a claim runs once more after it.
local claiming: { [Player]: boolean } = {}
local claimAgain: { [Player]: boolean } = {}

local function inboxKey(userId: number): string
	return "Inbox_" .. userId
end

-- Adds `gift` to the recipient's inbox (once). Yields. Returns false on failure.
function GiftService.deliver(recipientUserId: number, gift: BagRules.Gift): boolean
	local store = inboxStore
	if store == nil then
		return false
	end
	local ok, err = pcall(function()
		store:UpdateAsync(inboxKey(recipientUserId), function(old: unknown)
			local gifts = BagRules.parseInbox(old)
			for _, existing in gifts do
				if existing.GiftId == gift.GiftId then
					return nil -- already delivered; keep as is
				end
			end
			table.insert(gifts, gift)
			return gifts
		end)
	end)
	if not ok then
		warn("[Gift] delivery failed: " .. tostring(err))
		return false
	end
	-- Tell the recipient's server, wherever it is, to claim now.
	local online = Players:GetPlayerByUserId(recipientUserId)
	if online then
		task.spawn(GiftService.claim, online)
	else
		pcall(function()
			MessagingService:PublishAsync(TOPIC, recipientUserId)
		end)
	end
	return true
end

local function removeClaimed(userId: number, ids: { [string]: boolean }): ()
	local store = inboxStore
	if store == nil then
		return
	end
	local ok, err = pcall(function()
		store:UpdateAsync(inboxKey(userId), function(old: unknown)
			local kept = {}
			for _, gift in BagRules.parseInbox(old) do
				if not ids[gift.GiftId] then
					table.insert(kept, gift)
				end
			end
			return kept
		end)
	end)
	if not ok then
		-- Harmless: ClaimedGifts stops these from being claimed twice.
		warn("[Gift] couldn't clear claimed gifts: " .. tostring(err))
	end
end

-- Moves the player's pending gifts into their Bag. Yields.
function GiftService.claim(player: Player): ()
	local store = inboxStore
	if store == nil then
		return
	end
	if claiming[player] then
		claimAgain[player] = true
		return
	end
	claiming[player] = true
	xpcall(function(): ()
		local raw = store:GetAsync(inboxKey(player.UserId))
		local gifts = BagRules.parseInbox(raw)
		if #gifts == 0 then
			return
		end
		local data = PlayerDataService.get(player)
		if data == nil then
			return
		end

		-- No yield from here until the save request: grant and record together.
		local ids: { [string]: boolean } = {}
		local received: { BagRules.Gift } = {}
		for _, gift in gifts do
			ids[gift.GiftId] = true
			if not table.find(data.ClaimedGifts, gift.GiftId) then
				BagRules.add(data.Bag, gift.ProductKey, 1)
				table.insert(data.ClaimedGifts, gift.GiftId)
				table.insert(received, gift)
			end
		end
		while #data.ClaimedGifts > PlayerDataSchema.MAX_CLAIMED_GIFTS do
			table.remove(data.ClaimedGifts, 1)
		end
		if #received > 0 then
			ProgressService.sync(player)
			for _, gift in received do
				local product = BagRules.product(gift.ProductKey)
				if product then
					ToastRemote:FireClient(
						player,
						string.format(
							"Gift from %s: %s. It's in your Bag!",
							gift.FromName,
							BagRules.itemText(product)
						)
					)
				end
			end
		end

		local saved = PlayerDataService.saveAndConfirmAsync(
			player,
			function(savedData: any): boolean
				local list = if typeof(savedData) == "table" then savedData.ClaimedGifts else nil
				if typeof(list) ~= "table" then
					return false
				end
				for id in ids do
					if not table.find(list, id) then
						return false
					end
				end
				return true
			end,
			StoreAdminConfig.ReceiptSaveWaitSeconds
		)
		if saved then
			removeClaimed(player.UserId, ids)
		end
	end, function(err: unknown)
		warn("[Gift] claim failed: " .. tostring(err))
	end)
	claiming[player] = nil
	if claimAgain[player] and player.Parent == Players then
		claimAgain[player] = nil
		GiftService.claim(player)
	end
end

function GiftService.init(): ()
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		inboxStore = store
	else
		warn("[Gift] DataStore unavailable: " .. tostring(store))
	end
	PlayerDataService.onLoaded(function(player: Player)
		GiftService.claim(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		claiming[player] = nil
		claimAgain[player] = nil
	end)
end

function GiftService.start(): ()
	pcall(function()
		MessagingService:SubscribeAsync(TOPIC, function(message)
			local userId = message.Data
			if typeof(userId) ~= "number" then
				return
			end
			local player = Players:GetPlayerByUserId(userId)
			if player then
				GiftService.claim(player)
			end
		end)
	end)
	while true do
		task.wait(REFRESH_SECONDS)
		for _, player in Players:GetPlayers() do
			task.spawn(GiftService.claim, player)
		end
	end
end

return GiftService
