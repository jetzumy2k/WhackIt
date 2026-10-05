--!strict
--[[
	Hammer shop (docs/REMOTE_CONTRACTS.md). The client only names a hammer; the
	server checks it exists, the price, coins and ownership (Shared/
	ProgressionRules) and does the deduction itself. Handlers never yield, so a
	purchase is checked and applied atomically: rapid double-clicks can't buy
	twice or spend coins twice.

	After every request the player gets a fresh Profile.Sync, so the shop UI
	always shows the server's truth even when a request was refused.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)
local HammerRules = require(ReplicatedStorage.Shared.HammerRules)
local HammerService = require(script.Parent.HammerService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)
local ProgressionRules = require(ReplicatedStorage.Shared.ProgressionRules)
local RemoteController = require(ServerScriptService.Controllers.RemoteController)
local RemoteLimits = require(ServerScriptService.Config.RemoteLimits)
local SessionService = require(script.Parent.SessionService)
local Validate = require(ReplicatedStorage.Shared.Validate)

local ShopRemotes = ReplicatedStorage.Remotes.Shop

local ShopService = {}

local function readHammerId(player: Player, remoteName: string, raw: unknown): string?
	local hammerId = Validate.id(raw, RemoteLimits.MaxIdLength)
	if
		hammerId == nil
		or (HammerConfig.ById[hammerId] == nil and not HammerRules.isMysteryId(hammerId))
	then
		RemoteController.reject(player, remoteName, "invalid hammerId")
		return nil
	end
	return hammerId
end

local function equip(player: Player, hammerId: string): ()
	SessionService.setEquippedHammer(player, hammerId)
	HammerService.reequip(player)
end

local function onBuy(player: Player, raw: unknown): ()
	local hammerId = readHammerId(player, "BuyHammer", raw)
	local data = PlayerDataService.get(player)
	if hammerId == nil or data == nil then
		return
	end

	-- Not enough coins / already owned are normal UI races, not abuse: refuse quietly.
	if ProgressionRules.checkPurchase(hammerId, data.Coins, data.OwnedHammers) == "Ok" then
		local price = HammerConfig.ById[hammerId].Price
		if SessionService.trySpendCoins(player, price) then
			data.OwnedHammers[hammerId] = true
			equip(player, hammerId) -- a new hammer is put straight into your hand
		end
	end
	ProgressService.sync(player)
end

local function onEquip(player: Player, raw: unknown): ()
	local hammerId = readHammerId(player, "EquipHammer", raw)
	local data = PlayerDataService.get(player)
	if hammerId == nil or data == nil then
		return
	end

	local owns = ProgressionRules.ownsHammer(hammerId, data.OwnedHammers)
		or data.MysteryHammers[hammerId] ~= nil
	if owns and data.EquippedHammerId ~= hammerId then
		equip(player, hammerId)
	end
	ProgressService.sync(player)
end

function ShopService.init(): ()
	RemoteController.bind(ShopRemotes.BuyHammer, {
		name = "BuyHammer",
		maxArgs = 1,
		rateLimit = RemoteLimits.Shop,
	}, onBuy)
	RemoteController.bind(ShopRemotes.EquipHammer, {
		name = "EquipHammer",
		maxArgs = 1,
		rateLimit = RemoteLimits.Shop,
	}, onEquip)
end

return ShopService
