--!strict
--[[
	The Lucky Capsule Machine (docs/CAPSULE.md, docs/REMOTE_CONTRACTS.md
	"Capsule"). Capsule.Spin(): Level 5, a spin left today and the coins for
	the fixed price; the coins are taken, the prize is rolled with the
	server's Random (the last spin of the day only from the lucky tiers) and
	paid at once. Capsule.Result tells the client what came out. Coins only:
	there is no Robux path into or out of the machine.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ActivityService = require(script.Parent.ActivityService)
local BagRules = require(ReplicatedStorage.Shared.BagRules)
local CapsuleConfig = require(ReplicatedStorage.Config.CapsuleConfig)
local CapsuleRules = require(ReplicatedStorage.Shared.CapsuleRules)
local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)
local FurnitureRules = require(ReplicatedStorage.Shared.FurnitureRules)
local HistoryService = require(script.Parent.HistoryService)
local LevelRules = require(ReplicatedStorage.Shared.LevelRules)
local PickleballRules = require(ReplicatedStorage.Shared.PickleballRules)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)
local QuestRules = require(ReplicatedStorage.Shared.QuestRules)
local RemoteController = require(ServerScriptService.Controllers.RemoteController)
local RemoteLimits = require(ServerScriptService.Config.RemoteLimits)
local SessionService = require(script.Parent.SessionService)

local Remotes = ReplicatedStorage.Remotes.Capsule
local ToastRemote = ReplicatedStorage.Remotes.Notify.Toast

local CapsuleService = {}

local random = Random.new()

-- Pays `prize` (in place in saved data); returns the detail to show.
local function grant(player: Player, prize: CapsuleConfig.Prize): string
	local data = PlayerDataService.get(player)
	if data == nil then
		return ""
	end
	if prize.Kind == "Coins" then
		SessionService.addCoins(player, prize.Amount)
	elseif prize.Kind == "Xp" then
		SessionService.addXp(player, prize.Amount)
	elseif prize.Kind == "Bag" and prize.Key then
		local product = BagRules.product(prize.Key)
		if product then
			BagRules.grant(data.Bag, product, prize.Amount)
			return "In your 🎒 Bag."
		end
	elseif prize.Kind == "Supply" then
		local item = PickleballRules.rollSupply(CapsuleConfig.SupplyPool, random)
		if FurnitureRules.grantSpecial(data.Furniture, item, prize.Amount) then
			local info = FurnitureConfig.ByKey[item]
			return (if info then info.Name else item) .. " (in your office storage)"
		end
	end
	return ""
end

local function onSpin(player: Player): ()
	local data = PlayerDataService.get(player)
	if data == nil or SessionService.get(player) == nil then
		return
	end
	local dayKey = QuestRules.dayKey(os.time())
	local ok, reason =
		CapsuleRules.canSpin(LevelRules.levelFor(data.Xp), data.Coins, data.Capsule, dayKey)
	if not ok then
		return ToastRemote:FireClient(player, reason or "You can't spin right now.")
	end
	-- Never yields from here on, so two quick taps can't both spend.
	local lucky = CapsuleRules.nextIsLucky(data.Capsule, dayKey)
	if not SessionService.trySpendCoins(player, CapsuleConfig.Cost) then
		return ToastRemote:FireClient(
			player,
			string.format("A spin costs %d coins.", CapsuleConfig.Cost)
		)
	end
	CapsuleRules.noteSpin(data.Capsule, dayKey)
	local prize = CapsuleRules.pick(random:NextNumber(), lucky)
	local detail = grant(player, prize)
	ProgressService.sync(player)
	ActivityService.record(player, "CapsuleSpin", 1)
	HistoryService.record(player.UserId, "Item", "Capsule", "Lucky Capsule: " .. prize.Label)
	Remotes.Result:FireClient(player, {
		PrizeId = prize.Id,
		Label = prize.Label,
		Icon = prize.Icon,
		Tier = prize.Tier,
		Detail = detail,
		Lucky = lucky,
		SpinsLeft = CapsuleRules.spinsLeft(data.Capsule, dayKey),
	})
end

function CapsuleService.init(): ()
	RemoteController.bind(Remotes.Spin, {
		name = "Capsule.Spin",
		maxArgs = 0,
		rateLimit = RemoteLimits.Capsule,
	}, onSpin :: RemoteController.Handler)
end

return CapsuleService
