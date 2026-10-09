--!strict
--[[
	Admin events (docs/EVENTS.md): XP events, outdoor boss events, boss drop
	events and Hammer Shop sales, shared by every server.

	Storage: one DataStore key (AdminConfig.EventStoreName / EventKey) holds the
	running and scheduled events plus a short history. Changes go through
	UpdateAsync (two admins at once can't lose each other's events) and a
	MessagingService ping tells other servers to reload; a periodic reload
	covers missed pings, and a restarted server simply loads the key again.
	Saved data is validated on every load (Shared/EventRules.parseStore). In
	Studio without API access, changes apply to this server only.

	Timing: events start and end by their saved times (os.time, UTC), so no
	admin has to clean up. One loop per server re-checks at most every few
	seconds; it only sends anything when the set of active events changes.
	When an event starts or ends every player here gets a short notice
	(Events.Notice) and the new list (Events.State); event bosses spawn or
	vanish (BossService.setEventBosses). Restoring normal XP, prices and drops
	needs nothing: the effect queries below only look at active events.

	Effect queries (the only place gameplay asks about events):
	  xpMultiplier()   RewardService, boss XP
	  dropsFor(boss)   RewardService, extra drops for qualifying players
	  hammerPrice(id)  ShopService, the coin price charged right now
	AdminService checks admin rights and filters names before calling
	create() or stop(); nothing here trusts the client.
]]

local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local AdminConfig = require(ServerScriptService.Config.AdminConfig)
local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local BossService = require(script.Parent.BossService)
local CustomBossConfig = require(ReplicatedStorage.Config.CustomBossConfig)
local EventConfig = require(ReplicatedStorage.Config.EventConfig)
local EventRules = require(ReplicatedStorage.Shared.EventRules)
local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)

local EventRemotes = ReplicatedStorage.Remotes.Events

local EventService = {}

-- Longest wait between checks for an event starting or ending.
local CHECK_SECONDS = 5

local store: EventRules.Store = { Events = {}, History = {} }
local eventStore: DataStore? = nil
local changedCallbacks: { () -> () } = {}
local idRandom = Random.new()
-- Active events as of the last check, by id (for start / end notices).
local activeById: { [string]: EventRules.Record } = {}
local checkedOnce = false
local stateDirty = true

local function now(): number
	return os.time()
end

-- Events force-removed here whose removal couldn't be saved yet: this server
-- ignores them until a save goes through (forceRemove).
local suppressed: { [string]: boolean } = {}

local function liveActive(): { EventRules.Record }
	local active = EventRules.active(store.Events, now())
	if next(suppressed) == nil then
		return active
	end
	local kept: { EventRules.Record } = {}
	for _, record in active do
		if not suppressed[record.Id] then
			table.insert(kept, record)
		end
	end
	return kept
end

-- Egg hunts running now (PetService spawns their eggs).
function EventService.eggHunts(): { EventRules.EggHunt }
	return EventRules.eggHunts(liveActive())
end

-- Effects -------------------------------------------------------------------

-- Boss XP multiplier from events (1 = none). Highest active one wins.
function EventService.xpMultiplier(): number
	return EventRules.xpMultiplier(liveActive())
end

-- Event drops on offer for this defeated boss.
function EventService.dropsFor(definition: BossConfig.BossDefinition): { EventRules.Drop }
	local lookId = if definition.Event then definition.LookId else nil
	return EventRules.dropsFor(liveActive(), definition.Id, lookId)
end

-- Whole % off a hammer right now (0 = full price).
function EventService.discountPercent(hammerId: string): number
	return EventRules.discountPercent(liveActive(), hammerId)
end

-- Coins the Hammer Shop charges for a hammer right now.
function EventService.hammerPrice(hammerId: string): number
	local hammer = HammerConfig.ById[hammerId]
	if hammer == nil then
		return math.huge
	end
	return EventRules.discountedPrice(hammer.Price, EventService.discountPercent(hammerId))
end

-- Players --------------------------------------------------------------------

local function publicState(): { [string]: any }
	local events = {}
	for _, record in liveActive() do
		table.insert(events, EventRules.publicView(record))
	end
	return { Events = events }
end

local function sendState(player: Player): ()
	EventRemotes.State:FireClient(player, publicState())
end

local function notice(kind: string, record: EventRules.Record): ()
	print(string.format("[Event] %s %q (%s)", string.lower(kind), record.Name, record.Type))
	EventRemotes.Notice:FireAllClients({
		Kind = kind,
		Name = record.Name,
		Summary = EventRules.summary(record),
	})
end

-- Spawns the bosses of active BossSpawn events and removes the rest.
local function syncBosses(active: { EventRules.Record }): ()
	local size = CustomBossConfig.Size
	local wanted: { BossService.CustomSpawn } = {}
	for _, spawn in EventRules.bossSpawns(active, BossService.spawnPositions(true)) do
		local definition = EventRules.bossDefinition(spawn)
		if definition then
			table.insert(wanted, {
				Definition = definition,
				Spawn = table.freeze({
					BossId = spawn.Id,
					Position = spawn.Position,
					Size = size,
					FloorY = spawn.Position.Y - size.Y / 2,
				}),
				Signature = string.format("%s|%s", spawn.LookId, tostring(spawn.Position)),
				Respawns = true,
				Spent = false,
			})
		end
	end
	BossService.setEventBosses(wanted)
