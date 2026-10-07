--!strict
--[[
	Grants boss-defeat rewards to every contributor (Lib/RewardRules):
	score and coins by damage share, a last-hit bonus, the Zen Level coin bonus,
	and, for players with at least MinRewardDamageShare, the stress bonus and a
	defeat count toward unlocking the next boss.

	XP is the score earned times GameConfig.XpRewardMultiplier and any XP boost.
	Admin-created (custom) bosses don't count toward unlocks.
	Each qualifying player may get a random 30-minute store boost in their Bag
	(Shared/CustomBossRules, Shared/BagRules): always from a custom boss, and
	from an office boss with a chance picked at random in the range in effect
	(DropRateService: Normal, or Lucky during the Lucky window).
	Players who hit this boss life with admin-set damage get nothing.

	Idempotent: BossState.markRewarded lets each player be rewarded at most once
	per boss life, no matter how often this is called.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BagRules = require(ReplicatedStorage.Shared.BagRules)
local BossState = require(ServerScriptService.Lib.BossState)
local BuffService = require(script.Parent.BuffService)
local CustomBossConfig = require(ReplicatedStorage.Config.CustomBossConfig)
local CustomBossRules = require(ReplicatedStorage.Shared.CustomBossRules)
local DropRateService = require(script.Parent.DropRateService)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local LevelRules = require(ReplicatedStorage.Shared.LevelRules)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)
local ProgressionRules = require(ReplicatedStorage.Shared.ProgressionRules)
local RewardRules = require(ServerScriptService.Lib.RewardRules)
local SessionService = require(script.Parent.SessionService)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)
local StressService = require(script.Parent.StressService)

local RewardService = {}

export type Grant = {
	Score: number,
	Coins: number,
	Share: number,
	Qualified: boolean,
	LastHit: boolean,
	StressRelieved: number,
	UnlockedBossIds: { string }, -- bosses this defeat newly unlocked
	BuffDrop: CustomBossRules.Drop?, -- the store boost this player got, if any
}

local KIND_TEXT: { [string]: string } = { Xp = "XP", Damage = "Damage", CritDamage = "Crit Damage" }
local DROP_OPTIONS = CustomBossRules.dropOptions(StoreConfig.Products)
local dropRandom = Random.new()

function RewardService.dropText(drop: CustomBossRules.Drop): string
	return string.format(
		"+%d%% %s boost (%d min), in your Bag",
		drop.Percent,
		KIND_TEXT[drop.Kind] or drop.Kind,
		CustomBossConfig.BuffDropSeconds // 60
	)
end

local function asSet(ids: { string }): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, id in ids do
		set[id] = true
	end
	return set
end

-- Returns what was granted, or nil if nothing was (already rewarded, data not
-- loaded, the player dealt no damage, or hit with admin-set damage).
function RewardService.grantDefeat(player: Player, state: BossState.BossState): Grant?
	local data = PlayerDataService.get(player)
	local damage = state.Contributions[player.UserId]
	if
		data == nil
		or damage == nil
		or damage <= 0
		or state.AdminBoosted[player.UserId]
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
	local unlockedBefore = asSet(
		ProgressionRules.unlockedBossIds(
			data.BossDefeats,
			LevelRules.levelFor(data.Xp),
			data.AdminUnlocks
		)
	)

	SessionService.addScore(player, reward.Score)
	-- XP follows score, boosted by any XP buff (Score itself stays unboosted).
	SessionService.addXp(
		player,
		reward.Score * GameConfig.XpRewardMultiplier * BuffService.xpMultiplier(player)
	)
	SessionService.addCoins(player, reward.Coins)

	local stressRelieved = 0
	local buffDrop: CustomBossRules.Drop? = nil
	if reward.Qualifies then
		data.TotalBossesDefeated += 1
		if not definition.Custom then
			data.BossDefeats[definition.Id] = (data.BossDefeats[definition.Id] or 0) + 1
		end
		local chance = DropRateService.chance(dropRandom:NextNumber())
		if RewardRules.dropsBuff(definition, dropRandom:NextNumber(), chance) then
			buffDrop = CustomBossRules.pickDrop(DROP_OPTIONS, dropRandom:NextNumber())
			if buffDrop then
				BagRules.add(data.Bag, buffDrop.Key, 1)
			end
		end
		-- Last, so a Zen moment it may trigger sees the updated coins.
		stressRelieved = StressService.relieve(player, GameConfig.DefeatStressRelief)
	end

	local newlyUnlocked: { string } = {}
	for _, bossId in
		ProgressionRules.unlockedBossIds(
			data.BossDefeats,
			LevelRules.levelFor(data.Xp),
			data.AdminUnlocks
		)
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
		BuffDrop = buffDrop,
	}
end

return RewardService
