--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyEventConfig = require(ReplicatedStorage.Config.DailyEventConfig)
local DailyEventRules = require(ReplicatedStorage.Shared.DailyEventRules)

-- 2026-10-10 23:30 UTC.
local NOW = 1791675000
local DAY = 86400

local function today(): (DailyEventRules.State, DailyEventConfig.DailyEvent)
	local state = DailyEventRules.default()
	DailyEventRules.refresh(state, NOW)
	return state, DailyEventRules.eventFor(NOW)
end

-- An activity today's event counts, and its weight.
local function counted(dailyEvent: DailyEventConfig.DailyEvent): (string, number)
	for event, weight in dailyEvent.Points do
		return event, weight
	end
	error("event counts nothing")
end

return function()
	describe("DailyEventRules schedule", function()
		it("runs one event per UTC day, the same everywhere, cycling the rotation", function()
			local rotation = DailyEventConfig.Rotation
			local seen: { [string]: boolean } = {}
			for day = 0, #rotation - 1 do
				local event = DailyEventRules.eventFor(NOW + day * DAY)
				expect(seen[event.Id]).to.equal(nil)
				seen[event.Id] = true
			end
			expect(DailyEventRules.eventFor(NOW)).to.equal(
				DailyEventRules.eventFor(NOW + #rotation * DAY)
			)
			-- Within a day it never changes.
			local midnight = DailyEventRules.endsAt(NOW)
			expect(DailyEventRules.eventFor(midnight - 1)).to.equal(DailyEventRules.eventFor(NOW))
			expect(DailyEventRules.eventFor(midnight)).never.to.equal(DailyEventRules.eventFor(NOW))
			expect(midnight - NOW).to.equal(30 * 60)
		end)
	end)

	describe("DailyEventRules points and tiers", function()
		it("counts only what today's event weights", function()
			local state, dailyEvent = today()
			local event, weight = counted(dailyEvent)
			expect(DailyEventRules.pointsFor(dailyEvent, "NotAnEvent", 5)).to.equal(0)
			expect(#DailyEventRules.add(state, dailyEvent, "NotAnEvent", 5)).to.equal(0)
			expect(state.Points).to.equal(0)
			DailyEventRules.add(state, dailyEvent, event, 2)
			expect(state.Points).to.equal(2 * weight)
		end)

		it("ignores bad amounts", function()
			local state, dailyEvent = today()
			local event = counted(dailyEvent)
			for _, amount in { 0, -1, 0 / 0, math.huge } do
				DailyEventRules.add(state, dailyEvent, event, amount)
			end
			expect(state.Points).to.equal(0)
		end)

		it("pays each tier once, even several at a time, and stops at the last", function()
			local state, dailyEvent = today()
			local event, weight = counted(dailyEvent)
			local tiers = DailyEventConfig.Tiers
			local reached = DailyEventRules.add(state, dailyEvent, event, tiers[2].Points / weight)
			expect(#reached).to.equal(2)
			expect(reached[1]).to.equal(1)
			expect(reached[2]).to.equal(2)
			expect(#DailyEventRules.add(state, dailyEvent, event, 0.0001)).to.equal(0)
			local last =
				DailyEventRules.add(state, dailyEvent, event, tiers[#tiers].Points * 10 / weight)
			expect(#last).to.equal(#tiers - 2)
			expect(state.Tiers).to.equal(#tiers)
			expect(#DailyEventRules.add(state, dailyEvent, event, 100)).to.equal(0)
		end)

		it("starts over on a new day, and only then", function()
			local state, dailyEvent = today()
			local event, weight = counted(dailyEvent)
			DailyEventRules.add(state, dailyEvent, event, DailyEventConfig.Tiers[1].Points / weight)
			DailyEventRules.refresh(state, NOW + 60)
			expect(state.Tiers).to.equal(1)
			DailyEventRules.refresh(state, NOW + DAY)
			expect(state.Points).to.equal(0)
			expect(state.Tiers).to.equal(0)
			expect(state.DayKey).to.equal("2026-10-11")
		end)
	end)

	describe("DailyEventRules saved state", function()
		it("keeps a good state and repairs a broken one", function()
			local good =
				DailyEventRules.sanitize({ DayKey = "2026-10-10", Points = 42.5, Tiers = 1 })
			expect(good.Points).to.equal(42.5)
			expect(good.Tiers).to.equal(1)
			expect(DailyEventRules.shownPoints(good)).to.equal(42)
			local broken = DailyEventRules.sanitize({ DayKey = "yesterday", Points = 9, Tiers = 3 })
			expect(broken.DayKey).to.equal("")
			expect(broken.Points).to.equal(0)
			local clamped =
				DailyEventRules.sanitize({ DayKey = "2026-10-10", Points = -5, Tiers = 99 })
			expect(clamped.Points).to.equal(0)
			expect(clamped.Tiers).to.equal(#DailyEventConfig.Tiers)
			expect(DailyEventRules.sanitize("x").DayKey).to.equal("")
		end)
	end)
end
