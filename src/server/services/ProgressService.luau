--!strict
-- Sends each player a snapshot of their own progression (coins, hammers, boss
-- unlocks) for the UI. Display only: the server re-checks everything itself.
-- Called on load and after every change (RewardService, ShopService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)
local LevelRules = require(ReplicatedStorage.Shared.LevelRules)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressionRules = require(ReplicatedStorage.Shared.ProgressionRules)
local PetConfig = require(ReplicatedStorage.Config.PetConfig)
local QuestRules = require(ReplicatedStorage.Shared.QuestRules)
local Types = require(ReplicatedStorage.Shared.Types)

local SyncRemote = ReplicatedStorage.Remotes.Profile.Sync

local ProgressService = {}

-- Which incubator in this server shows a player's egg (PetService sets it;
-- 0 = none here, e.g. all busy). Kept here so the snapshot needs no require cycle.
local shownIncubator: { [number]: number? } = {}

function ProgressService.setIncubatorShown(userId: number, index: number?): ()
	shownIncubator[userId] = index
end

local function mysteryList(data: PlayerDataService.PlayerData): { Types.MysteryHammer }
	local list: { Types.MysteryHammer } = {}
	for hammerId, roll in data.MysteryHammers do
		table.insert(list, {
			Id = hammerId,
			Damage = roll.Damage,
			BonusDamagePercent = roll.BonusDamagePercent,
			CritDamagePercent = roll.CritDamagePercent,
		})
	end
	table.sort(list, function(a, b)
		return a.Id < b.Id
	end)
	return list
end

-- Owned pets for the UI: equipped first, then rarest, then oldest.
local function petList(data: PlayerDataService.PlayerData): { Types.OwnedPet }
	local list: { Types.OwnedPet } = {}
	for petId, pet in data.Pets do
		local buffs: { { Kind: string, Percent: number } } = {}
		for _, buff in pet.Buffs do
			local kind: string = buff.Kind
			table.insert(buffs, { Kind = kind, Percent = buff.Percent })
		end
		table.insert(
			list,
			{ Id = petId, Species = pet.Species, Rarity = pet.Rarity, Buffs = buffs }
		)
	end
	local function rank(pet: Types.OwnedPet): number
		local info = PetConfig.RarityInfo[pet.Rarity]
		return if info then info.Order else 0
	end
	table.sort(list, function(a, b)
		local aOn, bOn = a.Id == data.EquippedPetId, b.Id == data.EquippedPetId
		if aOn ~= bOn then
			return aOn
		end
		if rank(a) ~= rank(b) then
			return rank(a) > rank(b)
		end
		local aNumber = tonumber(string.sub(a.Id, 5)) or 0
		local bNumber = tonumber(string.sub(b.Id, 5)) or 0
		return aNumber < bNumber
	end)
	return list
end

local function adminUnlockList(data: PlayerDataService.PlayerData): { string }
	local list: { string } = {}
	for bossId in data.AdminUnlocks do
		table.insert(list, bossId)
	end
	table.sort(list)
	return list
end

-- `shownIndex`: the incubator in this server showing the player's egg (0 = none).
function ProgressService.snapshot(
	data: PlayerDataService.PlayerData,
	shownIndex: number?
): Types.ProfileSnapshot
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
			LevelRules.levelFor(data.Xp),
			data.AdminUnlocks
		),
		ZenLevel = data.ZenLevel,
		Level = LevelRules.levelFor(data.Xp),
		Xp = data.Xp,
		Buffs = table.clone(data.Buffs),
		MysteryHammers = mysteryList(data),
		AdminUnlocks = adminUnlockList(data),
		Bag = table.clone(data.Bag),
		Pets = petList(data),
		EquippedPetId = data.EquippedPetId,
		-- Only the egg's rarity and timing: what hatches stays on the server.
		Incubation = if data.Incubation
			then {
				Rarity = data.Incubation.Rarity,
				EndsAt = data.Incubation.EndsAt,
				IncubatorIndex = shownIndex or 0,
			}
			else nil,
		Settings = table.clone(data.Settings),
		Cosmetics = table.clone(data.Cosmetics),
		Furniture = table.clone(data.Furniture),
		OfficeLayout = table.clone(data.OfficeLayout),
		OfficePrivacy = data.OfficePrivacy,
		Recreation = {
			Rating = data.Recreation.Rating,
			SeasonId = data.Recreation.SeasonId,
			Wins = data.Recreation.Wins,
			Losses = data.Recreation.Losses,
			TotalWins = data.Recreation.TotalWins,
			TotalLosses = data.Recreation.TotalLosses,
			DayKey = data.Recreation.DayKey,
			DayMatches = data.Recreation.DayMatches,
			DayOpponents = table.clone(data.Recreation.DayOpponents),
		},
		Quests = QuestRules.copy(data.Quests),
		DailyEvent = table.clone(data.DailyEvent),
		Missions = table.clone(data.Missions),
		PetArena = {
			Cleared = data.PetArena.Cleared,
			DayWins = data.PetArena.DayWins,
			DayKey = data.PetArena.DayKey,
		},
		Capsule = table.clone(data.Capsule),
		PaperToss = { Cleared = data.PaperToss.Cleared, Best = data.PaperToss.Best },
	}
end

function ProgressService.sync(player: Player): ()
	local data = PlayerDataService.get(player)
	if data then
		SyncRemote:FireClient(player, ProgressService.snapshot(data, shownIncubator[player.UserId]))
	end
end

function ProgressService.init(): ()
	PlayerDataService.onLoaded(function(player: Player)
		ProgressService.sync(player)
	end)
end

return ProgressService
