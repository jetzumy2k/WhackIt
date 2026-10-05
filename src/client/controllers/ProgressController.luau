--!strict
-- Holds the latest Profile.Sync snapshot of the local player's progression
-- (coins, hammers, boss unlocks) for the UI. Display only: the server
-- re-checks every hit, purchase and equip itself.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProgressionRules =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ProgressionRules"))
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local ProgressController = {}

local snapshot: Types.ProfileSnapshot? = nil
local changedEvent = Instance.new("BindableEvent")

-- Fires whenever a new snapshot arrives.
ProgressController.Changed = changedEvent.Event

local function stringList(value: unknown): { string }?
	if typeof(value) ~= "table" then
		return nil
	end
	local list: { string } = {}
	for _, item in value :: { unknown } do
		if typeof(item) == "string" then
			table.insert(list, item)
		end
	end
	return list
end

local function parseBuffs(value: unknown): { [string]: { Percent: number, SecondsLeft: number } }
	local buffs: { [string]: { Percent: number, SecondsLeft: number } } = {}
	if typeof(value) == "table" then
		for kind, entry in value :: { [unknown]: unknown } do
			if typeof(kind) == "string" and typeof(entry) == "table" then
				local raw = entry :: { [string]: unknown }
				local percent, seconds = raw.Percent, raw.SecondsLeft
				if typeof(percent) == "number" and typeof(seconds) == "number" then
					buffs[kind] = { Percent = percent, SecondsLeft = seconds }
				end
			end
		end
	end
	return buffs
end

local function parseMystery(
	value: unknown
): { { Id: string, Damage: number, CritDamagePercent: number } }
	local list: { { Id: string, Damage: number, CritDamagePercent: number } } = {}
	if typeof(value) == "table" then
		for _, entry in value :: { unknown } do
			if typeof(entry) == "table" then
				local raw = entry :: { [string]: unknown }
				local id, damage, crit = raw.Id, raw.Damage, raw.CritDamagePercent
				if
					typeof(id) == "string"
					and typeof(damage) == "number"
					and typeof(crit) == "number"
				then
					table.insert(list, { Id = id, Damage = damage, CritDamagePercent = crit })
				end
			end
		end
	end
	return list
end

-- Server messages are still checked so a malformed one can't break the UI.
local function parse(payload: unknown): Types.ProfileSnapshot?
	if typeof(payload) ~= "table" then
		return nil
	end
	local data = payload :: { [string]: unknown }
	local owned = stringList(data.OwnedHammerIds)
	local unlocked = stringList(data.UnlockedBossIds)
	local coins, equipped, rawDefeats, zenLevel, level, xp =
		data.Coins, data.EquippedHammerId, data.BossDefeats, data.ZenLevel, data.Level, data.Xp
	if
		owned == nil
		or unlocked == nil
		or typeof(coins) ~= "number"
		or typeof(equipped) ~= "string"
		or typeof(zenLevel) ~= "number"
		or typeof(level) ~= "number"
		or typeof(xp) ~= "number"
	then
		return nil
	end

	local defeats: { [string]: number } = {}
	if typeof(rawDefeats) == "table" then
		for bossId, count in rawDefeats :: { [unknown]: unknown } do
			if typeof(bossId) == "string" and typeof(count) == "number" then
				defeats[bossId] = count
			end
		end
	end

	return {
		Coins = coins,
		OwnedHammerIds = owned,
		EquippedHammerId = equipped,
		BossDefeats = defeats,
		UnlockedBossIds = unlocked,
		ZenLevel = zenLevel,
		Level = level,
		Xp = xp,
		Buffs = parseBuffs(data.Buffs),
		MysteryHammers = parseMystery(data.MysteryHammers),
	}
end

function ProgressController.get(): Types.ProfileSnapshot?
	return snapshot
end

-- False until the first snapshot arrives, so nothing looks unlocked by mistake.
function ProgressController.isBossUnlocked(bossId: string): boolean
	local current = snapshot
	if current == nil then
		return false
	end
	return table.find(current.UnlockedBossIds, bossId) ~= nil
end

function ProgressController.unlockStatus(bossId: string): ProgressionRules.UnlockStatus?
	local current = snapshot
	return if current
		then ProgressionRules.unlockStatus(bossId, current.BossDefeats, current.Level)
		else nil
end

function ProgressController.ownsHammer(hammerId: string): boolean
	local current = snapshot
	return current ~= nil and table.find(current.OwnedHammerIds, hammerId) ~= nil
end

function ProgressController.start(): ()
	local remote =
		ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Profile"):WaitForChild("Sync")
	assert(remote:IsA("RemoteEvent"), "Profile.Sync must be a RemoteEvent")
	remote.OnClientEvent:Connect(function(payload: unknown)
		local parsed = parse(payload)
		if parsed then
			snapshot = parsed
			changedEvent:Fire()
		end
	end)
end

return ProgressController
