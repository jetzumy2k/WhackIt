--!strict
--[[
	Using items from the Bag (docs/STORE.md "Bag and gifts", docs/REMOTE_CONTRACTS.md).
	The client names a product key; the server checks the player has one, takes
	it out and applies it in the same step (no yield), so an item is used once:
	  * a boost starts (or extends) that timed buff (BuffService);
	  * a Mystery Hammer is opened: its stats are rolled now, it's added to the
	    player's hammers and equipped.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BagRules = require(ReplicatedStorage.Shared.BagRules)
local BuffService = require(script.Parent.BuffService)
local HammerRules = require(ReplicatedStorage.Shared.HammerRules)
local HammerService = require(script.Parent.HammerService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)
local RemoteController = require(ServerScriptService.Controllers.RemoteController)
local RemoteLimits = require(ServerScriptService.Config.RemoteLimits)
local SessionService = require(script.Parent.SessionService)
local Validate = require(ReplicatedStorage.Shared.Validate)

local BagRemotes = ReplicatedStorage.Remotes.Bag
local ToastRemote = ReplicatedStorage.Remotes.Notify.Toast

local BagService = {}

local rollRandom = Random.new()

local function onUse(player: Player, rawKey: unknown): ()
	local key = Validate.id(rawKey, RemoteLimits.MaxIdLength)
	local product = if key then BagRules.product(key) else nil
	if key == nil or product == nil then
		return RemoteController.reject(player, "Bag.Use", "unknown item")
	end
	local data = PlayerDataService.get(player)
	if data == nil then
		return
	end
	if not BagRules.take(data.Bag, key) then
		-- The UI was out of date (e.g. used twice quickly): just refresh it.
		ProgressService.sync(player)
		return
	end

	if product.Kind == "MysteryHammer" then
		local hammerId = HammerRules.mysteryId(data.NextMysteryNumber)
		data.NextMysteryNumber += 1
		local roll = HammerRules.rollMystery(rollRandom)
		data.MysteryHammers[hammerId] = roll
		SessionService.setEquippedHammer(player, hammerId)
		HammerService.reequip(player)
		ProgressService.sync(player)
		ToastRemote:FireClient(
			player,
			string.format(
				"Mystery Hammer opened: %d damage, +%d%% crit damage! Equipped.",
				roll.Damage,
				roll.CritDamagePercent
			)
		)
		return
	end

	BuffService.grantTimed(player, product.Kind, product.Percent, product.Seconds)
	ToastRemote:FireClient(player, BagRules.itemText(product) .. " is now active.")
end

function BagService.init(): ()
	RemoteController.bind(BagRemotes.Use, {
		name = "Bag.Use",
		maxArgs = 1,
		rateLimit = RemoteLimits.Shop,
	}, onUse)
end

return BagService
