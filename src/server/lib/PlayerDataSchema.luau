--!strict
--[[
	Saved player data: shape, defaults, migrations and validation. Pure (no
	DataStore), so every path is unit-tested; PlayerDataService applies it to
	each loaded profile before the game uses it. See docs/DATA_SCHEMA.md.

	Loaded data is never trusted: an older bug, a manual DataStore edit or a
	newer server version could have written anything. prepare() upgrades old
	versions, fills missing fields, repairs invalid values in place, and refuses
	data written by a NEWER schema rather than risk misreading it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BagRules = require(ReplicatedStorage.Shared.BagRules)
local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local CapsuleRules = require(ReplicatedStorage.Shared.CapsuleRules)
local ContestRules = require(ReplicatedStorage.Shared.ContestRules)
local DailyEventRules = require(ReplicatedStorage.Shared.DailyEventRules)
local FurnitureRules = require(ReplicatedStorage.Shared.FurnitureRules)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)
local HammerRules = require(ReplicatedStorage.Shared.HammerRules)
local LevelRewardRules = require(ReplicatedStorage.Shared.LevelRewardRules)
local LevelRules = require(ReplicatedStorage.Shared.LevelRules)
local MissionRules = require(ReplicatedStorage.Shared.MissionRules)
local OfficeConfig = require(ReplicatedStorage.Config.OfficeConfig)
local PaperTossRules = require(ReplicatedStorage.Shared.PaperTossRules)
local PetArenaRules = require(ReplicatedStorage.Shared.PetArenaRules)
local PetConfig = require(ReplicatedStorage.Config.PetConfig)
local PetRules = require(ReplicatedStorage.Shared.PetRules)
local PickleballConfig = require(ReplicatedStorage.Config.PickleballConfig)
local PickleballRules = require(ReplicatedStorage.Shared.PickleballRules)
local ProgressionRules = require(ReplicatedStorage.Shared.ProgressionRules)
local QuestRules = require(ReplicatedStorage.Shared.QuestRules)
local SettingsRules = require(ReplicatedStorage.Shared.SettingsRules)
local ShowcaseRules = require(ReplicatedStorage.Shared.ShowcaseRules)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)

