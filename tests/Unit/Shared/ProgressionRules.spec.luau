--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)
local ProgressionRules = require(ReplicatedStorage.Shared.ProgressionRules)

local FIRST = BossConfig.List[1]
local SECOND = BossConfig.List[2]
local THIRD = BossConfig.List[3]

-- The cheapest hammer that costs coins.
local function firstPaidHammer(): HammerConfig.HammerDefinition
	for _, hammer in HammerConfig.List do
		if hammer.Price > 0 then
			return hammer
		end
	end
	error("no paid hammer configured")
end

return function()
	describe("ProgressionRules boss unlocks", function()
		it("always unlocks the first boss", function()
			expect(ProgressionRules.isBossUnlocked(FIRST.Id, {})).to.equal(true)
		end)

		it("locks the second boss until the first is defeated enough times", function()
			local status = ProgressionRules.unlockStatus(SECOND.Id, {})
			expect(status.Unlocked).to.equal(false)
			expect(status.PreviousBossId).to.equal(FIRST.Id)
			expect(status.DefeatsNeeded).to.equal(SECOND.UnlockDefeats)
		end)

		it("counts down remaining defeats and unlocks at the requirement", function()
			local almost = { [FIRST.Id] = SECOND.UnlockDefeats - 1 }
			expect(ProgressionRules.unlockStatus(SECOND.Id, almost).DefeatsNeeded).to.equal(1)
			expect(ProgressionRules.isBossUnlocked(SECOND.Id, almost)).to.equal(false)

			local enough = { [FIRST.Id] = SECOND.UnlockDefeats }
			expect(ProgressionRules.isBossUnlocked(SECOND.Id, enough)).to.equal(true)
			expect(ProgressionRules.unlockStatus(SECOND.Id, enough).DefeatsNeeded).to.equal(0)
		end)

		it("only counts the previous boss, not other bosses", function()
			-- Lots of first-boss defeats don't unlock the third boss.
			local defeats = { [FIRST.Id] = 99 }
			expect(ProgressionRules.isBossUnlocked(THIRD.Id, defeats)).to.equal(false)
		end)

		it("treats unknown bosses as locked", function()
			expect(ProgressionRules.isBossUnlocked("not_a_boss", {})).to.equal(false)
		end)

		it("lists unlocked bosses in order", function()
			local ids = ProgressionRules.unlockedBossIds({ [FIRST.Id] = SECOND.UnlockDefeats })
			expect(#ids).to.equal(2)
			expect(ids[1]).to.equal(FIRST.Id)
			expect(ids[2]).to.equal(SECOND.Id)
		end)
	end)

	describe("ProgressionRules hammer shop", function()
		it("owns free hammers without buying them", function()
			expect(ProgressionRules.ownsHammer(GameConfig.DefaultHammerId, {})).to.equal(true)
		end)

		it("does not own paid hammers until bought", function()
			local paid = firstPaidHammer()
			expect(ProgressionRules.ownsHammer(paid.Id, {})).to.equal(false)
			expect(ProgressionRules.ownsHammer(paid.Id, { [paid.Id] = true })).to.equal(true)
		end)

		it("allows a purchase with exactly enough coins", function()
			local paid = firstPaidHammer()
			expect(ProgressionRules.checkPurchase(paid.Id, paid.Price, {})).to.equal("Ok")
		end)

		it("refuses a purchase one coin short", function()
			local paid = firstPaidHammer()
			expect(ProgressionRules.checkPurchase(paid.Id, paid.Price - 1, {})).to.equal(
				"NotEnoughCoins"
			)
		end)

		it("refuses buying a hammer twice, including free ones", function()
			local paid = firstPaidHammer()
			expect(ProgressionRules.checkPurchase(paid.Id, 1e6, { [paid.Id] = true })).to.equal(
				"AlreadyOwned"
			)
			expect(ProgressionRules.checkPurchase(GameConfig.DefaultHammerId, 1e6, {})).to.equal(
				"AlreadyOwned"
			)
		end)

		it("refuses unknown hammers", function()
			expect(ProgressionRules.checkPurchase("free_win_hammer", 1e6, {})).to.equal(
				"UnknownHammer"
			)
			expect(ProgressionRules.ownsHammer("free_win_hammer", { free_win_hammer = true })).to.equal(
				false
			)
		end)
	end)
end
