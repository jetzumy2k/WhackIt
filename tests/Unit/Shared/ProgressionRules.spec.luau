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
			expect(ProgressionRules.isBossUnlocked(FIRST.Id, {}, 1)).to.equal(true)
		end)

		it("locks the second boss until the first is defeated enough times", function()
			local status = ProgressionRules.unlockStatus(SECOND.Id, {}, 1)
			expect(status.Unlocked).to.equal(false)
			expect(status.PreviousBossId).to.equal(FIRST.Id)
			expect(status.DefeatsNeeded).to.equal(SECOND.UnlockDefeats)
		end)

		it("counts down remaining defeats and unlocks at the requirement", function()
			local almost = { [FIRST.Id] = SECOND.UnlockDefeats - 1 }
			expect(ProgressionRules.unlockStatus(SECOND.Id, almost, 1).DefeatsNeeded).to.equal(1)
			expect(ProgressionRules.isBossUnlocked(SECOND.Id, almost, 1)).to.equal(false)

			local enough = { [FIRST.Id] = SECOND.UnlockDefeats }
			expect(ProgressionRules.isBossUnlocked(SECOND.Id, enough, 1)).to.equal(true)
			expect(ProgressionRules.unlockStatus(SECOND.Id, enough, 1).DefeatsNeeded).to.equal(0)
		end)

		it("only counts the previous boss, not other bosses", function()
			-- Lots of first-boss defeats don't unlock the third boss.
			local defeats = { [FIRST.Id] = 99 }
			expect(ProgressionRules.isBossUnlocked(THIRD.Id, defeats, 1)).to.equal(false)
		end)

		it("treats unknown bosses as locked", function()
			expect(ProgressionRules.isBossUnlocked("not_a_boss", {}, 1)).to.equal(false)
		end)

		it("lists unlocked bosses in order", function()
			local ids = ProgressionRules.unlockedBossIds({ [FIRST.Id] = SECOND.UnlockDefeats }, 1)
			expect(#ids).to.equal(2)
			expect(ids[1]).to.equal(FIRST.Id)
			expect(ids[2]).to.equal(SECOND.Id)
		end)
	end)

	describe("ProgressionRules Senior bosses (upstairs)", function()
		local senior = BossConfig.ById["senior_" .. FIRST.Id]
		local minLevel = GameConfig.UpstairsMinLevel

		it("exists for the first boss and needs the upstairs level", function()
			expect(senior).never.to.equal(nil)
			expect(senior.MinLevel).to.equal(minLevel)
		end)

		it("stays locked below the level even with every defeat done", function()
			local status =
				ProgressionRules.unlockStatus(senior.Id, { [FIRST.Id] = 99 }, minLevel - 1)
			expect(status.Unlocked).to.equal(false)
			expect(status.LevelNeeded).to.equal(minLevel)
			expect(status.DefeatsNeeded).to.equal(0)
		end)

		it("stays locked at the level until its ground-floor version is defeated", function()
			local status = ProgressionRules.unlockStatus(senior.Id, {}, minLevel)
			expect(status.Unlocked).to.equal(false)
			expect(status.LevelNeeded).to.equal(0)
			expect(status.PreviousBossId).to.equal(FIRST.Id)
		end)

		it("unlocks with the level and a defeat of the ground-floor version", function()
			expect(
				ProgressionRules.isBossUnlocked(
					senior.Id,
					{ [FIRST.Id] = senior.UnlockDefeats },
					minLevel
				)
			).to.equal(true)
		end)

		it("leaves ground-floor bosses unaffected by level", function()
			expect(ProgressionRules.unlockStatus(FIRST.Id, {}, 1).LevelNeeded).to.equal(0)
			expect(ProgressionRules.isBossUnlocked(FIRST.Id, {}, 1)).to.equal(true)
		end)

		it("doesn't list Senior bosses for a new player", function()
			for _, id in ProgressionRules.unlockedBossIds({ [FIRST.Id] = 99 }, 1) do
				expect(BossConfig.ById[id].MinLevel).to.equal(nil)
			end
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

		it("needs the Player Level for hammers with a MinLevel", function()
			local gated: HammerConfig.HammerDefinition? = nil
			for _, hammer in HammerConfig.List do
				if hammer.MinLevel and gated == nil then
					gated = hammer
				end
			end
			assert(gated and gated.MinLevel, "no hammer with a level requirement")
			local need = gated.MinLevel :: number
			expect(ProgressionRules.checkPurchase(gated.Id, 1e6, {}, nil, need - 1)).to.equal(
				"LevelTooLow"
			)
			expect(ProgressionRules.checkPurchase(gated.Id, 1e6, {}, nil, need)).to.equal("Ok")
			-- No level given counts as Level 1.
			expect(ProgressionRules.checkPurchase(gated.Id, 1e6, {})).to.equal("LevelTooLow")
			-- Owning it already is reported first.
			expect(ProgressionRules.checkPurchase(gated.Id, 1e6, { [gated.Id] = true }, nil, 1)).to.equal(
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
	describe("ProgressionRules CEO (Executive Floor)", function()
		local ceoId = "the_ceo"
		local level = GameConfig.UpstairsMinLevel

		local function allDefeatedExcept(skip: string?): { [string]: number }
			local defeats: { [string]: number } = {}
			for _, boss in BossConfig.List do
				if boss.Id ~= ceoId and boss.Id ~= skip then
					defeats[boss.Id] = 1
				end
			end
			return defeats
		end

		it("stays locked while any other boss has never been beaten", function()
			local status = ProgressionRules.unlockStatus(ceoId, allDefeatedExcept(FIRST.Id), level)
			expect(status.Unlocked).to.equal(false)
			expect(status.DefeatsNeeded).to.equal(1)
		end)

		it("counts how many bosses are still left to beat", function()
			local status = ProgressionRules.unlockStatus(ceoId, {}, level)
			-- Every boss but the CEO and the Principal tier (PostCeo, 4th floor).
			local others = 0
			for _, boss in BossConfig.List do
				if boss.Id ~= ceoId and not boss.PostCeo then
					others += 1
				end
			end
			expect(status.DefeatsNeeded).to.equal(others)
		end)

		it("never needs the Principal tier (Phase 3a)", function()
			local defeats = allDefeatedExcept(nil)
			for _, boss in BossConfig.List do
				if boss.PostCeo then
					defeats[boss.Id] = nil
				end
			end
			expect(ProgressionRules.isBossUnlocked(ceoId, defeats, level)).to.equal(true)
		end)

		it("unlocks once every other boss is beaten at the required level", function()
			expect(ProgressionRules.isBossUnlocked(ceoId, allDefeatedExcept(nil), level)).to.equal(
				true
			)
		end)

		it("still needs the level", function()
			expect(ProgressionRules.isBossUnlocked(ceoId, allDefeatedExcept(nil), level - 1)).to.equal(
				false
			)
		end)
	end)
	describe("ProgressionRules Principal bosses (4th floor)", function()
		local principal = BossConfig.ById.principal_deadline_boss
		local senior = "senior_deadline_boss"

		it("needs Level 30 and a defeat of the Senior version", function()
			expect(principal).never.to.equal(nil)
			local high = GameConfig.PrincipalMinLevel
			expect(ProgressionRules.isBossUnlocked(principal.Id, { [senior] = 1 }, high)).to.equal(
				true
			)
			expect(ProgressionRules.isBossUnlocked(principal.Id, { [senior] = 1 }, high - 1)).to.equal(
				false
			)
			expect(ProgressionRules.isBossUnlocked(principal.Id, {}, high)).to.equal(false)
		end)
	end)
	describe("ProgressionRules admin unlocks and custom bosses", function()
		it("opens a locked boss the admin unlocked", function()
			expect(ProgressionRules.isBossUnlocked(SECOND.Id, {}, 1)).to.equal(false)
			local unlocks = { [SECOND.Id] = true }
			expect(ProgressionRules.isBossUnlocked(SECOND.Id, {}, 1, unlocks)).to.equal(true)
			expect(ProgressionRules.isBossUnlocked(THIRD.Id, {}, 1, unlocks)).to.equal(false)
		end)

		it("opens a Senior boss below its level when admin-unlocked", function()
			local senior = BossConfig.ById["senior_" .. FIRST.Id]
			expect(ProgressionRules.isBossUnlocked(senior.Id, {}, 1)).to.equal(false)
			expect(ProgressionRules.isBossUnlocked(senior.Id, {}, 1, { [senior.Id] = true })).to.equal(
				true
			)
		end)

		it("lists admin-unlocked bosses as unlocked", function()
			local ids = ProgressionRules.unlockedBossIds({}, 1, { [THIRD.Id] = true })
			expect(table.find(ids, THIRD.Id)).never.to.equal(nil)
			expect(table.find(ids, SECOND.Id)).to.equal(nil)
		end)

		it("always opens custom bosses, and still locks unknown ids", function()
			expect(ProgressionRules.isBossUnlocked("custom_1_1234", {}, 1)).to.equal(true)
			expect(ProgressionRules.isBossUnlocked("no_such_boss", {}, 1)).to.equal(false)
		end)
	end)
end
