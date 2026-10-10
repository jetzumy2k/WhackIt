--!strict
--[[
	Quests (docs/QUESTS.md, major update Phase 2b, decisions D7-D9).

	* Counting: other services report what a player did to the activity
	  feed (ActivityService.record), which calls QuestService.record; only server-side results
	  count: a rewarded boss defeat and its coins (CombatService), a rewarded
	  Zen (StressService), a rewarded pickleball match or win
	  (RecreationService), a piece placed or another player's office reached
	  (OfficeService), a pet hatched (PetService). Clients never report
	  progress.
	* Windows: daily quests are drawn at 00:00 UTC and weekly ones on Mondays
	  (Shared/QuestRules.refresh) when a player's data loads, on every event
	  or request, and once a minute for everyone here. A finished quest the
	  reset replaces is still paid.
	* Remotes (client -> server): Quests.Claim(kind, index?) and
	  Quests.Reroll(index), rate-limited and validated. A claim marks the
	  quest claimed before paying, in the session-locked saved data, so it
	  pays once. Quests.Rewarded (server -> client) shows what was paid.
	* Rewards: coins (SessionService.addCoins), XP (SessionService.addXp,
	  levels as usual) and, for weekly quests, one office supply roll
	  (PickleballConfig.Supplies.Loser pool).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ActivityService = require(script.Parent.ActivityService)
local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)
local FurnitureRules = require(ReplicatedStorage.Shared.FurnitureRules)
local LevelRules = require(ReplicatedStorage.Shared.LevelRules)
local PickleballConfig = require(ReplicatedStorage.Config.PickleballConfig)
local PickleballRules = require(ReplicatedStorage.Shared.PickleballRules)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)
local QuestConfig = require(ReplicatedStorage.Config.QuestConfig)
local QuestRules = require(ReplicatedStorage.Shared.QuestRules)
local RemoteController = require(ServerScriptService.Controllers.RemoteController)
local RemoteLimits = require(ServerScriptService.Config.RemoteLimits)
local SessionService = require(script.Parent.SessionService)
local Validate = require(ReplicatedStorage.Shared.Validate)

local QuestRemotes = ReplicatedStorage.Remotes.Quests
local ToastRemote = ReplicatedStorage.Remotes.Notify.Toast

-- How often everyone here gets a reset check (seconds).
local REFRESH_INTERVAL = 60
-- How long a joining player's quests wait for their session (seconds).
local SESSION_WAIT = 15

local QuestService = {}

local random = Random.new()
local syncQueued: { [Player]: boolean } = {}

local function toast(player: Player, text: string): ()
	ToastRemote:FireClient(player, text)
end

-- One snapshot per player per frame, however many events arrived.
local function queueSync(player: Player): ()
	if syncQueued[player] then
		return
	end
	syncQueued[player] = true
	task.defer(function()
		syncQueued[player] = nil
		if player.Parent then
			ProgressService.sync(player)
		end
	end)
end

type Payout = { Title: string, Coins: number, Xp: number, Supply: boolean }

-- Pays `payout` and tells the player. Saved data was already marked.
local function pay(player: Player, payout: Payout): ()
	SessionService.addCoins(player, payout.Coins)
	SessionService.addXp(player, payout.Xp)
	local supplyName = ""
	if payout.Supply then
		local data = PlayerDataService.get(player)
		local item = PickleballRules.rollSupply(PickleballConfig.Supplies.Loser, random)
		if data and FurnitureRules.grantSpecial(data.Furniture, item, 1) then
			local info = FurnitureConfig.ByKey[item]
			supplyName = if info then info.Name else item
		end
	end
	QuestRemotes.Rewarded:FireClient(player, {
		Title = payout.Title,
		Coins = payout.Coins,
		Xp = payout.Xp,
		Supply = supplyName,
	})
	queueSync(player)
end

local function payoutFor(quest: QuestConfig.Quest): Payout
	return {
		Title = quest.Text,
		Coins = quest.Coins,
		Xp = quest.Xp,
		Supply = quest.Kind == "Weekly",
	}
end

