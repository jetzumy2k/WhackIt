--!strict
--[[
	Payload validators for untrusted remote arguments. Each returns the value with
	its proper type when valid, or nil, so callers get type refinement for free:

		local bossInstanceId = Validate.id(raw, RemoteLimits.MaxIdLength)
		if not bossInstanceId then
			return RemoteController.reject(player, "RequestHammerHit", "bad bossInstanceId")
		end
]]

local Validate = {}

-- Server-issued ids: letters, digits, underscore and hyphen only.
local ID_PATTERN = "^[%w_%-]+$"

function Validate.string(value: unknown, maxLength: number): string?
	if typeof(value) ~= "string" then
		return nil
	end
	if #value == 0 or #value > maxLength then
		return nil
	end
	-- Rejects malformed UTF-8 that could break UI or logging downstream.
	if utf8.len(value) == nil then
		return nil
	end
	return value
end

function Validate.id(value: unknown, maxLength: number): string?
	local text = Validate.string(value, maxLength)
	if text == nil or string.match(text, ID_PATTERN) == nil then
		return nil
	end
	return text
end

-- Rejects NaN and +/-inf, which pass naive range checks in surprising ways.
function Validate.number(value: unknown, min: number, max: number): number?
	if typeof(value) ~= "number" then
		return nil
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	if value < min or value > max then
		return nil
	end
	return value
end

function Validate.integer(value: unknown, min: number, max: number): number?
	local number = Validate.number(value, min, max)
	if number == nil or number % 1 ~= 0 then
		return nil
	end
	return number
end

function Validate.boolean(value: unknown): boolean?
	if typeof(value) ~= "boolean" then
		return nil
	end
	return value
end

return Validate