export type PlayerData = {
	SchemaVersion: number,
	Score: number,
	Stress: number,
	TotalHits: number,
	TotalBossesDefeated: number,
	EquippedHammerId: string,
	-- v2
	Coins: number,
	OwnedHammers: { [string]: boolean }, -- bought hammers (free ones are always owned)
	BossDefeats: { [string]: number }, -- rewarded defeats per boss id; drives unlocks
	-- v3
	ZenLevel: number, -- times the player reached Zen (0 stress); boosts boss coins
	ZenArmed: boolean, -- next Zen pays out; re-armed when stress climbs back up
	-- v4
	Xp: number, -- drives Player Level; boosted by XP buffs (Score stays unboosted)
	Buffs: { [string]: { Percent: number, SecondsLeft: number } }, -- "Xp" | "Damage" | "CritDamage"
	ProcessedPurchases: { string }, -- recent Robux PurchaseIds, so a receipt is granted once
	-- "mystery_<n>" -> rolled stats (Shared/HammerRules); BonusDamagePercent since v7.
	MysteryHammers: { [string]: HammerRules.MysteryRoll },
	NextMysteryNumber: number,
	-- v5
	AdminUnlocks: { [string]: boolean }, -- bosses an admin unlocked for this player
	-- v6
	Bag: { [string]: number }, -- unused store items by product key (Shared/BagRules)
	ClaimedGifts: { string }, -- recent GiftIds already put in the Bag, so a gift lands once
	-- The gift the player is buying right now (set before the purchase prompt).
	PendingGift: PendingGift?,
	-- v8 (docs/PETS.md)
	Pets: { [string]: PetRules.Pet }, -- "pet_<n>" -> species, rarity, buffs (fixed at hatch)
	NextPetNumber: number,
	EquippedPetId: string, -- "" = no pet out
	Incubation: PetRules.Incubation?, -- the egg incubating now, with what will hatch
	-- v9 (docs/UI.md "Settings")
	Settings: SettingsRules.Settings, -- on/off player settings (Config/SettingsConfig)
	-- v10 (docs/GAMEPLAY_RULES.md "Level rewards")
	LevelRewardsClaimed: number, -- highest level whose level-up coins were paid
	Cosmetics: LevelRewardRules.Cosmetics, -- picked trail and Zen glow ("" = default)
	-- v11 (docs/OFFICES.md)
	Furniture: FurnitureRules.Owned, -- Special furniture owned (Basic items are unlimited)
	OfficeLayout: FurnitureRules.Layout, -- placed furniture, room-local
	NextOfficeItemId: number, -- next layout entry id (never reused)
	OfficePrivacy: string, -- "Public" | "Friends" | "Private"
	-- v12 (docs/PICKLEBALL.md)
	Recreation: PickleballRules.Record, -- rating, wins/losses, today's reward caps
	ProcessedMatches: { string }, -- recent rewarded match ids, so a match pays once
	SeasonClaims: { number }, -- seasons whose prizes were handed out
	-- v13 (docs/QUESTS.md)
	Quests: QuestRules.State, -- today's and this week's quests, the tutorial step
	-- v14 (docs/DAILY_EVENTS.md)
	DailyEvent: DailyEventRules.State, -- today's Event of the Day points and tiers paid
	-- v15 (docs/MISSIONS.md)
	Missions: MissionRules.Record, -- today's rewarded team missions, missions cleared
	-- v16 (docs/SHOWCASE.md)
	Showcase: ShowcaseRules.State, -- last publish, offices liked and hidden
	-- v17 (docs/CONTESTS.md)
	Contest: ContestRules.State, -- weeks entered, prizes paid, this week's votes
	-- v18 (docs/PET_ARENA.md)
	PetArena: PetArenaRules.Record, -- trainers beaten, today's rewarded battles
	-- v19 (docs/CAPSULE.md)
	Capsule: CapsuleRules.State, -- today's Lucky Capsule spins
	-- v20 (docs/PAPER_TOSS.md)
	PaperToss: PaperTossRules.Record, -- opponents beaten, best score, today's wins
}

export type PendingGift = {
	RecipientUserId: number,
	ProductKey: string,
}

-- Raw saved table before validation.
export type RawData = { [string]: unknown }

-- Upgrades data from version (n - 1) to version n, in place.
export type Migration = (data: RawData) -> ()

local PlayerDataSchema = {}

PlayerDataSchema.CURRENT_VERSION = 20

-- Upper bound for counters; far beyond legitimate play, small enough to stay
-- an exact integer and to keep leaderboard values sane.
local MAX_COUNTER = 2 ^ 50