end

-- Compares the active events with the last check: notices for each change,
-- bosses re-synced and the list re-sent only when something changed. The
-- first check after the server starts sends no notices (nothing "started"
-- for players who join a server mid-event). Returns whether anything changed.
local function check(): boolean
	local active = liveActive()
	local nextById: { [string]: EventRules.Record } = {}
	for _, record in active do
		nextById[record.Id] = record
	end
	local changed = not checkedOnce or stateDirty
	for id, record in nextById do
		if activeById[id] == nil then
			changed = true
			if checkedOnce then
				notice("Started", record)
			end
		end
	end
	for id, record in activeById do
		if nextById[id] == nil then
			changed = true
			notice("Ended", record)
		end
	end
	activeById = nextById
	checkedOnce = true
	stateDirty = false
	if changed then
		syncBosses(active)
		EventRemotes.State:FireAllClients(publicState())
	end
	return changed
end

local function notifyChanged(): ()
	for _, callback in changedCallbacks do
		task.spawn(callback)
	end
end

-- Storage --------------------------------------------------------------------

local function apply(newStore: EventRules.Store): ()
	store = newStore
	stateDirty = true
	check()
	notifyChanged()
end

local function load(): ()
	local dataStore = eventStore
	if dataStore == nil then
		return
	end
	local ok, saved = pcall(function()
		return dataStore:GetAsync(AdminConfig.EventKey)
	end)
	if ok then
		apply(EventRules.parseStore(saved))
	else
		warn("[Event] couldn't load events, keeping current ones: " .. tostring(saved))
	end
end

local function copyStore(source: EventRules.Store): EventRules.Store
	return { Events = table.clone(source.Events), History = table.clone(source.History) }
end

-- Runs `change` on the saved events inside UpdateAsync (expired events are
-- moved to the history first). `change` returns the new store, or nil plus a
-- message to cancel. Yields. Returns (ok, message).
local function mutate(change: (EventRules.Store) -> (EventRules.Store?, string?)): (boolean, string)
	local cancelMessage: string? = nil
	local result: EventRules.Store? = nil
	local dataStore = eventStore
	local ok, err = false, "no DataStore"
	if dataStore then
		ok, err = pcall(function()
			dataStore:UpdateAsync(AdminConfig.EventKey, function(old: unknown)
				local parsed = EventRules.parseStore(old)
				EventRules.prune(parsed, now())
				local nextStore, message = change(parsed)
				cancelMessage = message
				result = nextStore
				return nextStore -- nil cancels the write
			end)
		end)
	end
	if not ok then
		if not RunService:IsStudio() then
			warn("[Event] save failed: " .. tostring(err))
			return false, "Saving failed. Try again in a moment."
		end
		-- Studio without API access: this server only, so events can be tried out.
		local localCopy = copyStore(store)
		EventRules.prune(localCopy, now())
		local nextStore, message = change(localCopy)
		if nextStore == nil then
			return false, message or "Nothing changed."
		end
		apply(nextStore)
		return true, "Saved for this server only (no DataStore access in Studio)."
	end
	local saved = result
	if saved == nil then
		return false, cancelMessage or "Nothing changed."
	end
	apply(saved)
	local published, publishErr = pcall(function()
		MessagingService:PublishAsync(AdminConfig.EventTopic, "changed")
	end)
	if not published then
		-- Other servers still pick it up on their next refresh.
		warn("[Event] couldn't notify other servers: " .. tostring(publishErr))
	end
	return true, "Saved for all servers."
end

local function newId(current: EventRules.Store): string
	local taken: { [string]: boolean } = {}
	for _, record in current.Events do
		taken[record.Id] = true
	end
	for _, entry in current.History do
		taken[entry.Id] = true
	end
	local id: string
	repeat
		id = string.format("ev%d_%d", now(), idRandom:NextInteger(1000, 9999))
	until not taken[id]
	return id
end

-- Admin actions --------------------------------------------------------------

-- `name` must already be text-filtered (when the admin typed one). Yields.
function EventService.create(admin: Player, spec: EventRules.Spec, name: string): (boolean, string)
	return mutate(function(current)
		if #current.Events >= EventConfig.MaxEvents then
			return nil,
				string.format(
					"At most %d events can be running or scheduled. Stop one first.",
					EventConfig.MaxEvents
				)
		end
		table.insert(current.Events, {
			Id = newId(current),
			Name = name,
			Type = spec.Type,
			StartTime = spec.StartTime,
			EndTime = spec.EndTime,
			Config = spec.Config,
			CreatedBy = admin.UserId,
			CreatedByName = admin.Name,
			CreatedAt = now(),
		})
		return current, nil
	end)
end

