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
local BuffService = require(script.Parent.BuffService)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local LevelRules = require(ReplicatedStorage.Shared.LevelRules)
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

	-- Captured before anything changes: both the defeat count and a level-up
	-- from the added score can unlock bosses.
	local unlockedBefore =
		asSet(ProgressionRules.unlockedBossIds(data.BossDefeats, LevelRules.levelFor(data.Xp)))

	SessionService.addScore(player, reward.Score)
	-- XP follows score, boosted by any XP buff (Score itself stays unboosted).
	SessionService.addXp(player, reward.Score * BuffService.xpMultiplier(player))
	SessionService.addCoins(player, reward.Coins)

	local stressRelieved = 0
	if reward.Qualifies then
		data.TotalBossesDefeated += 1
		data.BossDefeats[definition.Id] = (data.BossDefeats[definition.Id] or 0) + 1
		-- Last, so a Zen moment it may trigger sees the updated coins.
		stressRelieved = StressService.relieve(player, GameConfig.DefeatStressRelief)
	end

	local newlyUnlocked: { string } = {}
	for _, bossId in
		ProgressionRules.unlockedBossIds(data.BossDefeats, LevelRules.levelFor(data.Xp))
	do
		if not unlockedBefore[bossId] then
			table.insert(newlyUnlocked, bossId)
		end
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
