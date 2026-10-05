--!strict
--[[
	Pure rules for when the Robux store is open (docs/STORE.md). An admin sets
	one of three modes:
	  * "On"       - always open;
	  * "Off"      - closed (buttons hidden);
	  * "Schedule" - open from StartsAt until EndsAt (unix seconds, UTC).
	Closing the store only stops new purchase prompts: anything already paid
	for is always delivered.
]]

export type Mode = "On" | "Off" | "Schedule"

export type Settings = {
	Mode: Mode,
	StartsAt: number,
	EndsAt: number,
}

local StoreSchedule = {}

-- How far ahead a schedule may be set (also bounds bad input).
StoreSchedule.MAX_AHEAD_SECONDS = 366 * 24 * 60 * 60

function StoreSchedule.default(mode: Mode): Settings
	return { Mode = mode, StartsAt = 0, EndsAt = 0 }
end

function StoreSchedule.isOpen(settings: Settings, now: number): boolean
	if settings.Mode == "On" then
		return true
	elseif settings.Mode == "Schedule" then
		return now >= settings.StartsAt and now < settings.EndsAt
	end
	return false
end

local function isFinite(value: unknown): boolean
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

-- Turns untrusted input (admin remote, DataStore, cross-server message) into
-- valid settings, or nil if it can't be. A schedule must end after it starts
-- and not end in the past or too far ahead.
function StoreSchedule.parse(raw: unknown, now: number): Settings?
	if typeof(raw) ~= "table" then
		return nil
	end
	local fields = raw :: { [string]: unknown }
	local mode = fields.Mode
	if mode == "On" or mode == "Off" then
		return StoreSchedule.default(mode)
	end
	if mode ~= "Schedule" then
		return nil
	end
	local startsAt, endsAt = fields.StartsAt, fields.EndsAt
	if not isFinite(startsAt) or not isFinite(endsAt) then
		return nil
	end
	local startNumber, endNumber = math.floor(startsAt :: number), math.floor(endsAt :: number)
	if
		endNumber <= startNumber
		or endNumber <= now
		or endNumber > now + StoreSchedule.MAX_AHEAD_SECONDS
	then
		return nil
	end
	return { Mode = "Schedule", StartsAt = startNumber, EndsAt = endNumber }
end

return StoreSchedule
