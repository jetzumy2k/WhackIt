--!strict
-- Holds the latest Profile.Sync snapshot of the local player's progression
-- (coins, hammers, boss unlocks) for the UI. Display only: the server
-- re-checks every hit, purchase and equip itself.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attributes"))
local CustomBossRules =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CustomBossRules"))
local FurnitureRules =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FurnitureRules"))
local PickleballRules =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PickleballRules"))
local QuestRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("QuestRules"))
local MissionRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MissionRules"))
local DailyEventRules =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DailyEventRules"))
local ProgressionRules =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ProgressionRules"))
local LevelRewardRules =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LevelRewardRules"))
local SettingsRules =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SettingsRules"))
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

local function parseMystery(value: unknown): { Types.MysteryHammer }
	local list: { Types.MysteryHammer } = {}
	if typeof(value) == "table" then
		for _, entry in value :: { unknown } do
			if typeof(entry) == "table" then
				local raw = entry :: { [string]: unknown }
				local id, damage, crit = raw.Id, raw.Damage, raw.CritDamagePercent
				local bonus = raw.BonusDamagePercent
				if
					typeof(id) == "string"
					and typeof(damage) == "number"
					and typeof(crit) == "number"
				then
					table.insert(list, {
						Id = id,
						Damage = damage,
						BonusDamagePercent = if typeof(bonus) == "number" then bonus else 0,
						CritDamagePercent = crit,
					})
				end
			end
		end
	end
	return list
end

local function parseBag(raw: unknown): { [string]: number }
	local bag: { [string]: number } = {}
	if typeof(raw) == "table" then
		for key, count in raw :: { [unknown]: unknown } do
			if typeof(key) == "string" and typeof(count) == "number" and count >= 1 then
				bag[key] = math.floor(count)
			end
		end
	end
	return bag
end

local function parsePets(raw: unknown): { Types.OwnedPet }
	local pets: { Types.OwnedPet } = {}
	if typeof(raw) ~= "table" then
		return pets
	end
	for _, entry in raw :: { unknown } do
		if typeof(entry) == "table" then
			local data = entry :: { [string]: unknown }
			local buffs: { { Kind: string, Percent: number } } = {}
			if typeof(data.Buffs) == "table" then
				for _, buff in data.Buffs :: { unknown } do
					if typeof(buff) == "table" then
						local kind = (buff :: { [string]: unknown }).Kind
						local percent = (buff :: { [string]: unknown }).Percent
						if typeof(kind) == "string" and typeof(percent) == "number" then
							table.insert(buffs, { Kind = kind, Percent = percent })
						end
					end
				end
			end
			if
				typeof(data.Id) == "string"
				and typeof(data.Species) == "string"
				and typeof(data.Rarity) == "string"
			then
				table.insert(pets, {
					Id = data.Id,
					Species = data.Species,
					Rarity = data.Rarity,
					Buffs = buffs,
				})
			end
		end
	end
	return pets
end

local function parseIncubation(raw: unknown): Types.IncubationView?
	if typeof(raw) ~= "table" then
		return nil
	end
	local data = raw :: { [string]: unknown }
	if
		typeof(data.Rarity) ~= "string"
		or typeof(data.EndsAt) ~= "number"
		or typeof(data.IncubatorIndex) ~= "number"
	then
		return nil
	end
	return { Rarity = data.Rarity, EndsAt = data.EndsAt, IncubatorIndex = data.IncubatorIndex }
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

	local furniture = FurnitureRules.sanitizeOwned(data.Furniture)
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
		AdminUnlocks = stringList(data.AdminUnlocks) or {},
		Bag = parseBag(data.Bag),
		Pets = parsePets(data.Pets),
		EquippedPetId = if typeof(data.EquippedPetId) == "string" then data.EquippedPetId else "",
		Incubation = parseIncubation(data.Incubation),
		Settings = SettingsRules.sanitize(data.Settings),
		Cosmetics = LevelRewardRules.sanitizeCosmetics(data.Cosmetics),
		Furniture = furniture,
		OfficeLayout = (FurnitureRules.parseLayout(data.OfficeLayout, furniture)),
		OfficePrivacy = if FurnitureRules.isPrivacy(data.OfficePrivacy)
			then data.OfficePrivacy :: string
			else "Public",
		Recreation = PickleballRules.sanitizeRecord(data.Recreation),
		Quests = QuestRules.sanitize(data.Quests),
		DailyEvent = DailyEventRules.sanitize(data.DailyEvent),
		Missions = MissionRules.sanitizeRecord(data.Missions),
	}
end

function ProgressController.get(): Types.ProfileSnapshot?
	return snapshot
end

-- False until the first snapshot arrives, so nothing looks unlocked by mistake.
-- Admin-created bosses are open to everyone.
-- The server turned on this admin's boss-access bypass (display only; the
-- server checks its own copy on every hit).
local function hasBypass(): boolean
	return Players.LocalPlayer:GetAttribute(Attributes.AdminBypass) == true
end

function ProgressController.isBossUnlocked(bossId: string): boolean
	local current = snapshot
	if current == nil then
		return false
	end
	if hasBypass() then
		return true
	end
	return CustomBossRules.isCustomId(bossId) or table.find(current.UnlockedBossIds, bossId) ~= nil
end

function ProgressController.unlockStatus(bossId: string): ProgressionRules.UnlockStatus?
	local current = snapshot
	if current == nil then
		return nil
	end
	if hasBypass() then
		return { Unlocked = true, PreviousBossId = nil, DefeatsNeeded = 0, LevelNeeded = 0 }
	end
	local adminUnlocks: { [string]: boolean } = {}
	for _, id in current.AdminUnlocks do
		adminUnlocks[id] = true
	end
	return ProgressionRules.unlockStatus(bossId, current.BossDefeats, current.Level, adminUnlocks)
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
	-- Doors and boss labels follow an admin's bypass at once.
	Players.LocalPlayer:GetAttributeChangedSignal(Attributes.AdminBypass):Connect(function()
		if snapshot then
			changedEvent:Fire()
		end
	end)
end

return ProgressController