-- MIGRATIONS[n] upgrades version n - 1 to n. Data saved before versioning
-- existed has no SchemaVersion and counts as version 0.
PlayerDataSchema.MIGRATIONS = table.freeze({
	[1] = function(data: RawData)
		-- v0 -> v1: first versioned schema; fields are filled by prepare().
		data.SchemaVersion = 1
	end,
	[2] = function(data: RawData)
		-- v1 -> v2: coins, hammer ownership and per-boss defeats. Only the
		-- Deadline Boss existed in v1, so its defeats carry over and keep the
		-- player's unlock progress.
		data.Coins = 0
		data.OwnedHammers = {}
		local defeated = data.TotalBossesDefeated
		data.BossDefeats =
			{ [BossConfig.List[1].Id] = if typeof(defeated) == "number" then defeated else 0 }
	end,
	[3] = function(data: RawData)
		-- v2 -> v3: Zen. Everyone starts at level 0 with their first Zen armed.
		data.ZenLevel = 0
		data.ZenArmed = true
	end,
	[4] = function(data: RawData)
		-- v3 -> v4: store. Level now comes from XP; everyone keeps their level
		-- because XP starts equal to their lifetime Score.
		local score = data.Score
		data.Xp = if typeof(score) == "number" then score else 0
		data.Buffs = {}
		data.ProcessedPurchases = {}
		data.MysteryHammers = {}
		data.NextMysteryNumber = 1
	end,
	[5] = function(data: RawData)
		-- v4 -> v5: admin panel. Nobody has admin-unlocked bosses yet.
		data.AdminUnlocks = {}
	end,
	[6] = function(data: RawData)
		-- v5 -> v6: Bag and gifts. Everything bought before was already used.
		data.Bag = {}
		data.ClaimedGifts = {}
	end,
	[7] = function(data: RawData)
		-- v6 -> v7: Mystery Hammers get fixed base damage plus a damage bonus.
		-- Hammers opened before (20-35 damage) keep their crit roll, move to
		-- the base damage and get LegacyBonusDamagePercent; sanitize() then
		-- clamps everything. The version bump also stops older servers, which
		-- would drop the new field, from loading (and saving over) this data.
		local hammers = data.MysteryHammers
		if typeof(hammers) ~= "table" then
			return
		end
		for _, entry in hammers :: { [unknown]: unknown } do
			if typeof(entry) == "table" then
				local roll = entry :: { [string]: unknown }
				if roll.BonusDamagePercent == nil then
					roll.BonusDamagePercent = StoreConfig.Mystery.LegacyBonusDamagePercent
				end
			end
		end
	end,
	[8] = function(data: RawData)
		-- v7 -> v8: pets. Nobody has pets or an egg incubating yet.
		data.Pets = {}
		data.NextPetNumber = 1
		data.EquippedPetId = ""
		data.Incubation = nil
	end,
	[9] = function(data: RawData)
		-- v8 -> v9: player settings. Everyone starts from the defaults
		-- (sanitize() fills them in).
		data.Settings = {}
	end,
	[10] = function(data: RawData)
		-- v9 -> v10: the steeper level curve and level rewards (2026-10-09).
		-- Nobody loses a level: XP is raised to the new curve's threshold for
		-- the level the old curve gave (capped at MaxLevel). Levels already
		-- reached count as rewarded, so the change pays no back-dated coins.
		local xp = data.Xp
		local oldXp = if typeof(xp) == "number" and xp == xp and xp > 0 then xp else 0
		local keptLevel = math.min(LevelRules.legacyLevelFor(oldXp), LevelRules.MAX_LEVEL)
		data.Xp = math.max(oldXp, LevelRules.scoreForLevel(keptLevel))
		data.LevelRewardsClaimed = keptLevel
		data.Cosmetics = {}
	end,
	[11] = function(data: RawData)
		-- v10 -> v11: personal offices. Everyone gets the starting furniture
		-- (sanitize() fills in the default layout when none is saved).
		data.Furniture = {}
		data.OfficeLayout = nil
		data.NextOfficeItemId = nil
		data.OfficePrivacy = OfficeConfig.DefaultPrivacy
	end,
	[12] = function(data: RawData)
		-- v11 -> v12: pickleball. Everyone starts unrated (sanitize() fills in
		-- the starting record) with no matches played or prizes claimed.
		data.Recreation = nil
		data.ProcessedMatches = {}
		data.SeasonClaims = {}
	end,
	[13] = function(data: RawData)
		-- v12 -> v13: quests. Everyone starts the tutorial chain; daily and
		-- weekly quests are drawn on first use (QuestService).
		data.Quests = nil
	end,
	[14] = function(data: RawData)
		-- v13 -> v14: the Event of the Day. Nobody has points yet.
		data.DailyEvent = nil
	end,
	[15] = function(data: RawData)
		-- v14 -> v15: team missions. Nobody has played one yet.
		data.Missions = nil
	end,
	[16] = function(data: RawData)
		-- v15 -> v16: the Office Showcase. Nothing published, liked or hidden yet.
		data.Showcase = nil
	end,
	[17] = function(data: RawData)
		-- v16 -> v17: design contests. Nothing entered, voted or paid yet.
		data.Contest = nil
	end,
	[18] = function(data: RawData)
		-- v17 -> v18: the Pet Arena. No battles yet.
		data.PetArena = nil
	end,
	[19] = function(data: RawData)
		-- v18 -> v19: the Lucky Capsule Machine. No spins yet.
		data.Capsule = nil
	end,
	[20] = function(data: RawData)
		-- v19 -> v20: Paper Toss Showdown. No games yet.
		data.PaperToss = nil
	end,
}) :: { [number]: Migration }

