--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local CustomBossRules = require(ReplicatedStorage.Shared.CustomBossRules)
local MissionConfig = require(ReplicatedStorage.Config.MissionConfig)
local MissionRules = require(ReplicatedStorage.Shared.MissionRules)
local ProgressionRules = require(ReplicatedStorage.Shared.ProgressionRules)

local WAVE = MissionConfig.List[1].Waves[1]

return function()
	describe("MissionRules bosses", function()
		it("scales health with the team size", function()
			local base = MissionRules.bossHealth(WAVE, MissionConfig.TeamHealthBase)
			expect(base).to.equal(WAVE.Health)
			expect(MissionRules.bossHealth(WAVE, 3) > base).to.equal(true)
			expect(MissionRules.bossHealth(WAVE, 4) > MissionRules.bossHealth(WAVE, 3)).to.equal(
				true
			)
			expect(MissionRules.bossHealth(WAVE, 99)).to.equal(
				MissionRules.bossHealth(WAVE, MissionConfig.TeamMax)
			)
			expect(MissionRules.bossHealth(WAVE, 1) >= 1).to.equal(true)
		end)

		it("makes boss ids that are always open and never clash", function()
			local a = MissionRules.bossId(1, 1, 1, 1)
			local b = MissionRules.bossId(1, 2, 1, 1)
			local c = MissionRules.bossId(2, 1, 1, 1)
			expect(a).never.to.equal(b)
			expect(a).never.to.equal(c)
			expect(CustomBossRules.isCustomId(a)).to.equal(true)
			expect(ProgressionRules.isBossUnlocked(a, {}, 1, nil)).to.equal(true)
			expect(#a <= 64).to.equal(true)
		end)

		it("builds a mission boss definition from the wave", function()
			local definition = MissionRules.bossDefinition("custom_mission_x", WAVE, 2)
			expect(definition).to.be.ok()
			local boss = definition :: BossConfig.BossDefinition
			expect(boss.Mission).to.equal(true)
			expect(boss.Custom).to.equal(true)
			expect(boss.Event).to.equal(nil)
			expect(boss.LookId).to.equal(WAVE.Look)
			expect(boss.MaxHealth).to.equal(WAVE.Health)
			expect(boss.DisplayName).to.equal(WAVE.Name)
			local broken: MissionConfig.Wave =
				{ Look = "no_such_boss", Name = "X", Count = 1, Health = 10 }
			expect(MissionRules.bossDefinition("custom_mission_y", broken, 2)).to.equal(nil)
		end)

		it("spaces bosses at least 14 studs apart inside the room", function()
			for count = 1, 4 do
				local offsets = MissionRules.bossOffsets(count)
				expect(#offsets).to.equal(count)
				for i = 1, count do
					expect(math.abs(offsets[i].X) < MissionConfig.Rooms.Size / 2 - 6).to.equal(true)
					for j = i + 1, count do
						expect((offsets[i] - offsets[j]).Magnitude >= 14).to.equal(true)
					end
				end
			end
		end)

		it("puts rooms far apart", function()
			local a, b = MissionRules.roomCenter(1), MissionRules.roomCenter(2)
			expect((a - b).Magnitude >= MissionConfig.Rooms.Size).to.equal(true)
		end)
	end)

	describe("MissionRules contribution", function()
		it("counts players by hits against the team's average", function()
			local counted = MissionRules.counted(
				{ [1] = 40, [2] = 30, [3] = 4, [4] = 10 },
				{ 1, 2, 3, 4 }
			)
			-- Average 21: a quarter is 5.25, so 4 hits doesn't count, 10 does.
			expect(counted[1]).to.equal(true)
			expect(counted[2]).to.equal(true)
			expect(counted[3]).to.equal(nil)
			expect(counted[4]).to.equal(true)
		end)

		it("needs at least MinHits, and nobody counts without hits", function()
			local few = MissionRules.counted(
				{ [1] = MissionConfig.MinHits - 1, [2] = MissionConfig.MinHits - 1 },
				{ 1, 2 }
			)
			expect((next(few))).to.equal(nil)
			expect((next(MissionRules.counted({}, { 1, 2 })))).to.equal(nil)
			expect((next(MissionRules.counted({ [9] = 99 }, {})))).to.equal(nil)
		end)

		it("doesn't count hits from someone who isn't a member", function()
			local counted = MissionRules.counted({ [1] = 20, [2] = 20, [99] = 500 }, { 1, 2 })
			expect(counted[99]).to.equal(nil)
			expect(counted[1]).to.equal(true)
		end)
	end)

	describe("MissionRules daily record", function()
		it("caps rewarded missions per UTC day and starts over the next day", function()
			local record = MissionRules.defaultRecord()
			for _ = 1, MissionConfig.DailyRewarded do
				expect(MissionRules.canEarn(record, "2026-10-10")).to.equal(true)
				record.DayRewarded += 1
			end
			expect(MissionRules.canEarn(record, "2026-10-10")).to.equal(false)
			expect(MissionRules.canEarn(record, "2026-10-11")).to.equal(true)
			expect(record.DayRewarded).to.equal(0)
		end)

		it("cleans a saved record", function()
			local good =
				MissionRules.sanitizeRecord({ DayKey = "2026-10-10", DayRewarded = 2, Cleared = 7 })
			expect(good.DayRewarded).to.equal(2)
			expect(good.Cleared).to.equal(7)
			local broken =
				MissionRules.sanitizeRecord({ DayKey = "today", DayRewarded = 2, Cleared = -3 })
			expect(broken.DayKey).to.equal("")
			expect(broken.DayRewarded).to.equal(0)
			expect(broken.Cleared).to.equal(0)
			expect(MissionRules.sanitizeRecord(nil).Cleared).to.equal(0)
		end)
	end)
end
