--!strict
--[[
	Pure boss-defeat reward maths (docs/GAMEPLAY_RULES.md):
	  * score and coins are split by the share of the boss's HP each player dealt
	    (overkill isn't credited, so shares add up to 100 %);
	  * the defeating hit earns LastHitBonusShare of the boss's reward on top
	    (at least 1 score and 1 coin);
	  * coins get the player's Zen Level bonus;
	  * only players with at least MinRewardDamageShare "qualify": their defeat
	    counts toward unlocks and they get the stress bonus;
	  * qualifying players may get a store boost: always from a custom boss,
	    otherwise (office and event bosses) with the current drop chance
	    (Shared/DropRateRules).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)

export type DefeatReward = {
	Score: number,
	Coins: number,
	Share: number, -- 0..1 of the boss's HP this player dealt
	Qualifies: boolean, -- defeat counts toward unlocks + stress bonus
	LastHit: boolean,
}

local RewardRules = {}

local function round(value: number): number
	return math.floor(value + 0.5)
end

-- Multiplier on boss coins from Zen Level (1 + 5 % per level, capped).
function RewardRules.zenCoinMultiplier(zenLevel: number): number
	local levels = math.clamp(math.floor(zenLevel), 0, GameConfig.ZenCoinBonusMaxLevel)
	return 1 + levels * GameConfig.ZenCoinBonusPerLevel
end

function RewardRules.defeatReward(
	boss: BossConfig.BossDefinition,
	damageDealt: number,
	isLastHitter: boolean,
	zenLevel: number
): DefeatReward
	local share = math.clamp(damageDealt / boss.MaxHealth, 0, 1)
	local score = boss.ScoreReward * share
	local coins = boss.CoinReward * share
	if isLastHitter then
		score += math.max(1, boss.ScoreReward * GameConfig.LastHitBonusShare)
		coins += math.max(1, boss.CoinReward * GameConfig.LastHitBonusShare)
	end
	coins *= RewardRules.zenCoinMultiplier(zenLevel)

	return {
		Score = round(score),
		Coins = round(coins),
		Share = share,
		-- Small tolerance: 10 of 100 HP must count as exactly 10 %.
		Qualifies = share + 1e-9 >= GameConfig.MinRewardDamageShare,
		LastHit = isLastHitter,
	}
end

-- Whether a qualifying player gets a buff drop, for a roll in [0, 1) and the
-- office boss drop chance in effect.
function RewardRules.dropsBuff(
	boss: BossConfig.BossDefinition,
	roll: number,
	chance: number
): boolean
	if boss.Custom and not boss.Event and not boss.Mission then
		return true
	end
	return roll < chance
end

return RewardRules