-- Most recent purchase ids remembered for duplicate-receipt protection. Roblox
-- retries an unacknowledged receipt soon after, so a bounded history is enough.
PlayerDataSchema.MAX_PROCESSED_PURCHASES = 200
-- Same idea for claimed gifts: an inbox entry is removed right after it's claimed.
PlayerDataSchema.MAX_CLAIMED_GIFTS = 200
-- Season prize claims kept (newest last); older seasons are long settled.
PlayerDataSchema.MAX_SEASON_CLAIMS = 24
local BUFF_KINDS = { "Xp", "Damage", "CritDamage" }

function PlayerDataSchema.template(): PlayerData
	return {
		SchemaVersion = PlayerDataSchema.CURRENT_VERSION,
		Score = GameConfig.StartingScore,
		Stress = GameConfig.StartingStress,
		TotalHits = 0,
		TotalBossesDefeated = 0,
		EquippedHammerId = GameConfig.DefaultHammerId,
		Coins = GameConfig.StartingCoins,
		OwnedHammers = {},
		BossDefeats = {},
		ZenLevel = 0,
		ZenArmed = true,
		Xp = 0,
		Buffs = {},
		ProcessedPurchases = {},
		MysteryHammers = {},
		NextMysteryNumber = 1,
		AdminUnlocks = {},
		Bag = {},
		ClaimedGifts = {},
		PendingGift = nil,
		Pets = {},
		NextPetNumber = 1,
		EquippedPetId = "",
		Incubation = nil,
		Settings = SettingsRules.defaults(),
		LevelRewardsClaimed = 1,
		Cosmetics = { Trail = "", Glow = "", Office = "" },
		Furniture = {},
		OfficeLayout = FurnitureRules.defaultLayout(),
		NextOfficeItemId = #FurnitureRules.defaultLayout() + 1,
		OfficePrivacy = OfficeConfig.DefaultPrivacy,
		Recreation = PickleballRules.defaultRecord(0),
		ProcessedMatches = {},
		SeasonClaims = {},
		Quests = QuestRules.default(),
		DailyEvent = DailyEventRules.default(),
		Missions = MissionRules.defaultRecord(),
		Showcase = ShowcaseRules.defaultState(),
		Contest = ContestRules.defaultState(),
		PetArena = PetArenaRules.defaultRecord(),
		Capsule = CapsuleRules.defaultState(),
		PaperToss = PaperTossRules.defaultRecord(),
	}
end

