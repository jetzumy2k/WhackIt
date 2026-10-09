--!strict
--[[
	Robux store gate (docs/STORE.md, docs/REMOTE_CONTRACTS.md):
	  * whether the store is open: an admin's On / Off / Schedule setting
	    (Shared/StoreSchedule), saved in a DataStore and pushed to every server
	    with MessagingService;
	  * who may see the Mystery Hammer: players whose PolicyService rules
	    restrict paid random items never get the offer;
	  * Store.RequestPurchase: the client names a product key; the server checks
	    all of the above and opens Roblox's own purchase prompt. Payment and
	    delivery are handled by PurchaseService, which always delivers what was
	    paid for, even if the store has closed since.
	  * Store.RequestGift: the same, but the item goes to a Roblox friend
	    (docs/STORE.md "Bag and gifts"). The server checks the friendship and
	    remembers the choice in the buyer's data (PendingGift) before the
	    prompt, so PurchaseService knows where to deliver. A normal purchase
	    request or a cancelled prompt clears it.
	Store.State tells each client what to show; it's display only.
]]

local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AdminAuth = require(ServerScriptService.Lib.AdminAuth)
local BagRules = require(ReplicatedStorage.Shared.BagRules)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteController = require(ServerScriptService.Controllers.RemoteController)
local RemoteLimits = require(ServerScriptService.Config.RemoteLimits)
local StoreAdminConfig = require(ServerScriptService.Config.StoreAdminConfig)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)
local StoreSchedule = require(ReplicatedStorage.Shared.StoreSchedule)
local Validate = require(ReplicatedStorage.Shared.Validate)

local StoreRemotes = ReplicatedStorage.Remotes.Store
local ToastRemote = ReplicatedStorage.Remotes.Notify.Toast

local StoreService = {}

local settings: StoreSchedule.Settings =
	StoreSchedule.default(StoreAdminConfig.DefaultMode :: StoreSchedule.Mode)
local lastOpen: boolean? = nil
-- true = may be offered paid random items; missing = not checked yet (treated as no).
local mysteryAllowed: { [Player]: boolean } = {}
local admins: { [Player]: boolean } = {}

local settingsStore: DataStore? = nil

local function now(): number
	return os.time()
end

function StoreService.isOpen(): boolean
	return StoreSchedule.isOpen(settings, now())
end

local function stateFor(player: Player): { [string]: any }
	return {
		Open = StoreService.isOpen(),
		MysteryAllowed = mysteryAllowed[player] == true,
		IsAdmin = admins[player] == true,
		Mode = settings.Mode,
		StartsAt = settings.StartsAt,
		EndsAt = settings.EndsAt,
	}
end

local function sendState(player: Player): ()
	StoreRemotes.State:FireClient(player, stateFor(player))
end

local function broadcastState(): ()
	lastOpen = StoreService.isOpen()
	for _, player in Players:GetPlayers() do
		sendState(player)
	end
end

local function applySettings(raw: unknown): boolean
	local parsed = StoreSchedule.parse(raw, now())
	if parsed == nil then
		return false
	end
	settings = parsed
	broadcastState()
	return true
end

-- Unknown or failed lookups count as restricted: never show a paid random
-- item unless Roblox says it's allowed for this player.
local function checkMysteryAllowed(player: Player): boolean
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	if not ok or typeof(info) ~= "table" then
		return false
	end
	return (info :: { [string]: any }).ArePaidRandomItemsRestricted == false
end

local function onPlayerAdded(player: Player): ()
	admins[player] = AdminAuth.check(player)
	mysteryAllowed[player] = checkMysteryAllowed(player)
	if player.Parent == Players then
		sendState(player)
	end
end

local function loadSettings(): ()
	local store = settingsStore
	if store == nil then
		return
	end
	local ok, saved = pcall(function()
		return store:GetAsync(StoreAdminConfig.SettingsKey)
	end)
	if ok and saved ~= nil then
		applySettings(saved)
	elseif not ok then
		warn("[Store] couldn't load store settings, keeping current ones: " .. tostring(saved))
	end
end

local function saveAndPublish(admin: Player, newSettings: StoreSchedule.Settings): ()
	local store = settingsStore
	if store ~= nil then
		local ok, err = pcall(function()
			store:SetAsync(StoreAdminConfig.SettingsKey, newSettings)
		end)
		if not ok then
			warn("[Store] couldn't save store settings: " .. tostring(err))
			ToastRemote:FireClient(
				admin,
				"Store setting applied here, but saving failed. Try again."
			)
			return
		end
	end
	local ok, err = pcall(function()
		MessagingService:PublishAsync(StoreAdminConfig.MessagingTopic, newSettings)
	end)
	if not ok then
		-- Other servers still pick it up on their next refresh.
		warn("[Store] couldn't notify other servers: " .. tostring(err))
	end
	ToastRemote:FireClient(admin, "Store setting saved for all servers.")
end

