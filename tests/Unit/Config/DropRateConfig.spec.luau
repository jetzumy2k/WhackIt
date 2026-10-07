--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DropRateConfig = require(ReplicatedStorage.Config.DropRateConfig)
local DropRateRules = require(ReplicatedStorage.Shared.DropRateRules)

return function()
	describe("DropRateConfig", function()
		it("uses the requested defaults: 0.0005-0.10, and 0.10-0.30 every 2 hours", function()
			local default = DropRateConfig.Default
			expect(default.NormalMin).to.equal(0.0005)
			expect(default.NormalMax).to.equal(0.10)
			expect(default.LuckyMin).to.equal(0.10)
			expect(default.LuckyMax).to.equal(0.30)
			expect(default.LuckyEveryMinutes).to.equal(120)
		end)

		it("has defaults that pass the admin input rules", function()
			expect((DropRateRules.parse(DropRateConfig.Default))).never.to.equal(nil)
			expect(table.isfrozen(DropRateConfig)).to.equal(true)
		end)
	end)
end
