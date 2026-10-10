--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local HudFormat = require(ServerScriptService.ClientLib.HudFormat)

return function()
	describe("HudFormat", function()
		it("groups thousands", function()
			expect(HudFormat.thousands(0)).to.equal("0")
			expect(HudFormat.thousands(999)).to.equal("999")
			expect(HudFormat.thousands(1000)).to.equal("1,000")
			expect(HudFormat.thousands(1234567)).to.equal("1,234,567")
			expect(HudFormat.thousands(-4500)).to.equal("-4,500")
		end)

		it("shows a calm face at Zen and a frazzled one when full", function()
			expect(HudFormat.moodIcon(0)).to.equal("🧘")
			expect(HudFormat.moodIcon(GameConfig.MaxStress)).to.equal("😫")
		end)

		it("colours the meter green when calm and red when frazzled", function()
			local calm, full = HudFormat.stressColor(0), HudFormat.stressColor(1)
			expect(calm.G > calm.R).to.equal(true)
			expect(full.R > full.G).to.equal(true)
			-- Out-of-range values are clamped.
			expect(HudFormat.stressColor(5)).to.equal(full)
		end)
	end)
end
