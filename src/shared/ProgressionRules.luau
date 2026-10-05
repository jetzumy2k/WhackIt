--!strict
--[[
	Pure progression rules: boss unlocks and the hammer shop. The server uses
	them to enforce; the client uses the same functions only to display what
	the server will allow.

	Bosses unlock in BossConfig.List order: boss N needs UnlockDefeats rewarded
	defeats of boss N - 1. The first boss is always unlocked.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)

export type BossDefeats = { [string]: number }
export type OwnedHammers = { [string]: boolean }

export type UnlockStatus = {
	Unlocked: boolean,
	PreviousBossId: string?, -- the boss to defeat to unlock this one
	DefeatsNeeded: number, -- remaining defeats of PreviousBossId (0 when unlocked)
}

export type PurchaseCheck = "Ok" | "UnknownHammer" | "AlreadyOwned" | "NotEnoughCoins"

local ProgressionRules = {}

local function indexOf(bossId: string): number?
	for index, boss in BossConfig.List do
		if boss.Id == bossId then
			return index
		end
	end
	return nil
end

function ProgressionRules.unlockStatus(bossId: string, defeats: BossDefeats): UnlockStatus
	local index = indexOf(bossId)
	if index == nil then
		return { Unlocked = false, PreviousBossId = nil, DefeatsNeeded = 0 }
	end
	if index == 1 then
		return { Unlocked = true, PreviousBossId = nil, DefeatsNeeded = 0 }
	end

	local previous = BossConfig.List[index - 1]
	local required = BossConfig.List[index].UnlockDefeats
	local done = defeats[previous.Id] or 0
	local needed = math.max(0, required - done)
	return { Unlocked = needed == 0, PreviousBossId = previous.Id, DefeatsNeeded = needed }
end

function ProgressionRules.isBossUnlocked(bossId: string, defeats: BossDefeats): boolean
	return ProgressionRules.unlockStatus(bossId, defeats).Unlocked
end

function ProgressionRules.unlockedBossIds(defeats: BossDefeats): { string }
	local ids: { string } = {}
	for _, boss in BossConfig.List do
		if ProgressionRules.isBossUnlocked(boss.Id, defeats) then
			table.insert(ids, boss.Id)
		end
	end
	return ids
end

function ProgressionRules.checkPurchase(
	hammerId: string,
	coins: number,
	owned: OwnedHammers
): PurchaseCheck
	local hammer = HammerConfig.ById[hammerId]
	if hammer == nil then
		return "UnknownHammer"
	end
	if ProgressionRules.ownsHammer(hammerId, owned) then
		return "AlreadyOwned"
	end
	if coins < hammer.Price then
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
