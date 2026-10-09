--!strict
--[[
	Pure rules for admin events (docs/EVENTS.md): validating what the Admin
	panel sends, validating what comes back from the DataStore, deciding which
	events are active, and the effect queries the gameplay services ask. No
	Instances or services, so every path is unit-tested. EventService owns
	storage and timing; the client uses the same text helpers for display.

	Conflicts between events of the same kind are settled here, never by
	stacking:
	  * XP: the highest active multiplier applies (2x and 3x -> 3x, not 6x);
	  * Hammer Shop: each hammer gets the highest discount that covers it;
	  * drops: each active drop event rolls on its own (they name different
	    items or bosses), once per qualifying player per boss defeat;
	  * outdoor bosses: events share each location's slots, oldest first; a
	    slot already taken (or too close to another boss) is skipped.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BagRules = require(script.Parent.BagRules)
local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local EventConfig = require(ReplicatedStorage.Config.EventConfig)
local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)
local Validate = require(script.Parent.Validate)

export type EventType = "XpBoost" | "BossSpawn" | "BossDrop" | "StoreDiscount" | "EggHunt"

-- Settings for one event; which fields are set depends on its Type.
export type Config = {
	Multiplier: number?, -- XpBoost
	BossId: string?, -- BossSpawn (look to copy) / BossDrop (ALL_BOSSES or a boss id)
	LocationId: string?, -- BossSpawn
	Quantity: number?, -- BossSpawn
	ItemKey: string?, -- BossDrop (StoreConfig key)
	ChancePercent: number?, -- BossDrop (whole %)
	Percent: number?, -- StoreDiscount (whole % off)
	HammerIds: { string }?, -- StoreDiscount; empty = every hammer
	EggRarity: string?, -- EggHunt: "Common" | "Rare" | "Mythical"
	IntervalMinutes: number?, -- EggHunt
	MaxEggs: number?, -- EggHunt: most of the hunt's eggs out at once
}

-- An egg hunt running now (PetService spawns its eggs).
export type EggHunt = { EventId: string, Rarity: string, IntervalSeconds: number, MaxEggs: number }

-- One saved event, shared by every server.
export type Record = {
	Id: string,
	Name: string, -- already text-filtered for everyone
	Type: EventType,
	StartTime: number, -- unix seconds (UTC)
	EndTime: number,
	Config: Config,
	CreatedBy: number, -- admin UserId
	CreatedByName: string,
	CreatedAt: number,
}

-- An event that ended (expired or stopped), for the Admin panel's history.
export type HistoryEntry = {
	Id: string,
	Name: string,
	Type: EventType,
	StartTime: number,
	EndTime: number, -- when it actually ended
	Summary: string,
	CreatedByName: string,
	StoppedByName: string?, -- nil when it simply ran out
	-- "Completed" (ran its full time), "Stopped" (ended early), "Cancelled"
	-- (stopped before it started) or "Removed" (force-removed by an admin).
	Status: string?,
	PlannedEndTime: number?, -- when it was meant to end
}

export type Store = {
	Events: { Record },
	History: { HistoryEntry },
}

-- What an admin asks for (before the name is filtered and an id assigned).
export type Spec = {
	Type: EventType,
	Name: string, -- cleaned; a default name when the admin left it empty
	CustomName: boolean, -- the admin typed it (so it must be text-filtered)
	StartTime: number,
	EndTime: number,
	Config: Config,
}

-- A drop an event offers for one defeat.
export type Drop = { EventId: string, ItemKey: string, Chance: number }

-- An event boss to keep spawned.
export type BossSpawn = { Id: string, EventId: string, LookId: string, Position: Vector3 }

-- What clients see about an active event.
export type PublicEvent = {
	Id: string,
	Name: string,
	Type: EventType,
	StartTime: number,
	EndTime: number,
	Summary: string,
	Percent: number?, -- StoreDiscount
	HammerIds: { string }?, -- StoreDiscount
}

local EventRules = {}

EventRules.ALL_BOSSES = "*"

local MAX_ID_LENGTH = 40
local MAX_ADMIN_NAME_LENGTH = 64
local MAX_TIME = 2 ^ 40 -- far beyond any real date; keeps arithmetic exact

-- Whether `value` names an event type. Callers then bind it to an annotated
-- local (`local t: EventType = value :: EventType`): the type checker keeps
-- the exact type that way, where a refined optional would widen to string.
function EventRules.isType(value: unknown): boolean
	return value == "XpBoost"
		or value == "BossSpawn"
		or value == "BossDrop"
		or value == "StoreDiscount"
		or value == "EggHunt"
end

function EventRules.location(locationId: string): EventConfig.Location?
	for _, location in EventConfig.Locations do
		if location.Id == locationId then
			return location
		end
	end
	return nil
end

-- Trims spaces and collapses runs of whitespace (newlines included).
function EventRules.cleanName(raw: string): string
	local collapsed = string.gsub(raw, "%s+", " ")
	return (string.match(collapsed, "^%s*(.-)%s*$") or "")
end

-- "2X EXPERIENCE", "OUTDOOR BOSS EVENT", ...: used when no name was typed.
function EventRules.defaultName(eventType: EventType, config: Config): string
	if eventType == "XpBoost" then
		return string.format("%sX EXPERIENCE", tostring(config.Multiplier or 1))
	elseif eventType == "StoreDiscount" then
		return string.format("%d%% OFF HAMMERS", config.Percent or 0)
	elseif eventType == "EggHunt" then
		return string.format("%s EGG HUNT", string.upper(config.EggRarity or ""))
	end
	return string.upper(EventConfig.TypeInfo[eventType].Label)
end

local function hammerIds(raw: unknown): ({ string }?, string?)
	if raw == nil then
		return {}, nil
	end
	if typeof(raw) ~= "table" then
		return nil, "Pick the hammers on sale."
	end
	local ids: { string } = {}
	local seen: { [string]: boolean } = {}
	local count = 0
	for _, value in raw :: { [unknown]: unknown } do
		count += 1
		if count > #HammerConfig.List then
			return nil, "Too many hammers picked."
		end
		local id = Validate.id(value, 64)
		local hammer = if id then HammerConfig.ById[id] else nil
		if id == nil or hammer == nil or hammer.Price <= 0 then
			return nil, "Only hammers that cost coins can be on sale."
		end
		if not seen[id] then
			seen[id] = true
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids, nil
end

-- Validates the type-specific settings. Returns the clean copy, or nil and
-- a reason an admin can read.
function EventRules.parseConfig(eventType: EventType, raw: unknown): (Config?, string?)
	if typeof(raw) ~= "table" then
		return nil, "Missing event settings."
	end
	local data = raw :: { [string]: unknown }
	if eventType == "XpBoost" then
		local multiplier = Validate.number(data.Multiplier, 1, 100)
		if multiplier == nil or table.find(EventConfig.XpMultipliers, multiplier) == nil then
			return nil, "Pick an XP multiplier from the list."
		end
		return { Multiplier = multiplier }, nil
	elseif eventType == "BossSpawn" then
		local bossId = Validate.id(data.BossId, 64)
		if bossId == nil or table.find(EventConfig.BossLookIds, bossId) == nil then
			return nil, "Pick a boss from the list."
		end
		local locationId = Validate.id(data.LocationId, 64)
		local location = if locationId then EventRules.location(locationId) else nil
		if locationId == nil or location == nil then
			return nil, "Pick a location from the list."
		end
		local maxQuantity = math.min(EventConfig.MaxBossQuantity, #location.Slots)
		local quantity = Validate.integer(data.Quantity, 1, maxQuantity)
		if quantity == nil then
			return nil, string.format("Quantity must be 1 to %d.", maxQuantity)
		end
		return { BossId = bossId, LocationId = locationId, Quantity = quantity }, nil
	elseif eventType == "BossDrop" then
		local bossId: string
		if data.BossId == EventRules.ALL_BOSSES then
			bossId = EventRules.ALL_BOSSES
		else
			local id = Validate.id(data.BossId, 64)
			if id == nil or BossConfig.ById[id] == nil then
				return nil, "Pick all bosses or one boss from the list."
			end
			bossId = id
		end
		local itemKey = Validate.id(data.ItemKey, 64)
		if
			itemKey == nil
			or table.find(EventConfig.DropItems, itemKey) == nil
			or StoreConfig.ByKey[itemKey] == nil
		then
			return nil, "Pick a drop item from the list."
		end
		local chance = Validate.integer(
			data.ChancePercent,
			EventConfig.MinDropChancePercent,
			EventConfig.MaxDropChancePercent
		)
		if chance == nil then
			return nil,
				string.format(
					"Drop chance must be a whole number from %d to %d.",
					EventConfig.MinDropChancePercent,
					EventConfig.MaxDropChancePercent
				)
		end
		return { BossId = bossId, ItemKey = itemKey, ChancePercent = chance }, nil
	elseif eventType == "StoreDiscount" then
		local percent = Validate.integer(
			data.Percent,
			EventConfig.MinDiscountPercent,
			EventConfig.MaxDiscountPercent
		)
		if percent == nil then
			return nil,
				string.format(
					"Discount must be a whole number from %d to %d %%.",
					EventConfig.MinDiscountPercent,
					EventConfig.MaxDiscountPercent
				)
		end
		local ids, problem = hammerIds(data.HammerIds)
		if ids == nil then
			return nil, problem
		end
		return { Percent = percent, HammerIds = ids }, nil
	elseif eventType == "EggHunt" then
		local rarity = data.EggRarity
		if rarity ~= "Common" and rarity ~= "Rare" and rarity ~= "Mythical" then
			return nil, "Pick an egg tier."
		end
		local interval = Validate.integer(data.IntervalMinutes, 1, 1440)
		if interval == nil or table.find(EventConfig.EggHuntIntervals, interval) == nil then
			return nil, "Pick how often eggs appear."
		end
		local maxEggs = Validate.integer(data.MaxEggs, 1, EventConfig.MaxEggHuntEggs)
		if maxEggs == nil then
			return nil,
				string.format("Eggs out at once must be 1 to %d.", EventConfig.MaxEggHuntEggs)
		end
		return { EggRarity = rarity :: string, IntervalMinutes = interval, MaxEggs = maxEggs }, nil
	end
	return nil, "Unknown event type."
end

-- Validates an admin's request. `now` is the server's os.time().
function EventRules.parseSpec(raw: unknown, now: number): (Spec?, string?)
	if typeof(raw) ~= "table" then
		return nil, "bad request"
	end
	local data = raw :: { [string]: unknown }
	if not EventRules.isType(data.Type) then
		return nil, "Pick an event type."
	end
	local eventType: EventType = data.Type :: EventType

	local config, problem = EventRules.parseConfig(eventType, data.Config)
	if config == nil then
		return nil, problem
	end

	local startTime: number, endTime: number
	if data.DurationSeconds ~= nil then
		local seconds = Validate.integer(data.DurationSeconds, 1, EventConfig.MaxDurationSeconds)
		local known = false
		for _, duration in EventConfig.Durations do
			if duration.Seconds == seconds then
				known = true
			end
		end
		if seconds == nil or not known then
			return nil, "Pick a duration from the list."
		end
		startTime, endTime = now, now + seconds
	else
		local starts = Validate.integer(data.StartsAt, 0, MAX_TIME)
		local ends = Validate.integer(data.EndsAt, 0, MAX_TIME)
		if starts == nil or ends == nil then
			return nil, "Enter a start and an end time."
		end
		if starts < now - EventConfig.StartGraceSeconds then
			return nil, "The start time is in the past."
		end
		if starts > now + EventConfig.MaxStartAheadSeconds then
			return nil, "Events can be scheduled at most 90 days ahead."
		end
		if ends <= starts or ends <= now then
			return nil, "The end time must be after the start time."
		end
		if ends - starts > EventConfig.MaxDurationSeconds then
			return nil, "An event can last at most 14 days."
		end
		startTime, endTime = math.max(starts, now), ends
	end

	local typed = if data.Name == nil
		then ""
		else Validate.string(data.Name, EventConfig.NameMaxLength * 4)
	if typed == nil then
		return nil, string.format("Name must be at most %d characters.", EventConfig.NameMaxLength)
	end
	local name = EventRules.cleanName(typed)
	local length = utf8.len(name)
	if length == nil or length > EventConfig.NameMaxLength then
		return nil, string.format("Name must be at most %d characters.", EventConfig.NameMaxLength)
	end
	local custom = length > 0
	local spec: Spec = {
		Type = eventType,
		Name = if custom then name else EventRules.defaultName(eventType, config),
		CustomName = custom,
		StartTime = startTime,
		EndTime = endTime,
		Config = config,
	}
	return spec, nil
end

local function finite(value: unknown, min: number, max: number): number?
	return Validate.number(value, min, max)
end

-- Validates one saved event (the DataStore is not trusted either).
function EventRules.parseRecord(raw: unknown): Record?
	if typeof(raw) ~= "table" then
		return nil
	end
	local data = raw :: { [string]: unknown }
	local id = Validate.id(data.Id, MAX_ID_LENGTH)
	local name = Validate.string(data.Name, EventConfig.NameMaxLength * 4)
	if id == nil or name == nil or not EventRules.isType(data.Type) then
		return nil
	end
	local eventType: EventType = data.Type :: EventType
	local config = EventRules.parseConfig(eventType, data.Config)
	local startTime = finite(data.StartTime, 0, MAX_TIME)
	local endTime = finite(data.EndTime, 0, MAX_TIME)
	local createdBy = Validate.integer(data.CreatedBy, 0, 2 ^ 53)
	local createdByName = Validate.string(data.CreatedByName, MAX_ADMIN_NAME_LENGTH)
	local createdAt = finite(data.CreatedAt, 0, MAX_TIME)
	if
		config == nil
		or startTime == nil
		or endTime == nil
		or endTime <= startTime
		or createdBy == nil
		or createdByName == nil
		or createdAt == nil
	then
		return nil
	end
	local record: Record = {
		Id = id,
		Name = name,
		Type = eventType,
		StartTime = startTime,
		EndTime = endTime,
		Config = config,
		CreatedBy = createdBy,
		CreatedByName = createdByName,
		CreatedAt = createdAt,
	}
	return record
end

function EventRules.parseHistoryEntry(raw: unknown): HistoryEntry?
	if typeof(raw) ~= "table" then
		return nil
	end
	local data = raw :: { [string]: unknown }
	local id = Validate.id(data.Id, MAX_ID_LENGTH)
	local name = Validate.string(data.Name, EventConfig.NameMaxLength * 4)
	local startTime = finite(data.StartTime, 0, MAX_TIME)
	local endTime = finite(data.EndTime, 0, MAX_TIME)
	local summary = Validate.string(data.Summary, 200)
	local createdByName = Validate.string(data.CreatedByName, MAX_ADMIN_NAME_LENGTH)
	local stoppedByName = if data.StoppedByName == nil
		then nil
		else Validate.string(data.StoppedByName, MAX_ADMIN_NAME_LENGTH)
	local status = if data.Status == nil then nil else Validate.id(data.Status, 16)
	local plannedEnd = if data.PlannedEndTime == nil
		then nil
		else finite(data.PlannedEndTime, 0, MAX_TIME)
	if
		id == nil
		or name == nil
		or not EventRules.isType(data.Type)
		or startTime == nil
		or endTime == nil
		or summary == nil
		or createdByName == nil
		or (data.StoppedByName ~= nil and stoppedByName == nil)
	then
		return nil
	end
	local eventType: EventType = data.Type :: EventType
	local entry: HistoryEntry = {
		Id = id,
		Name = name,
		Type = eventType,
		StartTime = startTime,
		EndTime = endTime,
		Summary = summary,
		CreatedByName = createdByName,
		StoppedByName = stoppedByName,
		Status = status,
		PlannedEndTime = plannedEnd,
	}
	return entry
end

-- Validates the saved events: bad entries and duplicates dropped, lists bounded.
function EventRules.parseStore(raw: unknown): Store
	local store: Store = { Events = {}, History = {} }
	if typeof(raw) ~= "table" then
		return store
	end
	local data = raw :: { [string]: unknown }
	local seen: { [string]: boolean } = {}
	if typeof(data.Events) == "table" then
		for _, entry in data.Events :: { unknown } do
			local record = EventRules.parseRecord(entry)
			if record and not seen[record.Id] and #store.Events < EventConfig.MaxEvents then
				seen[record.Id] = true
				table.insert(store.Events, record)
			end
		end
	end
	if typeof(data.History) == "table" then
		for _, entry in data.History :: { unknown } do
			local item = EventRules.parseHistoryEntry(entry)
			if item and #store.History < EventConfig.MaxHistory then
				table.insert(store.History, item)
			end
		end
	end
	return store
end

-- Timing -----------------------------------------------------------------

function EventRules.isActive(record: Record, now: number): boolean
	return record.StartTime <= now and now < record.EndTime
end

-- Active events, oldest start first (ties by id), so every server agrees.
function EventRules.active(records: { Record }, now: number): { Record }
	local list: { Record } = {}
	for _, record in records do
		if EventRules.isActive(record, now) then
			table.insert(list, record)
		end
	end
	table.sort(list, function(a, b)
		if a.StartTime ~= b.StartTime then
			return a.StartTime < b.StartTime
		end
		return a.Id < b.Id
	end)
	return list
end

-- Seconds until the next event starts or ends, or nil if nothing is pending.
function EventRules.secondsUntilChange(records: { Record }, now: number): number?
	local soonest: number? = nil
	for _, record in records do
		for _, moment in { record.StartTime, record.EndTime } do
			if moment > now and (soonest == nil or moment < soonest) then
				soonest = moment
			end
		end
	end
	return if soonest then soonest - now else nil
end

-- A history line for an event that ended (stopped early when `stoppedByName`).
-- `removed` marks an admin's force-remove.
function EventRules.toHistory(
	record: Record,
	endedAt: number,
	stoppedByName: string?,
	removed: boolean?
): HistoryEntry
	local status = if removed
		then "Removed"
		elseif stoppedByName == nil then "Completed"
		elseif endedAt < record.StartTime then "Cancelled"
		else "Stopped"
	return {
		Id = record.Id,
		Name = record.Name,
		Type = record.Type,
		StartTime = record.StartTime,
		EndTime = math.min(record.EndTime, math.max(endedAt, record.StartTime)),
		Summary = EventRules.summary(record),
		CreatedByName = record.CreatedByName,
		StoppedByName = stoppedByName,
		Status = status,
		PlannedEndTime = record.EndTime,
	}
end

-- Egg hunts running now, oldest first.
function EventRules.eggHunts(active: { Record }): { EggHunt }
	local hunts: { EggHunt } = {}
	for _, record in active do
		local config = record.Config
		if
			record.Type == "EggHunt"
			and config.EggRarity
			and config.IntervalMinutes
			and config.MaxEggs
		then
			table.insert(hunts, {
				EventId = record.Id,
				Rarity = config.EggRarity,
				IntervalSeconds = config.IntervalMinutes * 60,
				MaxEggs = config.MaxEggs,
			})
		end
	end
	return hunts
end

-- Moves events that have run out into the history (newest first, bounded).
-- Returns true when anything moved.
function EventRules.prune(store: Store, now: number): boolean
	local kept: { Record } = {}
	local moved = false
	for _, record in store.Events do
		if record.EndTime <= now then
			table.insert(store.History, 1, EventRules.toHistory(record, record.EndTime, nil))
			moved = true
		else
			table.insert(kept, record)
		end
	end
	store.Events = kept
	while #store.History > EventConfig.MaxHistory do
		table.remove(store.History)
	end
	return moved
end

-- Effects ----------------------------------------------------------------

-- Multiplier for boss XP: the highest active XP event, or 1.
function EventRules.xpMultiplier(active: { Record }): number
	local best = 1
	for _, record in active do
		if record.Type == "XpBoost" then
			best = math.max(best, record.Config.Multiplier or 1)
		end
	end
	return best
end

-- Drops on offer for a defeated boss. `lookId` is the office boss an event
-- boss copies, so "Production Bug" drop events cover its outdoor copies too.
function EventRules.dropsFor(active: { Record }, bossId: string, lookId: string?): { Drop }
	local drops: { Drop } = {}
	for _, record in active do
		local config = record.Config
		if record.Type ~= "BossDrop" or config.ItemKey == nil or config.ChancePercent == nil then
			continue
		end
		local target = config.BossId
		if
			target == EventRules.ALL_BOSSES
			or target == bossId
			or (lookId ~= nil and target == lookId)
		then
			table.insert(drops, {
				EventId = record.Id,
				ItemKey = config.ItemKey,
				Chance = config.ChancePercent / 100,
			})
		end
	end
	return drops
end

-- The biggest active discount (whole %) on a hammer, or 0.
function EventRules.discountPercent(active: { Record }, hammerId: string): number
	local best = 0
	for _, record in active do
		local config = record.Config
		if record.Type == "StoreDiscount" and config.Percent then
			local ids = config.HammerIds
			if ids == nil or #ids == 0 or table.find(ids, hammerId) then
				best = math.max(best, config.Percent)
			end
		end
	end
	return best
end

-- Price after a discount: whole coins, never below 1 for a paid hammer, never
-- above the normal price, and free hammers stay free.
function EventRules.discountedPrice(price: number, percent: number): number
	if price <= 0 then
		return 0
	end
	local clamped = math.clamp(percent, 0, EventConfig.MaxDiscountPercent)
	return math.clamp(math.floor(price * (100 - clamped) / 100), 1, price)
end

-- Where event bosses stand right now. Events take free slots in their
-- location, oldest first; slots closer than MinBossSpacing to `blocked`
-- (office and custom bosses) or to an earlier event boss are skipped.
function EventRules.bossSpawns(active: { Record }, blocked: { Vector3 }): { BossSpawn }
	local spawns: { BossSpawn } = {}
	local taken: { Vector3 } = table.clone(blocked)
	for _, record in active do
		local config = record.Config
		if record.Type ~= "BossSpawn" or config.LocationId == nil or config.BossId == nil then
			continue
		end
		local location = EventRules.location(config.LocationId)
		if location == nil then
			continue
		end
		local placed = 0
		for _, slot in location.Slots do
			if placed >= (config.Quantity or 0) then
				break
			end
			local free = true
			for _, other in taken do
				if (other - slot).Magnitude < EventConfig.MinBossSpacing then
					free = false
					break
				end
			end
			if free then
				placed += 1
				table.insert(taken, slot)
				table.insert(spawns, {
					Id = string.format("%s%s_%d", EventConfig.BossIdPrefix, record.Id, placed),
					EventId = record.Id,
					LookId = config.BossId,
					Position = slot,
				})
			end
		end
	end
	return spawns
end

function EventRules.isEventBossId(bossId: string): boolean
	local prefix = EventConfig.BossIdPrefix
	return string.sub(bossId, 1, #prefix) == prefix
end

-- The fight an event boss offers: a copy of its office boss (health, damage
-- taken, score and coin rewards), open to everyone, marked as an event boss.
function EventRules.bossDefinition(spawn: BossSpawn): BossConfig.BossDefinition?
	local base = BossConfig.ById[spawn.LookId]
	if base == nil then
		return nil
	end
	return table.freeze({
		Id = spawn.Id,
		DisplayName = "🎉 " .. base.DisplayName .. " (Event)",
		Description = base.Description,
		MaxHealth = base.MaxHealth,
		DamageTakenMultiplier = base.DamageTakenMultiplier,
		ScoreReward = base.ScoreReward,
		CoinReward = base.CoinReward,
		UnlockDefeats = 0,
		Custom = true,
		Event = true,
		LookId = base.Id,
	})
end

-- Text -------------------------------------------------------------------

local function bossName(bossId: string?): string
	local boss = if bossId then BossConfig.ById[bossId] else nil
	return if boss then boss.DisplayName else "boss"
end

-- One line describing what the event does.
function EventRules.summary(record: { Type: EventType, Config: Config }): string
	local config = record.Config
	if record.Type == "XpBoost" then
		return string.format("%sx XP from bosses", tostring(config.Multiplier or 1))
	elseif record.Type == "BossSpawn" then
		local location = if config.LocationId then EventRules.location(config.LocationId) else nil
		return string.format(
			"%d x %s at %s",
			config.Quantity or 0,
			bossName(config.BossId),
			if location then location.Label else "outside"
		)
	elseif record.Type == "BossDrop" then
		local product = if config.ItemKey then StoreConfig.ByKey[config.ItemKey] else nil
		return string.format(
			"%d%% chance of %s from %s",
			config.ChancePercent or 0,
			if product then BagRules.itemText(product) else "an item",
			if config.BossId == EventRules.ALL_BOSSES then "every boss" else bossName(config.BossId)
		)
	elseif record.Type == "StoreDiscount" then
		local ids = config.HammerIds
		local count = if ids then #ids else 0
		return string.format(
			"%d%% off %s in the Hammer Shop",
			config.Percent or 0,
			if count == 0
				then "every hammer"
				elseif count == 1 then "1 hammer"
				else count .. " hammers"
		)
	elseif record.Type == "EggHunt" then
		return string.format(
			"A %s Egg outside every %d min (up to %d at once)",
			config.EggRarity or "?",
			config.IntervalMinutes or 0,
			config.MaxEggs or 0
		)
	end
	return ""
end

function EventRules.publicView(record: Record): PublicEvent
	local isDiscount = record.Type == "StoreDiscount"
	return {
		Id = record.Id,
		Name = record.Name,
		Type = record.Type,
		StartTime = record.StartTime,
		EndTime = record.EndTime,
		Summary = EventRules.summary(record),
		Percent = if isDiscount then record.Config.Percent else nil,
		HammerIds = if isDiscount then record.Config.HammerIds else nil,
	}
end

-- Client side: checks one event from Events.State so a malformed message
-- can't break the UI. Display only.
function EventRules.parsePublic(raw: unknown): PublicEvent?
	if typeof(raw) ~= "table" then
		return nil
	end
	local data = raw :: { [string]: unknown }
	local id = Validate.string(data.Id, MAX_ID_LENGTH)
	local name = Validate.string(data.Name, EventConfig.NameMaxLength * 4)
	local summary = Validate.string(data.Summary, 200)
	local startTime = finite(data.StartTime, 0, MAX_TIME)
	local endTime = finite(data.EndTime, 0, MAX_TIME)
	if
		id == nil
		or name == nil
		or summary == nil
		or startTime == nil
		or endTime == nil
		or not EventRules.isType(data.Type)
	then
		return nil
	end
	local percent = finite(data.Percent, 0, EventConfig.MaxDiscountPercent)
	local ids: { string }? = nil
	if typeof(data.HammerIds) == "table" then
		local list: { string } = {}
		for _, value in data.HammerIds :: { unknown } do
			if typeof(value) == "string" and #list < #HammerConfig.List then
				table.insert(list, value)
			end
		end
		ids = list
	end
	local eventType: EventType = data.Type :: EventType
	local event: PublicEvent = {
		Id = id,
		Name = name,
		Type = eventType,
		StartTime = startTime,
		EndTime = endTime,
		Summary = summary,
		Percent = percent,
		HammerIds = ids,
	}
	return event
end

-- Client side: the discount (whole %) the active public events give a hammer.
function EventRules.publicDiscount(events: { PublicEvent }, hammerId: string, now: number): number
	local best = 0
	for _, event in events do
		if
			event.Type == "StoreDiscount"
			and event.Percent
			and event.StartTime <= now
			and now < event.EndTime
		then
			local ids = event.HammerIds
			if ids == nil or #ids == 0 or table.find(ids, hammerId) then
				best = math.max(best, event.Percent)
			end
		end
	end
	return best
end

-- "1d 02:03:04", "01:24:32" or "00:45" (seconds left).
function EventRules.countdown(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	local days = total // 86400
	local hours, minutes, secs = (total % 86400) // 3600, (total % 3600) // 60, total % 60
	if days > 0 then
		return string.format("%dd %02d:%02d:%02d", days, hours, minutes, secs)
	end
	return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

return EventRules
