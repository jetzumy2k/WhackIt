--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DropRateConfig = require(ReplicatedStorage.Config.DropRateConfig)
local DropRateRules = require(ReplicatedStorage.Shared.DropRateRules)

local function valid(): { [string]: unknown }
	return {
		NormalMin = 0.0005,
		NormalMax = 0.1,
		LuckyMin = 0.1,
		LuckyMax = 0.3,
		LuckyEveryMinutes = 120,
		LuckyLastsMinutes = 10,
	}
end

local function settings(): DropRateRules.Settings
	return (DropRateRules.parse(valid())) :: DropRateRules.Settings
end

return function()
	describe("DropRateRules.parse", function()
		it("accepts valid settings", function()
			local parsed = settings()
			expect(parsed).never.to.equal(nil)
			expect(parsed.LuckyMax).to.equal(0.3)
		end)

		it("rejects chances outside 0..1, non-numbers and non-finite values", function()
			local bads: { unknown } = { -0.1, 1.5, 0 / 0, math.huge, "0.1", nil }
			for _, bad in bads do
				local raw = valid()
				raw.LuckyMax = bad
				expect((DropRateRules.parse(raw))).to.equal(nil)
			end
			expect((DropRateRules.parse("fast"))).to.equal(nil)
		end)

		it("rejects a range whose min is above its max", function()
			local raw = valid()
			raw.NormalMin = 0.2
			expect((DropRateRules.parse(raw))).to.equal(nil)
		end)

		it("bounds the Lucky window and keeps it shorter than its cycle", function()
			local tooOften = valid()
			tooOften.LuckyEveryMinutes = DropRateConfig.MinEveryMinutes - 1
			expect((DropRateRules.parse(tooOften))).to.equal(nil)
			local fractional = valid()
			fractional.LuckyEveryMinutes = 120.5
			expect((DropRateRules.parse(fractional))).to.equal(nil)
			local always = valid()
			always.LuckyLastsMinutes = 120
			expect((DropRateRules.parse(always))).to.equal(nil)
			local never = valid()
			never.LuckyLastsMinutes = 0
			expect((DropRateRules.parse(never))).to.equal(nil)
		end)
	end)

	describe("DropRateRules Lucky window", function()
		it("is on for the first LuckyLastsMinutes of every cycle", function()
			local rates = settings()
			local cycle = 120 * 60
			expect(DropRateRules.isLucky(rates, 5 * cycle)).to.equal(true)
			expect(DropRateRules.isLucky(rates, 5 * cycle + 10 * 60 - 1)).to.equal(true)
			expect(DropRateRules.isLucky(rates, 5 * cycle + 10 * 60)).to.equal(false)
			expect(DropRateRules.isLucky(rates, 6 * cycle - 1)).to.equal(false)
		end)

		it("counts down to the next change", function()
			local rates = settings()
			local cycle = 120 * 60
			expect(DropRateRules.secondsUntilChange(rates, cycle)).to.equal(10 * 60)
			expect(DropRateRules.secondsUntilChange(rates, cycle + 10 * 60)).to.equal(110 * 60)
		end)
	end)

	describe("DropRateRules.chanceFor", function()
		it("stays in the Normal range outside the window", function()
			local rates = settings()
			local now = 60 * 60 -- 01:00 UTC, outside the window
			expect(DropRateRules.chanceFor(rates, now, 0)).to.equal(0.0005)
			expect(math.abs(DropRateRules.chanceFor(rates, now, 1) - 0.1) < 1e-12).to.equal(true)
			local mid = DropRateRules.chanceFor(rates, now, 0.5)
			expect(mid > 0.0005 and mid < 0.1).to.equal(true)
		end)

		it("uses the Lucky range inside the window", function()
			local rates = settings()
			expect(DropRateRules.chanceFor(rates, 0, 0)).to.equal(0.1)
			expect(math.abs(DropRateRules.chanceFor(rates, 0, 1) - 0.3) < 1e-12).to.equal(true)
			expect(math.abs(DropRateRules.chanceFor(rates, 0, 5) - 0.3) < 1e-12).to.equal(true)
		end)
	end)
end