-- The player's quest state, moved to today's and this week's quests. Any
-- finished quest a reset replaced is paid here.
local function stateOf(player: Player): QuestRules.State?
	local data = PlayerDataService.get(player)
	if data == nil then
		return nil
	end
	local expired = QuestRules.refresh(data.Quests, os.time(), LevelRules.levelFor(data.Xp), random)
	if #expired > 0 then
		for _, quest in expired do
			pay(player, payoutFor(quest))
		end
		toast(player, "Unclaimed quest rewards from the last reset were added for you.")
	end
	return data.Quests
end

--[[
	Counts `amount` (default 1) of `event` (QuestConfig events) for the player.
	Called by other services after a result they've already decided. Never
	yields.
]]
function QuestService.record(player: Player, event: string, amount: number?): ()
	local state = stateOf(player)
	if state == nil then
		return
	end
	local finished = QuestRules.record(state, event, amount or 1)
	for _, quest in finished do
		toast(player, "📋 Quest complete: " .. quest.Text .. "! Claim it in 📋 Quests.")
	end
	queueSync(player)
end

local function onClaim(player: Player, rawKind: unknown, rawIndex: unknown): ()
	local kind = if rawKind == "Daily"
			or rawKind == "Weekly"
			or rawKind == "Tutorial"
			or rawKind == "Bonus"
		then rawKind :: string
		else nil
	if kind == nil then
		return RemoteController.reject(player, "Quests.Claim", "bad kind")
	end
	local index: number? = nil
	if kind == "Daily" or kind == "Weekly" then
		index = Validate.integer(
			rawIndex,
			1,
			math.max(QuestConfig.Slots.Daily, QuestConfig.Slots.Weekly)
		)
		if index == nil then
			return RemoteController.reject(player, "Quests.Claim", "bad index")
		end
	end
	local state = stateOf(player)
	if state == nil then
		return
	end
	if kind == "Bonus" then
		if not QuestRules.claimBonus(state) then
			return toast(player, "Claim all of today's quests first.")
		end
		local bonus = QuestConfig.DailyBonus
		return pay(
			player,
			{ Title = "All daily quests done!", Coins = bonus.Coins, Xp = bonus.Xp, Supply = false }
		)
	end
	local quest, reason = QuestRules.claim(state, kind, index)
	if quest == nil then
		toast(player, reason or "You can't claim that.")
		return queueSync(player)
	end
	pay(player, payoutFor(quest))
end

local function onReroll(player: Player, rawIndex: unknown): ()
	local index = Validate.integer(rawIndex, 1, QuestConfig.Slots.Daily)
	if index == nil then
		return RemoteController.reject(player, "Quests.Reroll", "bad index")
	end
	local data = PlayerDataService.get(player)
	local state = stateOf(player)
	if data == nil or state == nil then
		return
	end
	local ok, reason = QuestRules.reroll(state, index, LevelRules.levelFor(data.Xp), random)
	if not ok then
		toast(player, reason or "You can't reroll that.")
	end
	queueSync(player)
end

function QuestService.init(): ()
	ActivityService.subscribe(QuestService.record)
	RemoteController.bind(QuestRemotes.Claim, {
		name = "Quests.Claim",
		maxArgs = 2,
		rateLimit = RemoteLimits.Quests,
	}, onClaim)
	RemoteController.bind(QuestRemotes.Reroll, {
		name = "Quests.Reroll",
		maxArgs = 1,
		rateLimit = RemoteLimits.Quests,
	}, onReroll)
	PlayerDataService.onLoaded(function(player: Player)
		-- Coins and XP need the session (SessionService makes it on load too);
		-- a reset at join may pay unclaimed quests.
		local deadline = os.clock() + SESSION_WAIT
		while SessionService.get(player) == nil do
			if os.clock() > deadline or player.Parent == nil then
				return
			end
			task.wait(0.25)
		end
		if stateOf(player) then
			queueSync(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		syncQueued[player] = nil
	end)
end

function QuestService.start(): ()
	while true do
		task.wait(REFRESH_INTERVAL)
		for _, player in Players:GetPlayers() do
			local data = PlayerDataService.get(player)
			if data then
				local before = data.Quests.DayKey .. data.Quests.WeekKey
				stateOf(player)
				if data.Quests.DayKey .. data.Quests.WeekKey ~= before then
					queueSync(player)
				end
			end
		end
	end
end

return QuestService
