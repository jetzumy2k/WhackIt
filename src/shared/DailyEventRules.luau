--!strict
--[[
	Pure rules for the Event of the Day (Config/DailyEventConfig,
	docs/DAILY_EVENTS.md): which event runs on a UTC day, points, tiers and
	the saved state's validation. The server (DailyEventService) owns the
	state and pays the tiers; clients only display it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyEventConfig = require(ReplicatedStorage.Config.DailyEventConfig)

export type State = {
	DayKey: string, -- the UTC day the points belong to ("" = none yet)
	Points: number,
	Tiers: number, -- tiers already paid that day (0..#Tiers)
}

local DailyEventRules = {}

local DAY = 86400

function DailyEventRules.dayKey(unixTime: number): string
	return os.date("!%Y-%m-%d", math.floor(unixTime)) :: string
end

-- Today's event: the same in every server, from the date alone.
function DailyEventRules.eventFor(unixTime: number): DailyEventConfig.DailyEvent
	local rotation = DailyEventConfig.Rotation
	local day = math.floor(unixTime / DAY)
	return rotation[day % #rotation + 1]
end

-- When today's event ends (the next 00:00 UTC).
function DailyEventRules.endsAt(unixTime: number): number
	return (math.floor(unixTime / DAY) + 1) * DAY
end

function DailyEventRules.default(): State
	return { DayKey = "", Points = 0, Tiers = 0 }
end

-- Starts the day's points when the UTC day changed. Nothing carries over and
-- nothing is lost: tiers were paid when reached.
function DailyEventRules.refresh(state: State, unixTime: number): ()
	local day = DailyEventRules.dayKey(unixTime)
	if state.DayKey ~= day then
		state.DayKey = day
		state.Points = 0
		state.Tiers = 0
	end
end

-- Points `event` x `amount` is worth in `dailyEvent` (0 if it doesn't count).
function DailyEventRules.pointsFor(
	dailyEvent: DailyEventConfig.DailyEvent,
	event: string,
	amount: number
): number
	local weight = dailyEvent.Points[event]
	if
		weight == nil
		or typeof(amount) ~= "number"
		or amount ~= amount
		or amount <= 0
		or amount == math.huge
	then
		return 0
	end
	return weight * amount
end

--[[
	Adds points for an activity (refresh first) and marks every tier the new
	total reaches. Returns those tiers' indexes, to be paid; each is marked
	before it's returned, so it pays once.
]]
function DailyEventRules.add(
	state: State,
	dailyEvent: DailyEventConfig.DailyEvent,
	event: string,
	amount: number
): { number }
	local reached: { number } = {}
	local points = DailyEventRules.pointsFor(dailyEvent, event, amount)
	if points <= 0 then
		return reached
	end
	state.Points = math.min(DailyEventConfig.MaxPoints, state.Points + points)
	local tiers = DailyEventConfig.Tiers
	while state.Tiers < #tiers and state.Points >= tiers[state.Tiers + 1].Points do
		state.Tiers += 1
		table.insert(reached, state.Tiers)
	end
	return reached
end

-- Whole points for display (fractions from coins are kept but not shown).
function DailyEventRules.shownPoints(state: State): number
	return math.floor(state.Points + 1e-6)
end

function DailyEventRules.sanitize(raw: unknown): State
	local state = DailyEventRules.default()
	if typeof(raw) ~= "table" then
		return state
	end
	local data = raw :: { [string]: unknown }
	local dayKey = data.DayKey
	if typeof(dayKey) ~= "string" or not string.match(dayKey, "^%d%d%d%d%-%d%d%-%d%d$") then
		return state
	end
	state.DayKey = dayKey
	local points = data.Points
	if typeof(points) == "number" and points == points then
		state.Points = math.clamp(points, 0, DailyEventConfig.MaxPoints)
	end
	local tiers = data.Tiers
	if typeof(tiers) == "number" and tiers == tiers then
		state.Tiers = math.clamp(math.floor(tiers), 0, #DailyEventConfig.Tiers)
	end
	return state
end

return DailyEventRules
