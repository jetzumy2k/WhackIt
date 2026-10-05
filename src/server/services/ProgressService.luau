--!strict
-- Sends each player a snapshot of their own progression (coins, hammers, boss
-- unlocks) for the UI. Display only: the server re-checks everything itself.
-- Called on load and after every change (RewardService, ShopService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)
local LevelRules = require(ReplicatedStorage.Shared.LevelRules)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressionRules = require(ReplicatedStorage.Shared.ProgressionRules)
local Types = require(ReplicatedStorage.Shared.Types)

local SyncRemote = ReplicatedStorage.Remotes.Profile.Sync

local ProgressService = {}

function ProgressService.snapshot(data: PlayerDataService.PlayerData): Types.ProfileSnapshot
	local ownedIds: { string } = {}
	for _, hammer in HammerConfig.List do
		if ProgressionRules.ownsHammer(hammer.Id, data.OwnedHammers) then
			table.insert(ownedIds, hammer.Id)
		end
	end
	return {
		Coins = data.Coins,
		OwnedHammerIds = ownedIds,
		EquippedHammerId = data.EquippedHammerId,
		BossDefeats = table.clone(data.BossDefeats),
		UnlockedBossIds = ProgressionRules.unlockedBossIds(
			data.BossDefeats,
			LevelRules.levelFor(data.Score)
		),
		ZenLevel = data.ZenLevel,
		Level = LevelRules.levelFor(data.Score),
	}
end

function ProgressService.sync(player: Player): ()
	local data = PlayerDataService.get(player)
	if data then
		SyncRemote:FireClient(player, ProgressService.snapshot(data))
	end
end

function ProgressService.init(): ()
	PlayerDataService.onLoaded(function(player: Player)
		ProgressService.sync(player)
	end)
end

return ProgressService