local function isFiniteNumber(value: unknown): boolean
	return typeof(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

local function counter(value: unknown, fallback: number): number
	if not isFiniteNumber(value) then
		return fallback
	end
	return math.clamp(math.floor(value :: number), 0, MAX_COUNTER)
end

-- Runs migrations from the stored version up to `targetVersion`.
-- Returns false (and changes nothing) for data newer than `targetVersion`.
function PlayerDataSchema.migrate(
	data: RawData,
	migrations: { [number]: Migration },
	targetVersion: number
): (boolean, string?)
	local version = data.SchemaVersion
	local current = if isFiniteNumber(version) then math.floor(version :: number) else 0
	if current > targetVersion then
		return false,
			string.format("data schema v%d is newer than this server's v%d", current, targetVersion)
	end
	for nextVersion = current + 1, targetVersion do
		local migration = migrations[nextVersion]
		if migration == nil then
			return false, string.format("no migration to schema v%d", nextVersion)
		end
		migration(data)
		data.SchemaVersion = nextVersion
	end
	return true, nil
end

-- Fills missing fields and repairs invalid values in place.
function PlayerDataSchema.sanitize(data: RawData): ()
	local defaults = PlayerDataSchema.template()

	data.Score = counter(data.Score, defaults.Score)
	data.TotalHits = counter(data.TotalHits, defaults.TotalHits)
	data.TotalBossesDefeated = counter(data.TotalBossesDefeated, defaults.TotalBossesDefeated)

	local stress = data.Stress
	data.Stress = if isFiniteNumber(stress)
		then math.clamp(stress :: number, 0, GameConfig.MaxStress)
		else defaults.Stress

	data.Coins = counter(data.Coins, defaults.Coins)

	-- Rebuilt from scratch: only known hammers, only `true`.
	local owned: { [string]: boolean } = {}
	local rawOwned = data.OwnedHammers
	if typeof(rawOwned) == "table" then
		for hammerId, value in rawOwned :: { [unknown]: unknown } do
			if typeof(hammerId) == "string" and HammerConfig.ById[hammerId] and value == true then
				owned[hammerId] = true
			end
		end
	end
	data.OwnedHammers = owned

	-- Rebuilt from scratch: only known bosses, valid counters.
	local defeats: { [string]: number } = {}
	local rawDefeats = data.BossDefeats
	if typeof(rawDefeats) == "table" then
		for bossId, value in rawDefeats :: { [unknown]: unknown } do
			if typeof(bossId) == "string" and BossConfig.ById[bossId] then
				local count = counter(value, 0)
				if count > 0 then
					defeats[bossId] = count
				end
			end
		end
	end
	data.BossDefeats = defeats

	-- Rebuilt from scratch: only known bosses, only `true`.
	local adminUnlocks: { [string]: boolean } = {}
	local rawUnlocks = data.AdminUnlocks
	if typeof(rawUnlocks) == "table" then
		for bossId, value in rawUnlocks :: { [unknown]: unknown } do
			if typeof(bossId) == "string" and BossConfig.ById[bossId] and value == true then
				adminUnlocks[bossId] = true
			end
		end
	end
	data.AdminUnlocks = adminUnlocks

	data.Bag = BagRules.sanitize(data.Bag)

	-- Claimed gift ids: strings only, newest last, bounded.
	local claimed: { string } = {}
	local rawClaimed = data.ClaimedGifts
	if typeof(rawClaimed) == "table" then
		for _, id in rawClaimed :: { unknown } do
			if typeof(id) == "string" and #id > 0 and #id <= 128 then
				table.insert(claimed, id)
			end
		end
	end
	while #claimed > PlayerDataSchema.MAX_CLAIMED_GIFTS do
		table.remove(claimed, 1)
	end
	data.ClaimedGifts = claimed

	-- A pending gift must name a real, giftable product and a real user.
	local pending = data.PendingGift
	if typeof(pending) == "table" then
		local raw = pending :: { [string]: unknown }
		local key, recipient = raw.ProductKey, raw.RecipientUserId
		local product = if typeof(key) == "string" then StoreConfig.ByKey[key] else nil
		local valid = product ~= nil
			and BagRules.isGiftable(product)
			and isFiniteNumber(recipient)
			and (recipient :: number) >= 1
			and (recipient :: number) % 1 == 0
		data.PendingGift = if valid then { RecipientUserId = recipient, ProductKey = key } else nil
	else
		data.PendingGift = nil
	end

	data.ZenLevel = counter(data.ZenLevel, defaults.ZenLevel)
	if typeof(data.ZenArmed) ~= "boolean" then
		data.ZenArmed = defaults.ZenArmed
	end

	data.Xp = counter(data.Xp, defaults.Xp)
	data.NextMysteryNumber =
		math.max(1, counter(data.NextMysteryNumber, defaults.NextMysteryNumber))

	-- Buffs: known kinds only; percent and time clamped to sane ranges.
	local buffs: { [string]: { Percent: number, SecondsLeft: number } } = {}
	local rawBuffs = data.Buffs
	if typeof(rawBuffs) == "table" then
		for _, kind in BUFF_KINDS do
			local entry = (rawBuffs :: { [string]: unknown })[kind]
			if typeof(entry) == "table" then
				local raw = entry :: { [string]: unknown }
				local percent, seconds = raw.Percent, raw.SecondsLeft
				if
					isFiniteNumber(percent)
					and isFiniteNumber(seconds)
					and (seconds :: number) > 0
				then
					buffs[kind] = {
						Percent = math.clamp(percent :: number, 0, 100),
						SecondsLeft = math.min(seconds :: number, StoreConfig.MaxBuffSeconds),
					}
				end
			end
		end
	end
	data.Buffs = buffs

	-- Purchase history: strings only, newest last, bounded.
	local purchases: { string } = {}
	local rawPurchases = data.ProcessedPurchases
	if typeof(rawPurchases) == "table" then
		for _, id in rawPurchases :: { unknown } do
			if typeof(id) == "string" and #id > 0 and #id <= 128 then
				table.insert(purchases, id)
			end
		end
	end
	while #purchases > PlayerDataSchema.MAX_PROCESSED_PURCHASES do
		table.remove(purchases, 1)
	end
	data.ProcessedPurchases = purchases

	-- Mystery Hammers were paid for: keep every valid id, clamping odd stats
	-- back into range rather than deleting a purchase.
	local mystery: { [string]: HammerRules.MysteryRoll } = {}
	local rawMystery = data.MysteryHammers
	if typeof(rawMystery) == "table" then
		for hammerId, entry in rawMystery :: { [unknown]: unknown } do
			if
				typeof(hammerId) == "string"
				and HammerRules.isMysteryId(hammerId)
				and typeof(entry) == "table"
			then
				local raw = entry :: { [string]: unknown }
				local damage, crit, bonus =
					raw.Damage, raw.CritDamagePercent, raw.BonusDamagePercent
				if isFiniteNumber(damage) and isFiniteNumber(crit) then
					mystery[hammerId] = HammerRules.clampRoll({
						Damage = damage :: number,
						-- Missing or broken -> the legacy bonus (HammerRules.clampRoll).
						BonusDamagePercent = if isFiniteNumber(bonus) then bonus :: number else nil,
						CritDamagePercent = crit :: number,
					})
				end
			end
		end
	end
	data.MysteryHammers = mystery

	-- Pets are the player's: every valid one is kept, buffs clamped (never
	-- rerolled). The equipped one must be owned.
	local pets: { [string]: PetRules.Pet } = {}
	local rawPets = data.Pets
	local petCount = 0
	if typeof(rawPets) == "table" then
		for petId, entry in rawPets :: { [unknown]: unknown } do
			if typeof(petId) == "string" and PetRules.isPetId(petId) then
				local pet = PetRules.parsePet(entry)
				if pet and petCount < PetConfig.MaxPets * 2 then
					pets[petId] = pet
					petCount += 1
				end
			end
		end
	end
	data.Pets = pets
	data.NextPetNumber = math.max(1, counter(data.NextPetNumber, defaults.NextPetNumber))
	-- Never hand out an id that is already used.
	for petId in pets do
		local number = tonumber(string.sub(petId, 5)) or 0
		if number >= (data.NextPetNumber :: number) then
			data.NextPetNumber = number + 1
		end
	end
	local equippedPet = data.EquippedPetId
	data.EquippedPetId = if typeof(equippedPet) == "string" and pets[equippedPet]
		then equippedPet
		else ""

	-- A broken incubation gives its egg back rather than losing it.
	if data.Incubation ~= nil then
		local incubation = PetRules.parseIncubation(data.Incubation)
		if incubation == nil then
			local rawIncubation = data.Incubation
			local eggKey = if typeof(rawIncubation) == "table"
				then (rawIncubation :: { [string]: unknown }).EggKey
				else nil
			if typeof(eggKey) == "string" and PetRules.eggRarity(eggKey) then
				BagRules.add(data.Bag :: BagRules.Bag, eggKey, 1)
			end
		end
		data.Incubation = incubation
	end

	-- Known settings default when missing or broken; unknown ones are kept.
	data.Settings = SettingsRules.sanitize(data.Settings)

	-- Level rewards: at most MaxLevel claimed; picks must be known ids.
	data.LevelRewardsClaimed =
		math.clamp(counter(data.LevelRewardsClaimed, 1), 1, LevelRules.MAX_LEVEL)
	data.Cosmetics = LevelRewardRules.sanitizeCosmetics(data.Cosmetics)
	-- Office: owned Special furniture, then the layout checked against it
	-- (bad entries dropped, the rest kept as placed). No saved layout at all
	-- means a new office: it gets the starting furniture.
	local ownedFurniture = FurnitureRules.sanitizeOwned(data.Furniture)
	data.Furniture = ownedFurniture
	local layout, nextId
	if data.OfficeLayout == nil then
		layout = FurnitureRules.defaultLayout()
		nextId = #layout + 1
	else
		layout, nextId = FurnitureRules.parseLayout(data.OfficeLayout, ownedFurniture)
	end
	data.OfficeLayout = layout
	-- Ids are never reused, even for removed furniture.
	data.NextOfficeItemId = math.max(nextId, counter(data.NextOfficeItemId, 1))
	if not FurnitureRules.isPrivacy(data.OfficePrivacy) then
		data.OfficePrivacy = OfficeConfig.DefaultPrivacy
	end

	-- Pickleball: the record repaired field by field (a new season's reset
	-- happens when it's used, RecreationService), match ids and season
	-- claims bounded, newest last.
	data.Recreation = PickleballRules.sanitizeRecord(data.Recreation)
	-- Quests: unknown ids dropped, progress clamped; a broken day or week is
	-- drawn again (QuestService).
	data.Quests = QuestRules.sanitize(data.Quests)
	-- Event of the Day: a broken day starts over (tiers already paid are kept
	-- only for the saved day, so nothing pays twice).
	data.DailyEvent = DailyEventRules.sanitize(data.DailyEvent)
	data.Missions = MissionRules.sanitizeRecord(data.Missions)
	data.Showcase = ShowcaseRules.sanitizeState(data.Showcase)
	data.Contest = ContestRules.sanitizeState(data.Contest)
	data.PetArena = PetArenaRules.sanitizeRecord(data.PetArena)
	data.Capsule = CapsuleRules.sanitizeState(data.Capsule)
	data.PaperToss = PaperTossRules.sanitizeRecord(data.PaperToss)
	local matches: { string } = {}
	local rawMatches = data.ProcessedMatches
	if typeof(rawMatches) == "table" then
		for _, id in rawMatches :: { unknown } do
			if typeof(id) == "string" and #id > 0 and #id <= 64 then
				table.insert(matches, id)
			end
		end
	end
	while #matches > PickleballConfig.MaxProcessedMatches do
		table.remove(matches, 1)
	end
	data.ProcessedMatches = matches
	local claims: { number } = {}
	local rawClaims = data.SeasonClaims
	if typeof(rawClaims) == "table" then
		for _, id in rawClaims :: { unknown } do
			if isFiniteNumber(id) and (id :: number) >= 0 and (id :: number) % 1 == 0 then
				table.insert(claims, id :: number)
			end
		end
	end
	while #claims > PlayerDataSchema.MAX_SEASON_CLAIMS do
		table.remove(claims, 1)
	end
	data.SeasonClaims = claims

	-- Must be a hammer the player actually owns.
	local hammerId = data.EquippedHammerId
	local ownsIt = typeof(hammerId) == "string"
		and (ProgressionRules.ownsHammer(hammerId, owned) or mystery[hammerId] ~= nil)
	if not ownsIt then
		data.EquippedHammerId = defaults.EquippedHammerId
	end
end

-- Migrate, then sanitize. On success the table matches PlayerData exactly
-- (extra keys from future versions are left untouched).
function PlayerDataSchema.prepare(data: RawData): (boolean, string?)
	local ok, reason = PlayerDataSchema.migrate(
		data,
		PlayerDataSchema.MIGRATIONS,
		PlayerDataSchema.CURRENT_VERSION
	)
	if not ok then
		return false, reason
	end
	PlayerDataSchema.sanitize(data)
	return true, nil
end

return PlayerDataSchema
