--!strict
--[[
	Grants boss-defeat rewards: score, coins, the stress bonus and the defeat
	counters that unlock the next boss. Called by CombatService for each
	qualifying contributor.

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
local SessionService = require(script.Parent.SessionService)
local StressService = require(script.Parent.StressService)

export type Grant = {
	Score: number,
	Coins: number,
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

-- Returns what was granted, or nil if nothing was (already rewarded, or the
-- player's data isn't loaded).
function RewardService.grantDefeat(player: Player, state: BossState.BossState): Grant?
	local data = PlayerDataService.get(player)
	if data == nil or not BossState.markRewarded(state, player.UserId) then
		return nil
	end

	local definition = state.Definition
	local unlockedBefore = asSet(ProgressionRules.unlockedBossIds(data.BossDefeats))

	SessionService.addScore(player, definition.ScoreReward)
	SessionService.addCoins(player, definition.CoinReward)
	local stressRelieved = StressService.relieve(player, GameConfig.DefeatStressRelief)
	data.TotalBossesDefeated += 1
	data.BossDefeats[definition.Id] = (data.BossDefeats[definition.Id] or 0) + 1

	local newlyUnlocked: { string } = {}
	for _, bossId in ProgressionRules.unlockedBossIds(data.BossDefeats) do
		if not unlockedBefore[bossId] then
			table.insert(newlyUnlocked, bossId)
		end
	end

	ProgressService.sync(player)
	return {
		Score = definition.ScoreReward,
		Coins = definition.CoinReward,
		StressRelieved = stressRelieved,
		UnlockedBossIds = newlyUnlocked,
	}
end

return RewardService
