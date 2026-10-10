--!strict
--[[
	The Event of the Day (docs/DAILY_EVENTS.md, major update Phase 5a;
	decisions D10, D12, D13).

	* Which event: Shared/DailyEventRules.eventFor(os.time()), from the UTC
	  date alone, so every server runs the same one with nothing stored.
	* Points: from the activity feed (ActivityService): the server's own
	  results, weighted by today's event (Config/DailyEventConfig). Clients
	  send nothing here.
	* Tiers: reaching one pays it at once (coins, XP, and an office supply
	  on the top tier) and shows a card (DailyEvent.Rewarded). The tier is
	  marked paid in the session-locked saved data before paying, so it
	  pays once. A new UTC day starts the points over; missing a day costs
	  nothing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActivityService = require(script.Parent.ActivityService)
local DailyEventConfig = require(ReplicatedStorage.Config.DailyEventConfig)
local DailyEventRules = require(ReplicatedStorage.Shared.DailyEventRules)
local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)
local FurnitureRules = require(ReplicatedStorage.Shared.FurnitureRules)
local PickleballConfig = require(ReplicatedStorage.Config.PickleballConfig)
local PickleballRules = require(ReplicatedStorage.Shared.PickleballRules)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)
local SessionService = require(script.Parent.SessionService)

local RewardedRemote = ReplicatedStorage.Remotes.DailyEvent.Rewarded

local DailyEventService = {}

local random = Random.new()
local syncQueued: { [Player]: boolean } = {}

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

local function payTier(player: Player, dailyEvent: DailyEventConfig.DailyEvent, index: number): ()
	local tier = DailyEventConfig.Tiers[index]
	SessionService.addCoins(player, tier.Coins)
	SessionService.addXp(player, tier.Xp)
	local supplyName = ""
	if tier.Supply then
		local data = PlayerDataService.get(player)
		local item = PickleballRules.rollSupply(PickleballConfig.Supplies.Winner, random)
		if data and FurnitureRules.grantSpecial(data.Furniture, item, 1) then
			local info = FurnitureConfig.ByKey[item]
			supplyName = if info then info.Name else item
		end
	end
	RewardedRemote:FireClient(player, {
		EventId = dailyEvent.Id,
		Tier = index,
		Tiers = #DailyEventConfig.Tiers,
		Coins = tier.Coins,
		Xp = tier.Xp,
		Supply = supplyName,
	})
end

local function onActivity(player: Player, event: string, amount: number): ()
	local data = PlayerDataService.get(player)
	if data == nil then
		return
	end
	local now = os.time()
	local dailyEvent = DailyEventRules.eventFor(now)
	DailyEventRules.refresh(data.DailyEvent, now)
	local before = data.DailyEvent.Points
	local reached = DailyEventRules.add(data.DailyEvent, dailyEvent, event, amount)
	for _, index in reached do
		payTier(player, dailyEvent, index)
	end
	if data.DailyEvent.Points ~= before then
		queueSync(player)
	end
end

function DailyEventService.init(): ()
	ActivityService.subscribe(onActivity)
	PlayerDataService.onLoaded(function(_player: Player, data)
		-- Yesterday's points shouldn't show as today's.
		DailyEventRules.refresh(data.DailyEvent, os.time())
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		syncQueued[player] = nil
	end)
end

function DailyEventService.start(): ()
	-- At 00:00 UTC everyone here starts the new day's event at 0.
	while true do
		local now = os.time()
		task.wait(math.max(1, DailyEventRules.endsAt(now) - now) + 1)
		for _, player in Players:GetPlayers() do
			local data = PlayerDataService.get(player)
			if data then
				DailyEventRules.refresh(data.DailyEvent, os.time())
				queueSync(player)
			end
		end
	end
end

return DailyEventService