local function onAdminSetMode(player: Player, raw: unknown): ()
	if admins[player] ~= true then
		return RemoteController.reject(player, "AdminSetMode", "not an admin")
	end
	local parsed = StoreSchedule.parse(raw, now())
	if parsed == nil then
		ToastRemote:FireClient(
			player,
			"That schedule isn't valid: it must end after it starts, in the future."
		)
		return
	end
	settings = parsed
	broadcastState()
	task.spawn(saveAndPublish, player, parsed)
end

local function onRequestPurchase(player: Player, raw: unknown): ()
	local key = Validate.id(raw, RemoteLimits.MaxIdLength)
	local product = if key then StoreConfig.ByKey[key] else nil
	if product == nil then
		return RemoteController.reject(player, "RequestPurchase", "unknown product")
	end
	-- Closed store, unconfigured product or restricted offer: normal UI races.
	if not StoreService.isOpen() or product.ProductId == 0 then
		sendState(player)
		return
	end
	-- Paid random items (the Mystery Hammer, pet eggs) only where allowed.
	if
		(product.Kind == "MysteryHammer" or product.Kind == "Egg")
		and mysteryAllowed[player] ~= true
	then
		sendState(player)
		return
	end
	-- A plain purchase is for the buyer, whatever gift they looked at before.
	local data = PlayerDataService.get(player)
	if data == nil then
		return
	end
	data.PendingGift = nil
	MarketplaceService:PromptProductPurchase(player, product.ProductId)
end

local function onRequestGift(player: Player, rawKey: unknown, rawRecipient: unknown): ()
	local key = Validate.id(rawKey, RemoteLimits.MaxIdLength)
	local product = if key then StoreConfig.ByKey[key] else nil
	local recipient = Validate.integer(rawRecipient, 1, 2 ^ 53)
	if product == nil or recipient == nil then
		return RemoteController.reject(player, "RequestGift", "bad product or recipient")
	end
	if not BagRules.isGiftable(product) then
		return RemoteController.reject(player, "RequestGift", "not giftable")
	end
	if recipient == player.UserId then
		ToastRemote:FireClient(player, "Pick a friend to send the gift to.")
		return
	end
	if not StoreService.isOpen() or product.ProductId == 0 then
		sendState(player)
		return
	end
	-- Yields; the buyer can't name anyone who isn't their Roblox friend.
	local ok, isFriend = pcall(function()
		return player:IsFriendsWithAsync(recipient)
	end)
	if not ok then
		ToastRemote:FireClient(player, "Couldn't check your friends list. Try again.")
		return
	end
	if isFriend ~= true then
		return RemoteController.reject(player, "RequestGift", "recipient is not a friend")
	end
	local data = PlayerDataService.get(player)
	if data == nil or player.Parent ~= Players then
		return
	end
	data.PendingGift = { RecipientUserId = recipient, ProductKey = product.Key }
	MarketplaceService:PromptProductPurchase(player, product.ProductId)
end

-- A cancelled prompt must not leave a gift choice behind for a later purchase.
local function onPromptFinished(userId: number, productId: number, purchased: boolean): ()
	if purchased then
		return
	end
	local player = Players:GetPlayerByUserId(userId)
	local data = if player then PlayerDataService.get(player) else nil
	local product = StoreConfig.ByProductId[productId]
	if data and product and data.PendingGift and data.PendingGift.ProductKey == product.Key then
		data.PendingGift = nil
	end
end

function StoreService.init(): ()
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(StoreAdminConfig.SettingsStoreName)
	end)
	if ok then
		settingsStore = store
	else
		warn("[Store] settings DataStore unavailable: " .. tostring(store))
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		mysteryAllowed[player] = nil
		admins[player] = nil
	end)

	RemoteController.bind(StoreRemotes.RequestPurchase, {
		name = "RequestPurchase",
		maxArgs = 1,
		rateLimit = RemoteLimits.Shop,
	}, onRequestPurchase)
	RemoteController.bind(StoreRemotes.RequestGift, {
		name = "RequestGift",
		maxArgs = 2,
		rateLimit = RemoteLimits.Shop,
	}, onRequestGift)
	MarketplaceService.PromptProductPurchaseFinished:Connect(onPromptFinished)
	RemoteController.bind(StoreRemotes.AdminSetMode, {
		name = "AdminSetMode",
		maxArgs = 1,
		rateLimit = RemoteLimits.Shop,
	}, onAdminSetMode)
end

function StoreService.start(): ()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	loadSettings()
	local subscribed, err = pcall(function()
		MessagingService:SubscribeAsync(StoreAdminConfig.MessagingTopic, function(message)
			applySettings(message.Data)
		end)
	end)
	if not subscribed then
		warn("[Store] cross-server updates unavailable, using periodic refresh: " .. tostring(err))
	end

	task.spawn(function()
		while true do
			task.wait(StoreAdminConfig.RefreshSeconds)
			loadSettings()
		end
	end)

	-- Open or close on schedule boundaries.
	while true do
		task.wait(5)
		if StoreService.isOpen() ~= lastOpen then
			broadcastState()
		end
	end
end

return StoreService
