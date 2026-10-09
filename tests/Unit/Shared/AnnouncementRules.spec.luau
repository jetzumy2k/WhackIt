--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnnouncementConfig = require(ReplicatedStorage.Config.AnnouncementConfig)
local AnnouncementRules = require(ReplicatedStorage.Shared.AnnouncementRules)

-- Just the cleaned text (clean() also returns a reason).
local function cleaned(raw: unknown): string?
	local text = AnnouncementRules.clean(raw)
	return text
end

return function()
	describe("AnnouncementRules.clean", function()
		it("keeps a normal message", function()
			expect(cleaned("Welcome to Whack It Out!")).to.equal("Welcome to Whack It Out!")
		end)

		it("turns newlines and tabs into single spaces and trims", function()
			expect(cleaned("  Boss\n\n\tevent   soon!  ")).to.equal("Boss event soon!")
		end)

		it("removes zero-width and right-to-left override characters", function()
			local sneaky = "Hi" .. utf8.char(0x200B) .. "there" .. utf8.char(0x202E) .. "!"
			expect(cleaned(sneaky)).to.equal("Hithere!")
		end)

		it("leaves markup as plain text (labels have RichText off)", function()
			expect(cleaned("<b>big</b>")).to.equal("<b>big</b>")
		end)

		it("refuses empty, blank, non-string and malformed text", function()
			expect((cleaned(""))).to.equal(nil)
			expect((cleaned("   \n  "))).to.equal(nil)
			expect((cleaned(42))).to.equal(nil)
			expect((cleaned(nil))).to.equal(nil)
			expect((cleaned("\255\254"))).to.equal(nil)
		end)

		it("counts characters, not bytes, against the limit", function()
			local max = AnnouncementConfig.MaxLength
			expect(cleaned(string.rep("a", max))).to.equal(string.rep("a", max))
			local tooLong, reason = AnnouncementRules.clean(string.rep("a", max + 1))
			expect(tooLong).to.equal(nil)
			expect(reason).never.to.equal(nil)
			-- Multi-byte characters up to the limit are fine.
			local accented = string.rep("é", max)
			expect(cleaned(accented)).to.equal(accented)
		end)

		it("refuses huge payloads before doing any work", function()
			expect((cleaned(string.rep("a", 100000)))).to.equal(nil)
		end)
	end)

	describe("AnnouncementRules.seconds", function()
		it("accepts only the configured durations", function()
			for _, seconds in AnnouncementConfig.Durations do
				expect(AnnouncementRules.seconds(seconds)).to.equal(seconds)
			end
			expect(AnnouncementRules.seconds(7)).to.equal(nil)
			expect(AnnouncementRules.seconds(-5)).to.equal(nil)
			expect(AnnouncementRules.seconds(0 / 0)).to.equal(nil)
			expect(AnnouncementRules.seconds("10")).to.equal(nil)
		end)
	end)
end
