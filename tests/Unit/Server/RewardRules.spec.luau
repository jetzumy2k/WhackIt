--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local RewardRules = require(ServerScriptService.Lib.RewardRules)

local function boss(maxHealth: number, score: number, coins: number): BossConfig.BossDefinition
	return {
		Id = "test_boss",
		DisplayName = "Test",
		Description = "Test",
		MaxHealth = maxHealth,
		DamageTakenMultiplier = 1,
		ScoreReward = score,
		CoinReward = coins,
		UnlockDefeats = 0,
	}
end

return function()
	describe("RewardRules.defeatReward", function()
		it("splits score and coins by damage share", function()
			local reward = RewardRules.defeatReward(boss(100, 200, 40), 25, false, 0)
			expect(reward.Share).to.equal(0.25)
			expect(reward.Score).to.equal(50)
			expect(reward.Coins).to.equal(10)
		end)

		it("gives a solo player the whole reward", function()
			local reward = RewardRules.defeatReward(boss(100, 100, 10), 100, false, 0)
			expect(reward.Score).to.equal(100)
			expect(reward.Coins).to.equal(10)
		end)

		it("adds 5% of the boss reward for the last hit", function()
			local normal = RewardRules.defeatReward(boss(100, 200, 40), 50, false, 0)
			local lastHit = RewardRules.defeatReward(boss(100, 200, 40), 50, true, 0)
			expect(lastHit.LastHit).to.equal(true)
			expect(lastHit.Score - normal.Score).to.equal(
				math.floor(200 * GameConfig.LastHitBonusShare + 0.5)
			)
			expect(lastHit.Coins - normal.Coins).to.equal(
				math.floor(40 * GameConfig.LastHitBonusShare + 0.5)
			)
		end)

		it("gives at least 1 score and 1 coin for the last hit on cheap bosses", function()
			local normal = RewardRules.defeatReward(boss(100, 10, 10), 50, false, 0)
			local lastHit = RewardRules.defeatReward(boss(100, 10, 10), 50, true, 0)
			expect(lastHit.Score - normal.Score >= 1).to.equal(true)
			expect(lastHit.Coins - normal.Coins >= 1).to.equal(true)
		end)

		it("qualifies at exactly the minimum share, not below", function()
			local threshold = GameConfig.MinRewardDamageShare * 100
			expect(RewardRules.defeatReward(boss(100, 100, 10), threshold, false, 0).Qualifies).to.equal(
				true
			)
			expect(RewardRules.defeatReward(boss(100, 100, 10), threshold - 1, false, 0).Qualifies).to.equal(
				false
			)
		end)

		it("still pays a small share to non-qualifying contributors", function()
			local reward = RewardRules.defeatReward(boss(100, 300, 50), 5, false, 0)
			expect(reward.Qualifies).to.equal(false)
			expect(reward.Score).to.equal(15)
		end)

		it("boosts only coins with the Zen Level bonus", function()
			local plain = RewardRules.defeatReward(boss(100, 100, 100), 100, false, 0)
			local zen = RewardRules.defeatReward(boss(100, 100, 100), 100, false, 2)
			expect(zen.Score).to.equal(plain.Score)
			expect(zen.Coins).to.equal(
				math.floor(100 * (1 + 2 * GameConfig.ZenCoinBonusPerLevel) + 0.5)
			)
		end)

		it("never pays out more than the boss reward plus the last-hit bonus in total", function()
			local definition = boss(120, 150, 20)
			local shares = { 40, 50, 30 } -- adds up to MaxHealth
			local totalScore = 0
			for index, damage in shares do
				totalScore += RewardRules.defeatReward(definition, damage, index == 2, 0).Score
			end
			local cap = 150 + math.max(1, 150 * GameConfig.LastHitBonusShare) + #shares -- rounding slack
			expect(totalScore <= cap).to.equal(true)
		end)
	end)

	describe("RewardRules.zenCoinMultiplier", function()
		it("adds the per-level bonus and stops at the cap", function()
			expect(RewardRules.zenCoinMultiplier(0)).to.equal(1)
			expect(RewardRules.zenCoinMultiplier(1)).to.equal(1 + GameConfig.ZenCoinBonusPerLevel)
			local capped = 1 + GameConfig.ZenCoinBonusMaxLevel * GameConfig.ZenCoinBonusPerLevel
			expect(RewardRules.zenCoinMultiplier(GameConfig.ZenCoinBonusMaxLevel + 50)).to.equal(
				capped
			)
		end)
	end)

	describe("RewardRules.dropsBuff", function()
		it("drops from an office boss only when the roll is below the chance", function()
			local office = boss(100, 10, 10)
			expect(RewardRules.dropsBuff(office, 0.29, 0.3)).to.equal(true)
			expect(RewardRules.dropsBuff(office, 0.3, 0.3)).to.equal(false)
			expect(RewardRules.dropsBuff(office, 0, 0)).to.equal(false)
		end)

		it("always drops from a custom boss", function()
			local custom = table.clone(boss(100, 10, 10)) :: any
			custom.Custom = true
			expect(RewardRules.dropsBuff(custom, 0.999999, 0)).to.equal(true)
		end)
	end)
end
