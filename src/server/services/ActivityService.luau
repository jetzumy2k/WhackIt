--!strict
--[[
	The activity feed: what players did, as decided by the server. Services
	report results here (ActivityService.record) and features that count
	them subscribe: quests (QuestService) and the Event of the Day
	(DailyEventService). Events are the QuestConfig.Events names:

	  DefeatBoss, EarnCoins (amount)   CombatService, a rewarded defeat
	  ReachZen                         StressService, a rewarded Zen
	  PlayMatch, WinMatch              RecreationService, a rewarded match
	  PlaceFurniture, VisitOffice      OfficeService
	  HatchPet                         PetService

	Nothing here comes from a client. Subscribers must not yield; an error in
	one is logged and doesn't stop the others.
]]

local ActivityService = {}

export type Listener = (player: Player, event: string, amount: number) -> ()

local listeners: { Listener } = {}

function ActivityService.subscribe(listener: Listener): ()
	table.insert(listeners, listener)
end

-- Reports `amount` (default 1) of `event` for `player`. Never yields.
function ActivityService.record(player: Player, event: string, amount: number?): ()
	local value = amount or 1
	for _, listener in listeners do
		local ok, message = pcall(function()
			listener(player, event, value)
		end)
		if not ok then
			warn("[Activity] a listener failed on " .. event .. ": " .. tostring(message))
		end
	end
end

return ActivityService
