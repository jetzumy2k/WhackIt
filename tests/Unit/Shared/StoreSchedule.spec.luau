--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StoreSchedule = require(ReplicatedStorage.Shared.StoreSchedule)

return function()
	local NOW = 1_800_000_000

	describe("StoreSchedule.isOpen", function()
		it("is always open in On mode and never in Off mode", function()
			expect(StoreSchedule.isOpen(StoreSchedule.default("On"), NOW)).to.equal(true)
			expect(StoreSchedule.isOpen(StoreSchedule.default("Off"), NOW)).to.equal(false)
		end)

		it("is open from StartsAt up to (not including) EndsAt", function()
			local settings: StoreSchedule.Settings =
				{ Mode = "Schedule", StartsAt = NOW, EndsAt = NOW + 60 }
			expect(StoreSchedule.isOpen(settings, NOW - 1)).to.equal(false)
			expect(StoreSchedule.isOpen(settings, NOW)).to.equal(true)
			expect(StoreSchedule.isOpen(settings, NOW + 59)).to.equal(true)
			expect(StoreSchedule.isOpen(settings, NOW + 60)).to.equal(false)
		end)
	end)

	describe("StoreSchedule.parse", function()
		it("accepts On and Off", function()
			local on = StoreSchedule.parse({ Mode = "On" }, NOW)
			expect(on and on.Mode).to.equal("On")
			local off = StoreSchedule.parse({ Mode = "Off", StartsAt = 5 }, NOW)
			expect(off and off.StartsAt).to.equal(0)
		end)

		it("accepts a valid future schedule, flooring times", function()
			local settings = StoreSchedule.parse(
				{ Mode = "Schedule", StartsAt = NOW + 0.7, EndsAt = NOW + 3600.9 },
				NOW
			)
			expect(settings).never.to.equal(nil)
			expect((settings :: StoreSchedule.Settings).StartsAt).to.equal(NOW)
			expect((settings :: StoreSchedule.Settings).EndsAt).to.equal(NOW + 3600)
		end)

		it("rejects bad input", function()
			local bad: { unknown } = {
				"On",
				{ Mode = "Maybe" },
				{ Mode = "Schedule", StartsAt = NOW, EndsAt = NOW }, -- ends when it starts
				{ Mode = "Schedule", StartsAt = NOW - 100, EndsAt = NOW - 10 }, -- already over
				{
					Mode = "Schedule",
					StartsAt = NOW,
					EndsAt = NOW + StoreSchedule.MAX_AHEAD_SECONDS + 1,
				},
				{ Mode = "Schedule", StartsAt = 0 / 0, EndsAt = NOW + 60 },
				{ Mode = "Schedule", StartsAt = NOW, EndsAt = math.huge },
				{ Mode = "Schedule", StartsAt = "soon", EndsAt = NOW + 60 },
			}
			for _, raw in bad do
				expect(StoreSchedule.parse(raw, NOW)).to.equal(nil)
			end
		end)
	end)
end
