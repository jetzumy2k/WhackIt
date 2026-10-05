--!strict
-- Small predicates shared by specs.

local Checks = {}

function Checks.isPositiveFinite(value: number): boolean
	-- value == value rejects NaN.
	return value == value and value > 0 and value < math.huge
end

function Checks.isNonEmptyString(value: string): boolean
	return #value > 0
end

return Checks