-- Ends a running event now, or cancels a scheduled one. Yields.
local function endEvent(admin: Player, eventId: string, removed: boolean): (boolean, string)
	return mutate(function(current)
		for index, record in current.Events do
			if record.Id == eventId then
				table.remove(current.Events, index)
				table.insert(
					current.History,
					1,
					EventRules.toHistory(record, now(), admin.Name, removed)
				)
				while #current.History > EventConfig.MaxHistory do
					table.remove(current.History)
				end
				return current, nil
			end
		end
		return nil, "That event has already ended."
	end)
end

-- Ends a running event now, or cancels a scheduled one. Yields.
function EventService.stop(admin: Player, eventId: string): (boolean, string)
	return endEvent(admin, eventId, false)
end

-- Like stop(), but if saving fails the event still stops in THIS server at
-- once (its bosses, eggs, drops, prices and XP go back to normal here) and
-- the admin is told to retry so other servers follow. Yields.
function EventService.forceRemove(admin: Player, eventId: string): (boolean, string)
	local ok, message = endEvent(admin, eventId, true)
	if ok then
		suppressed[eventId] = nil
		return true, message
	end
	if EventService.find(eventId) == nil or message == "That event has already ended." then
		return false, message
	end
	suppressed[eventId] = true
	stateDirty = true
	check()
	notifyChanged()
	return true,
		"Removed in this server, but saving failed: other servers still run it. Try Force remove again."
end

-- Starts a scheduled event now (keeps its end time). Yields.
function EventService.startNow(eventId: string): (boolean, string)
	return mutate(function(current)
		for _, record in current.Events do
			if record.Id == eventId then
				if record.StartTime <= now() then
					return nil, "That event is already running."
				end
				record.StartTime = now()
				return current, nil
			end
		end
		return nil, "That event has already ended."
	end)
end

-- Replaces an event's settings, name and times (keeps its id and creator).
-- `spec` and `name` are checked like a new event's. Yields.
function EventService.update(
	eventId: string,
	spec: EventRules.Spec,
	name: string
): (boolean, string)
	return mutate(function(current)
		for _, record in current.Events do
			if record.Id == eventId then
				record.Name = name
				record.Type = spec.Type
				record.Config = spec.Config
				-- A running event keeps its start; a scheduled one takes the new one.
				if record.StartTime > now() then
					record.StartTime = spec.StartTime
				end
				record.EndTime = spec.EndTime
				return current, nil
			end
		end
		return nil, "That event has already ended."
	end)
end

-- Deletes an ended event from the history. Yields.
function EventService.deleteHistory(eventId: string): (boolean, string)
	return mutate(function(current)
		for index, entry in current.History do
			if entry.Id == eventId then
				table.remove(current.History, index)
				return current, nil
			end
		end
		return nil, "That history entry is already gone."
	end)
end

function EventService.find(eventId: string): EventRules.Record?
	for _, record in store.Events do
		if record.Id == eventId then
			return record
		end
	end
	return nil
end

-- What the Admin panel shows: running and scheduled events, then the history
-- (events that ran out since the last save are listed there too).
function EventService.adminView(): { [string]: any }
	local time = now()
	local events = {}
	local history = {}
	for _, record in store.Events do
		if record.EndTime > time then
			table.insert(events, {
				Id = record.Id,
				Name = record.Name,
				Type = record.Type,
				StartTime = record.StartTime,
				EndTime = record.EndTime,
				Summary = EventRules.summary(record),
				CreatedByName = record.CreatedByName,
				Active = EventRules.isActive(record, time) and not suppressed[record.Id],
				Config = record.Config,
			})
		else
			table.insert(history, EventRules.toHistory(record, record.EndTime, nil))
		end
	end
	table.sort(events, function(a, b)
		return a.StartTime < b.StartTime
	end)
	for _, entry in store.History do
		table.insert(history, entry)
	end
	return { Events = events, History = history }
end

function EventService.onChanged(callback: () -> ()): ()
	table.insert(changedCallbacks, callback)
end

-- Lifecycle ------------------------------------------------------------------

function EventService.init(): ()
	local ok, dataStore = pcall(function()
		return DataStoreService:GetDataStore(AdminConfig.EventStoreName)
	end)
	if ok then
		eventStore = dataStore
	else
		warn("[Event] DataStore unavailable: " .. tostring(dataStore))
	end
	Players.PlayerAdded:Connect(sendState)
end

function EventService.start(): ()
	for _, player in Players:GetPlayers() do
		sendState(player)
	end
	load()
	check()
	local subscribed, err = pcall(function()
		MessagingService:SubscribeAsync(AdminConfig.EventTopic, function()
			load()
		end)
	end)
	if not subscribed then
		warn("[Event] cross-server updates unavailable, using periodic refresh: " .. tostring(err))
	end
	task.spawn(function()
		while true do
			task.wait(AdminConfig.EventRefreshSeconds)
			load()
		end
	end)
	while true do
		local untilChange = EventRules.secondsUntilChange(store.Events, now())
		task.wait(
			if untilChange then math.clamp(untilChange, 0.5, CHECK_SECONDS) else CHECK_SECONDS
		)
		if check() then
			-- Admins see "Scheduled" turn "Active", and ended events move to history.
			notifyChanged()
		end
	end
end

return EventService
