--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local BossPersonalityConfig = require(ReplicatedStorage.Config.BossPersonalityConfig)
local Checks = require(ServerScriptService.Tests.Helpers.Checks)

local FIDGETS = { "Hurry", "Glance", "Jitter", "Tilt", "Yawn", "Puff" }

local function allLines(): { string }
	local lines: { string } = {}
	for _, personality in BossPersonalityConfig.Types do
		for _, line in personality.ApproachLines do
			table.insert(lines, line)
		end
		for _, line in personality.HitLines do
			table.insert(lines, line)
		end
	end
	for _, line in BossPersonalityConfig.LockedLines do
		table.insert(lines, line)
	end
	return lines
end

return function()
	describe("BossPersonalityConfig", function()
		it("gives every boss a personality", function()
			for _, boss in BossConfig.List do
				expect(BossPersonalityConfig.ByBossId[boss.Id]).never.to.equal(nil)
			end
			local ceo = BossConfig.ById.the_ceo
			if ceo then
				expect(BossPersonalityConfig.ByBossId.the_ceo).never.to.equal(nil)
			end
			expect(BossPersonalityConfig.Default).never.to.equal(nil)
		end)

		it("keeps every line short, non-empty and family-friendly", function()
			for _, line in allLines() do
				expect(#line > 0).to.equal(true)
				expect(#line <= BossPersonalityConfig.MaxLineLength).to.equal(true)
				local found = Checks.blockedWord(line)
				if found then
					error(string.format("%q contains %q", line, found))
				end
			end
		end)

		it("has something to say on approach and on hits", function()
			for _, personality in BossPersonalityConfig.Types do
				expect(#personality.ApproachLines > 0).to.equal(true)
				expect(#personality.HitLines > 0).to.equal(true)
			end
		end)

		it("keeps motion small and sounds reasonable", function()
			for _, personality in BossPersonalityConfig.Types do
				expect(personality.ShuffleStuds >= 0).to.equal(true)
				expect(personality.ShuffleStuds <= BossPersonalityConfig.MaxShuffleStuds).to.equal(
					true
				)
				expect(personality.LookDegrees <= BossPersonalityConfig.MaxLookDegrees).to.equal(
					true
				)
				expect(personality.BobHeight > 0 and personality.BobHeight < 0.5).to.equal(true)
				expect(personality.Pitch >= 0.5 and personality.Pitch <= 2).to.equal(true)
				expect(table.find(FIDGETS, personality.Fidget)).never.to.equal(nil)
			end
		end)

		it("limits how often bosses make noise", function()
			expect(BossPersonalityConfig.HitSoundCooldown >= 0.5).to.equal(true)
			expect(BossPersonalityConfig.HitLineCooldown >= 2).to.equal(true)
			expect(BossPersonalityConfig.HitLineChance <= 0.5).to.equal(true)
			expect(BossPersonalityConfig.ApproachCooldown >= 5).to.equal(true)
			expect(BossPersonalityConfig.LeaveStuds > BossPersonalityConfig.ApproachStuds).to.equal(
				true
			)
			expect(BossPersonalityConfig.SoundVolume <= 1).to.equal(true)
		end)
	end)
end
