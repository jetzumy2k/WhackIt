--!strict
--[[
	Pure progression rules: boss unlocks and the hammer shop. The server uses
	them to enforce; the client uses the same functions only to display what
	the server will allow.

	A boss unlocks when ALL that apply hold (BossConfig):
	  * UnlockAfterBossId set    -> at least UnlockDefeats rewarded defeats of it;
	  * UnlockAfterAllBosses set -> every other boss defeated at least once;
	  * MinLevel set             -> Player Level (Shared/LevelRules) >= MinLevel.
	Bosses with none of these are always unlocked, and so are:
	  * bosses an admin unlocked for this player (`adminUnlocks`, saved data);
	  * admin-created custom bosses (Shared/CustomBossRules).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local CustomBossRules = require(script.Parent.CustomBossRules)
local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)

export type BossDefeats = { [string]: number }
export type OwnedHammers = { [string]: boolean }
-- Boss ids an admin unlocked for a player (PlayerData.AdminUnlocks).
export type AdminUnlocks = { [string]: boolean }

export type UnlockStatus = {
	Unlocked: boolean,
	PreviousBossId: string?, -- the boss to defeat to unlock this one
	DefeatsNeeded: number, -- remaining defeats needed (of PreviousBossId, or bosses not yet beaten)
	LevelNeeded: number, -- Player Level required, or 0 when already met
}

export type PurchaseCheck = "Ok" | "UnknownHammer" | "AlreadyOwned" | "NotEnoughCoins"

local ProgressionRules = {}

local OPEN: UnlockStatus =
	table.freeze({ Unlocked = true, PreviousBossId = nil, DefeatsNeeded = 0, LevelNeeded = 0 })

function ProgressionRules.unlockStatus(
	bossId: string,
	defeats: BossDefeats,
	level: number,
	adminUnlocks: AdminUnlocks?
): UnlockStatus
	if CustomBossRules.isCustomId(bossId) then
		return OPEN
	end
	local boss = BossConfig.ById[bossId]
	if boss == nil then
		return { Unlocked = false, PreviousBossId = nil, DefeatsNeeded = 0, LevelNeeded = 0 }
	end
	if adminUnlocks and adminUnlocks[bossId] == true then
		return OPEN
	end

	local defeatsNeeded = 0
	local previousId = boss.UnlockAfterBossId
	if previousId then
		defeatsNeeded = math.max(0, boss.UnlockDefeats - (defeats[previousId] or 0))
	end
	if boss.UnlockAfterAllBosses then
		-- One defeat still needed for each other boss never beaten.
		for _, other in BossConfig.List do
			if other.Id ~= boss.Id and (defeats[other.Id] or 0) < 1 then
				defeatsNeeded += 1
			end
		end
	end
	local minLevel = boss.MinLevel
	local levelNeeded = if minLevel and level < minLevel then minLevel else 0

	return {
		Unlocked = defeatsNeeded == 0 and levelNeeded == 0,
		PreviousBossId = previousId,
		DefeatsNeeded = defeatsNeeded,
		LevelNeeded = levelNeeded,
	}
end

function ProgressionRules.isBossUnlocked(
	bossId: string,
	defeats: BossDefeats,
	level: number,
	adminUnlocks: AdminUnlocks?
): boolean
	return ProgressionRules.unlockStatus(bossId, defeats, level, adminUnlocks).Unlocked
end

-- BossConfig bosses only (custom bosses are always open and come and go).
function ProgressionRules.unlockedBossIds(
	defeats: BossDefeats,
	level: number,
	adminUnlocks: AdminUnlocks?
): { string }
	local ids: { string } = {}
	for _, boss in BossConfig.List do
		if ProgressionRules.isBossUnlocked(boss.Id, defeats, level, adminUnlocks) then
			table.insert(ids, boss.Id)
		end
	end
	return ids
end

-- `price` is what the server charges right now (a Hammer Shop sale event
-- may lower it, Shared/EventRules); the hammer's normal price when omitted.
function ProgressionRules.checkPurchase(
	hammerId: string,
	coins: number,
	owned: OwnedHammers,
	price: number?
): PurchaseCheck
	local hammer = HammerConfig.ById[hammerId]
	if hammer == nil then
		return "UnknownHammer"
	end
	if ProgressionRules.ownsHammer(hammerId, owned) then
		return "AlreadyOwned"
	end
	if coins < (price or hammer.Price) then
		return "NotEnoughCoins"
	end
	return "Ok"
end

-- Free hammers (Price 0) are owned by everyone.
function ProgressionRules.ownsHammer(hammerId: string, owned: OwnedHammers): boolean
	local hammer = HammerConfig.ById[hammerId]
	return hammer ~= nil and (hammer.Price == 0 or owned[hammerId] == true)
end

return ProgressionRules
