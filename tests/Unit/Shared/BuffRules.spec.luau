--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuffRules = require(ReplicatedStorage.Shared.BuffRules)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)

return function()
	describe("BuffRules.add", function()
		it("starts a new buff", function()
			local buff = BuffRules.add(nil, 10, 1800)
			expect(buff.Percent).to.equal(10)
			expect(buff.SecondsLeft).to.equal(1800)
		end)

		it("adds time and keeps the strongest percent", function()
			local buff = BuffRules.add({ Percent = 20, SecondsLeft = 600 }, 10, 1800)
			expect(buff.Percent).to.equal(20)
			expect(buff.SecondsLeft).to.equal(2400)
			local stronger = BuffRules.add({ Percent = 10, SecondsLeft = 600 }, 25, 1800)
			expect(stronger.Percent).to.equal(25)
			expect(stronger.SecondsLeft).to.equal(2400)
		end)

		it("treats a used-up buff as new", function()
			local buff = BuffRules.add({ Percent = 25, SecondsLeft = 0 }, 10, 60)
			expect(buff.Percent).to.equal(10)
			expect(buff.SecondsLeft).to.equal(60)
		end)

		it("caps banked time at MaxBuffSeconds", function()
			local buff = BuffRules.add(
				{ Percent = 10, SecondsLeft = StoreConfig.MaxBuffSeconds - 10 },
				10,
				18000
			)
			expect(buff.SecondsLeft).to.equal(StoreConfig.MaxBuffSeconds)
		end)
	end)

	describe("BuffRules.tick", function()
		it("counts down", function()
			local buff = BuffRules.tick({ Percent = 5, SecondsLeft = 10 }, 1)
			expect(buff).never.to.equal(nil)
			expect((buff :: BuffRules.Buff).SecondsLeft).to.equal(9)
		end)

		it("ends the buff when time runs out", function()
			expect(BuffRules.tick({ Percent = 5, SecondsLeft = 1 }, 1)).to.equal(nil)
		end)
	end)

	describe("BuffRules.fraction", function()
		it("is 0 with no buff or no time", function()
			expect(BuffRules.fraction(nil)).to.equal(0)
			expect(BuffRules.fraction({ Percent = 10, SecondsLeft = 0 })).to.equal(0)
		end)

		it("converts percent to a fraction", function()
			expect(BuffRules.fraction({ Percent = 25, SecondsLeft = 5 })).to.equal(0.25)
		end)
	end)
end
