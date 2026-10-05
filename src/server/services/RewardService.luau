--!strict
--[[
	Grants boss-defeat rewards to every contributor (Lib/RewardRules):
	score and coins by damage share, a last-hit bonus, the Zen Level coin bonus,
	and, for players with at least MinRewardDamageShare, the stress bonus and a
	defeat count toward unlocking the next boss.

	Idempotent: BossState.markRewarded lets each player be rewarded at most once
	per boss life, no matter how often this is called.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossState = require(ServerScriptService.Lib.BossState)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)
local ProgressionRules = require(ReplicatedStorage.Shared.ProgressionRules)
local RewardRules = require(ServerScriptService.Lib.RewardRules)
local SessionService = require(script.Parent.SessionService)
local StressService = require(script.Parent.StressService)

export type Grant = {
	Score: number,
	Coins: number,
	Share: number,
	Qualified: boolean,
	LastHit: boolean,
	StressRelieved: number,
	UnlockedBossIds: { string }, -- bosses this defeat newly unlocked
}

local RewardService = {}

local function asSet(ids: { string }): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, id in ids do
		set[id] = true
	end
	return set
end

-- Returns what was granted, or nil if nothing was (already rewarded, data not
-- loaded, or the player dealt no damage).
function RewardService.grantDefeat(player: Player, state: BossState.BossState): Grant?
	local data = PlayerDataService.get(player)
	local damage = state.Contributions[player.UserId]
	if
		data == nil
		or damage == nil
		or damage <= 0
		or not BossState.markRewarded(state, player.UserId)
	then
		return nil
	end

	local definition = state.Definition
	local reward = RewardRules.defeatReward(
		definition,
		damage,
		state.LastHitterUserId == player.UserId,
		data.ZenLevel
	)

	SessionService.addScore(player, reward.Score)
	SessionService.addCoins(player, reward.Coins)

	local stressRelieved = 0
	local newlyUnlocked: { string } = {}
	if reward.Qualifies then
		local unlockedBefore = asSet(ProgressionRules.unlockedBossIds(data.BossDefeats))
		data.TotalBossesDefeated += 1
		data.BossDefeats[definition.Id] = (data.BossDefeats[definition.Id] or 0) + 1
		for _, bossId in ProgressionRules.unlockedBossIds(data.BossDefeats) do
			if not unlockedBefore[bossId] then
				table.insert(newlyUnlocked, bossId)
			end
		end
		-- Last, so a Zen moment it may trigger sees the updated coins.
		stressRelieved = StressService.relieve(player, GameConfig.DefeatStressRelief)
	end

	ProgressService.sync(player)
	return {
		Score = reward.Score,
		Coins = reward.Coins,
		Share = reward.Share,
		Qualified = reward.Qualifies,
		LastHit = reward.LastHit,
		StressRelieved = stressRelieved,
		UnlockedBossIds = newlyUnlocked,
	}
end

return RewardService
