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

-- Words that must never appear in anything a boss says (whole words, any
-- case). The game is for all ages; bosses can be grumpy but never vulgar.
Checks.BLOCKED_WORDS = table.freeze({
	"damn",
	"hell",
	"crap",
	"stupid",
	"idiot",
	"dumb",
	"shut up",
	"hate",
	"kill",
	"die",
	"loser",
	"moron",
	"sucks",
})

-- The first blocked word found in `line`, or nil.
function Checks.blockedWord(line: string): string?
	local lower = " " .. string.lower(line):gsub("[^%a ]", " ") .. " "
	for _, word in Checks.BLOCKED_WORDS do
		if string.find(lower, " " .. word .. " ", 1, true) then
			return word
		end
	end
	return nil
end

return Checks
