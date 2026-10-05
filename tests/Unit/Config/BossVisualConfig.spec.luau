--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local BossVisualConfig = require(ReplicatedStorage.Config.BossVisualConfig)

-- Long enough for the jokes, short enough to stay readable on the sign.
local MAX_SIGN_LENGTH = 16

return function()
	describe("BossVisualConfig", function()
		it("gives every boss a look", function()
			for _, boss in BossConfig.List do
				expect(BossVisualConfig[boss.Id]).never.to.equal(nil)
			end
		end)

		it("has no looks for bosses that don't exist", function()
			for bossId in BossVisualConfig do
				expect(BossConfig.ById[bossId]).never.to.equal(nil)
			end
		end)

		it("keeps sign text short and non-empty", function()
			for _, look in BossVisualConfig do
				expect(#look.SignText > 0).to.equal(true)
				expect(#look.SignText <= MAX_SIGN_LENGTH).to.equal(true)
			end
		end)

		it("is read-only", function()
			expect(table.isfrozen(BossVisualConfig)).to.equal(true)
			for _, look in BossVisualConfig do
				expect(table.isfrozen(look)).to.equal(true)
			end
		end)
	end)
end
