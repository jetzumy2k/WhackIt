--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestConfig = require(ReplicatedStorage.Config.QuestConfig)
local QuestRules = require(ReplicatedStorage.Shared.QuestRules)

-- 2026-10-10 23:30 UTC, a Saturday.
local SATURDAY = 1791675000
local DAY = 86400

local function fresh(level: number?): QuestRules.State
	local state = QuestRules.default()
	QuestRules.refresh(state, SATURDAY, level or 50, Random.new(1))
	return state
end

local function finish(slot: QuestRules.Slot): ()
	slot.Progress = (QuestRules.questOf(slot) :: QuestConfig.Quest).Target
end

return function()
	describe("QuestRules windows", function()
		it("uses UTC days and weeks from Monday", function()
			expect(QuestRules.dayKey(SATURDAY)).to.equal("2026-10-10")
			expect(QuestRules.nextDailyReset(SATURDAY) - SATURDAY).to.equal(30 * 60)
			-- Saturday 23:30 -> Monday 00:00 is a day and a half.
			expect(QuestRules.nextWeeklyReset(SATURDAY) - SATURDAY).to.equal(DAY + 30 * 60)
			local monday = QuestRules.nextWeeklyReset(SATURDAY)
			expect(QuestRules.weekKey(monday)).never.to.equal(QuestRules.weekKey(monday - 1))
			expect(QuestRules.weekKey(monday)).to.equal(QuestRules.weekKey(monday + 6 * DAY))
		end)
	end)

	describe("QuestRules drawing", function()
		it("draws different daily and weekly quests on first use", function()
			local state = fresh()
			expect(#state.Daily).to.equal(QuestConfig.Slots.Daily)
			expect(#state.Weekly).to.equal(QuestConfig.Slots.Weekly)
			expect(state.DayKey).to.equal("2026-10-10")
			local seen: { [string]: boolean } = {}
			for _, slot in state.Daily do
				expect(seen[slot.Id]).to.equal(nil)
				seen[slot.Id] = true
				expect((QuestRules.questOf(slot) :: QuestConfig.Quest).Kind).to.equal("Daily")
			end
		end)

		it("respects level requirements", function()
			for seed = 1, 20 do
				local state = QuestRules.default()
				QuestRules.refresh(state, SATURDAY, 1, Random.new(seed))
				for _, slot in state.Daily do
					local quest = QuestRules.questOf(slot) :: QuestConfig.Quest
					expect((quest.MinLevel or 1) <= 1).to.equal(true)
				end
			end
		end)

		it("keeps quests within a day and redraws the next day, paying finished ones", function()
			local state = fresh()
			local first = state.Daily[1].Id
			expect(#QuestRules.refresh(state, SATURDAY + 60, 50, Random.new(2))).to.equal(0)
			expect(state.Daily[1].Id).to.equal(first)
			finish(state.Daily[1])
			state.Daily[2].Claimed = true
			finish(state.Daily[2])
			state.Rerolls = 1
			local expired = QuestRules.refresh(state, SATURDAY + DAY, 50, Random.new(3))
			expect(#expired).to.equal(1) -- the claimed one isn't paid twice
			expect(state.DayKey).to.equal("2026-10-11")
			expect(state.Rerolls).to.equal(0)
			expect(state.Daily[1].Progress).to.equal(0)
		end)
	end)

	describe("QuestRules progress and claims", function()
		it("counts only matching events, up to the target", function()
			local state = QuestRules.default()
			state.DayKey = "2026-10-10"
			state.Daily = { { Id = "d_bosses_3", Progress = 0, Claimed = false } }
			expect(#QuestRules.record(state, "ReachZen", 1)).to.equal(0)
			expect(state.Daily[1].Progress).to.equal(0)
			-- 2 finishes the tutorial's first step (1 boss), not the daily yet.
			expect(#QuestRules.record(state, "DefeatBoss", 2)).to.equal(1)
			local finished = QuestRules.record(state, "DefeatBoss", 5)
			expect(state.Daily[1].Progress).to.equal(3)
			expect(state.TutorialProgress).to.equal(1)
			expect(#finished).to.equal(1)
			expect(#QuestRules.record(state, "DefeatBoss", 1)).to.equal(0) -- already finished
		end)

		it("ignores bad amounts", function()
			local state = QuestRules.default()
			for _, amount in { 0, -3, 0 / 0, math.huge, 0.4 } do
				QuestRules.record(state, "DefeatBoss", amount)
			end
			expect(state.TutorialProgress).to.equal(0)
		end)

		it("pays a quest once and only when finished", function()
			local state = fresh()
			local quest, reason = QuestRules.claim(state, "Daily", 1)
			expect(quest).to.equal(nil)
			expect(reason).to.be.ok()
			finish(state.Daily[1])
			expect(QuestRules.claimableCount(state)).to.equal(1)
			expect((QuestRules.claim(state, "Daily", 1))).to.be.ok()
			expect((QuestRules.claim(state, "Daily", 1))).to.equal(nil)
			expect((QuestRules.claim(state, "Daily", 9))).to.equal(nil)
			expect((QuestRules.claim(state, "Nope", 1))).to.equal(nil)
			expect(QuestRules.claimableCount(state)).to.equal(0)
		end)

		it("walks the tutorial one step at a time", function()
			local state = QuestRules.default()
			local first = QuestConfig.Tutorial[1]
			expect((QuestRules.claim(state, "Tutorial"))).to.equal(nil)
			QuestRules.record(state, first.Event, first.Target)
			expect((QuestRules.claim(state, "Tutorial"))).to.equal(first)
			expect(state.TutorialStep).to.equal(2)
			expect(state.TutorialProgress).to.equal(0)
			state.TutorialStep = #QuestConfig.Tutorial + 1
			expect(QuestRules.tutorialQuest(state)).to.equal(nil)
			expect((QuestRules.claim(state, "Tutorial"))).to.equal(nil)
		end)

		it("gives the daily bonus once, after every daily is claimed", function()
			local state = fresh()
			expect(QuestRules.claimBonus(state)).to.equal(false)
			for index, slot in state.Daily do
				finish(slot)
				QuestRules.claim(state, "Daily", index)
			end
			expect(QuestRules.claimableCount(state)).to.equal(1)
			expect(QuestRules.claimBonus(state)).to.equal(true)
			expect(QuestRules.claimBonus(state)).to.equal(false)
		end)

		it("rerolls an unfinished daily once a day, to a quest not already there", function()
			local state = fresh()
			local before: { [string]: boolean } = {}
			for _, slot in state.Daily do
				before[slot.Id] = true
			end
			-- Partly done (one short of the target, which may be 1).
			local first = QuestRules.questOf(state.Daily[1]) :: QuestConfig.Quest
			state.Daily[1].Progress = first.Target - 1
			expect((QuestRules.reroll(state, 1, 50, Random.new(4)))).to.equal(true)
			expect(before[state.Daily[1].Id]).to.equal(nil)
			expect(state.Daily[1].Progress).to.equal(0)
			expect((QuestRules.reroll(state, 2, 50, Random.new(5)))).to.equal(false)
			state.Rerolls = 0
			finish(state.Daily[2])
			expect((QuestRules.reroll(state, 2, 50, Random.new(6)))).to.equal(false)
		end)
	end)

	describe("QuestRules saved state", function()
		it("drops unknown or wrong-kind quests and clamps progress", function()
			local weekly = QuestConfig.Weekly[1]
			local daily: { unknown } = {
				{ Id = "d_bosses_3", Progress = 999, Claimed = false },
				{ Id = "d_bosses_3", Progress = 1, Claimed = false },
				{ Id = weekly.Id, Progress = 1, Claimed = false },
				{ Id = "made_up", Progress = 1, Claimed = false },
				"junk",
			}
			local state = QuestRules.sanitize({
				DayKey = "2026-10-10",
				Daily = daily,
				Rerolls = 99,
				WeekKey = "Wx",
				TutorialStep = 0,
				TutorialProgress = -4,
			})
			expect(#state.Daily).to.equal(1)
			expect(state.Daily[1].Progress).to.equal(3)
			expect(state.Rerolls).to.equal(QuestConfig.DailyRerolls)
			expect(state.WeekKey).to.equal("")
			expect(state.TutorialStep).to.equal(1)
			expect(state.TutorialProgress).to.equal(0)
		end)

		it("redraws a day with no usable quests and copies without sharing", function()
			local state = QuestRules.sanitize({ DayKey = "2026-10-10", Daily = {} })
			expect(state.DayKey).to.equal("")
			local filled = fresh()
			local copy = QuestRules.copy(filled)
			copy.Daily[1].Progress = 2
			expect(filled.Daily[1].Progress).to.equal(0)
		end)
	end)
	describe("QuestRules.claimableList", function()
		it("lists each finished, unclaimed quest once, matching claimableCount", function()
			local state = QuestRules.default()
			state.DayKey = "2026-10-10"
			local daily = QuestConfig.Daily[1]
			state.Daily = {
				{ Id = daily.Id, Progress = daily.Target, Claimed = false },
				{ Id = daily.Id, Progress = 0, Claimed = false },
			}
			local ready = QuestRules.claimableList(state)
			expect(#ready).to.equal(QuestRules.claimableCount(state))
			local found = false
			for _, entry in ready do
				if entry.Kind == "Daily" then
					found = true
					expect(entry.Key).to.equal("Daily:2026-10-10:" .. daily.Id)
					expect(entry.Text).to.equal(daily.Text)
				end
			end
			expect(found).to.equal(true)
			state.Daily[1].Claimed = true
			for _, entry in QuestRules.claimableList(state) do
				expect(entry.Kind).never.to.equal("Daily")
			end
		end)
	end)
end
