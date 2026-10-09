--!strict
--[[
	Dates an admin types and reads, in the player's own time zone
	("2026-10-05 18:30" <-> unix seconds, UTC). Used by the Store's opening
	hours and the Admin panel's event schedule. The server stores and
	compares only unix seconds.
]]

local LocalTime = {}

LocalTime.FORMAT_HINT = "YYYY-MM-DD HH:MM"

function LocalTime.format(unix: number): string
	if unix <= 0 then
		return ""
	end
	return DateTime.fromUnixTimestamp(unix):FormatLocalTime("YYYY-MM-DD HH:mm", "en-us")
end

-- Unix seconds for "YYYY-MM-DD HH:MM" in local time, or nil if it isn't one.
function LocalTime.parse(text: string): number?
	local year, month, day, hour, minute =
		string.match(text, "^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s+(%d%d?):(%d%d)%s*$")
	if year == nil then
		return nil
	end
	local ok, dateTime = pcall(
		DateTime.fromLocalTime,
		tonumber(year) :: number,
		tonumber(month) :: number,
		tonumber(day) :: number,
		tonumber(hour) :: number,
		tonumber(minute) :: number
	)
	return if ok then dateTime.UnixTimestamp else nil
end

return LocalTime
