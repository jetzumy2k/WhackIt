--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local BossShoutConfig = require(ReplicatedStorage.Config.BossShoutConfig)

local MAX_LINE_LENGTH = 60

-- Words that must never appear in a boss line (whole words, any case). The
-- game is for all ages; bosses can be grumpy but never vulgar.
local BLOCKED_WORDS = {
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
}

local function containsBlocked(line: string): string?
	local lower = " " .. string.lower(line):gsub("[^%a ]", " ") .. " "
	for _, word in BLOCKED_WORDS do
		if string.find(lower, " " .. word .. " ", 1, true) then
			return word
		end
	end
	return nil
end

return function()
	describe("BossShoutConfig", function()
		it("gives every boss something to shout", function()
			for _, boss in BossConfig.List do
				local lines = BossShoutConfig[boss.Id]
				expect(lines).never.to.equal(nil)
				expect(#lines > 0).to.equal(true)
			end
		end)

		it("keeps every line short and non-empty", function()
			for _, lines in BossShoutConfig do
				for _, line in lines do
					expect(#line > 0).to.equal(true)
					expect(#line <= MAX_LINE_LENGTH).to.equal(true)
				end
			end
		end)

		it("never uses bad language, including the angry CEO", function()
			for bossId, lines in BossShoutConfig do
				for _, line in lines do
					local found = containsBlocked(line)
					if found then
						error(string.format("%s line %q contains %q", bossId, line, found))
					end
				end
			end
		end)

		it("has no lines for bosses that don't exist", function()
			for bossId in BossShoutConfig do
				expect(BossConfig.ById[bossId]).never.to.equal(nil)
			end
		end)

		it("gives each boss at least two different lines so shouts don't repeat", function()
			for _, lines in BossShoutConfig do
				local seen: { [string]: boolean } = {}
				for _, line in lines do
					expect(seen[line]).to.equal(nil)
					seen[line] = true
				end
				expect(#lines >= 2).to.equal(true)
			end
		end)
	end)
end
