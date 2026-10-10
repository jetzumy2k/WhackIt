--!strict
--[[
	The pickleball season board and the top-10 season prizes
	(docs/PICKLEBALL.md "Rating and seasons", major update Phase 4b).

	* Writes: a player's season rating goes to the OrderedDataStore
	  RecRating_<seasonId> (keyed by UserId) once they've played
	  SeasonBoard.MinMatches rated matches that season. RecreationService
	  reports every rating change (noteRecord); a change is saved at most
	  every WriteInterval seconds, when the player leaves and at shutdown.
	  The value comes from saved data, never from a client.
	* Reads: the current season's top Size every ReadInterval seconds,
	  merged with the ranked players in this server (their live ratings),
	  sent to every client as Rec.Season { Kind = "Board" }. Clients can't
	  send anything here.
	* Prizes: a finished season's top list is frozen once, FreezeDelay after
	  the season ends (so every server has saved its last ratings), by the
	  first server that needs it: RecSeasons "Season_<id>", written with
	  UpdateAsync only if missing, so every server pays from the same list.
	  For each player here, the last ClaimSeasons finished seasons that are
	  not in their SeasonClaims are checked on join and every ReadInterval;
	  a ranked player gets the prize once (the season id goes into
	  SeasonClaims in the same step, and saved data is session-locked) and a
	  Rec.Season { Kind = "Prize" } card.
	* Without DataStore access (e.g. Studio with API access off) the board
	  ranks the players in this server and says so; no prizes are frozen or
	  paid.
	All DataStore calls are wrapped in pcall; failures keep the last values.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataConfig = require(ServerScriptService.Config.DataConfig)
local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)
local FurnitureRules = require(ReplicatedStorage.Shared.FurnitureRules)
local PickleballConfig = require(ReplicatedStorage.Config.PickleballConfig)
local PickleballRules = require(ReplicatedStorage.Shared.PickleballRules)
local PlayerDataSchema = require(ServerScriptService.Lib.PlayerDataSchema)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)
local SessionService = require(script.Parent.SessionService)

local SeasonRemote = ReplicatedStorage.Remotes.Rec.Season

local BOARD = PickleballConfig.SeasonBoard
-- How long a prize waits for the player's session (coins need it).
local SESSION_WAIT = 15
-- How long a shutdown waits for the last ratings to save.
local SHUTDOWN_WAIT = 8

type Entry = PickleballRules.BoardEntry
type Pending = { SeasonId: number, Rating: number }

local RecreationRankService = {}

local resultsStore: DataStore? = nil
local boardStores: { [number]: OrderedDataStore } = {}
-- Ratings still to save, by UserId; kept after the player leaves until saved.
local pending: { [number]: Pending } = {}
-- The last page read and the season it belongs to (-1 = none yet).
local page: { Entry } = {}
local pageSeason = -1
-- Finished seasons' frozen top lists, and seasons being loaded right now.
local frozen: { [number]: { Entry } } = {}
local loading: { [number]: boolean } = {}
local claiming: { [Player]: boolean } = {}
local nameCache: { [number]: string } = {}
local warned: { [string]: boolean } = {}
local lastBoard: { [string]: any }? = nil

-- Warn once per kind: without DataStore access every call fails the same way.
local function warnOnce(kind: string, message: string): ()
	if not warned[kind] then
		warned[kind] = true
		warn("[RecRank] " .. message)
	end
end

local function currentSeason(): number
	return PickleballRules.seasonId(os.time())
end

local function boardStore(seasonId: number): OrderedDataStore?
	local existing = boardStores[seasonId]
	if existing then
		return existing
	end
	local ok, store = pcall(function(): OrderedDataStore
		return DataStoreService:GetOrderedDataStore(DataConfig.RecRatingStorePrefix .. seasonId)
	end)
	if not ok then
		warnOnce("store", "season board store unavailable: " .. tostring(store))
		return nil
	end
	boardStores[seasonId] = store
	return store
end

-- The top `BOARD.Size` of a season's store, or nil if it can't be read.
local function readTop(seasonId: number): { Entry }?
	local store = boardStore(seasonId)
	if store == nil then
		return nil
	end
	local ok, items = pcall(function(): { { key: string, value: number } }
		return store:GetSortedAsync(false, BOARD.Size):GetCurrentPage()
	end)
	if not ok then
		warnOnce(
			"read",
			"couldn't read the season board, keeping the last one: " .. tostring(items)
		)
		return nil
	end
	local entries: { Entry } = {}
	for _, item in items do
		local userId = tonumber(item.key)
		if userId and typeof(item.value) == "number" then
			table.insert(entries, { UserId = userId, Rating = item.value })
		end
	end
	return PickleballRules.mergeBoard(entries, {}, BOARD.Size)
end

local function nameFor(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local here = Players:GetPlayerByUserId(userId)
	if here then
		nameCache[userId] = here.DisplayName
		return here.DisplayName
	end
	local ok, name = pcall(function(): string
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local resolved = if ok and typeof(name) == "string" then name else "Player " .. userId
	nameCache[userId] = resolved
	return resolved
end

-- Board -------------------------------------------------------------------------------

-- The ranked players here with their live ratings.
local function liveEntries(seasonId: number): { Entry }
	local entries: { Entry } = {}
	for _, player in Players:GetPlayers() do
		local data = PlayerDataService.get(player)
		if data and PickleballRules.isRanked(data.Recreation, seasonId) then
			table.insert(entries, { UserId = player.UserId, Rating = data.Recreation.Rating })
		end
	end
	return entries
end

local function broadcast(): ()
	local seasonId = currentSeason()
	local global = pageSeason == seasonId
	local top =
		PickleballRules.mergeBoard(if global then page else {}, liveEntries(seasonId), BOARD.Size)
	local rows = {}
	for _, entry in top do
		table.insert(
			rows,
			{ UserId = entry.UserId, Name = nameFor(entry.UserId), Rating = entry.Rating }
		)
	end
	local board = {
		Kind = "Board",
		SeasonId = seasonId,
		EndsAt = PickleballRules.seasonEnds(seasonId),
		Global = global,
		Top = rows,
	}
	lastBoard = board
	SeasonRemote:FireAllClients(board)
end

-- Changes within a moment are sent once.
local broadcastQueued = false
local function queueBroadcast(): ()
	if broadcastQueued then
		return
	end
	broadcastQueued = true
	task.delay(2, function()
		broadcastQueued = false
		broadcast()
	end)
end

-- Saving ratings ------------------------------------------------------------------------

local function flush(userId: number): ()
	local entry = pending[userId]
	if entry == nil then
		return
	end
	local store = boardStore(entry.SeasonId)
	if store == nil then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync(tostring(userId), math.max(0, math.floor(entry.Rating)))
	end)
	if not ok then
		warnOnce("write", "couldn't save a season rating: " .. tostring(err))
	elseif pending[userId] == entry then
		pending[userId] = nil
	end
end

-- Called by RecreationService after a rated result changed `record` (already
-- moved to the current season). Never yields.
function RecreationRankService.noteRecord(player: Player, record: PickleballRules.Record): ()
	if PickleballRules.isRanked(record, record.SeasonId) then
		pending[player.UserId] = { SeasonId = record.SeasonId, Rating = record.Rating }
	end
	queueBroadcast()
end

-- Season prizes ------------------------------------------------------------------------

-- Reads a finished season's frozen top list or, if no server froze it yet,
-- freezes the season's final board now (only if still missing).
local function loadOrFreeze(seasonId: number): { Entry }?
	local store = resultsStore
	if store == nil then
		return nil
	end
	local key = "Season_" .. seasonId
	local ok, raw = pcall(function(): unknown
		return store:GetAsync(key)
	end)
	if not ok then
		warnOnce("results", "couldn't read season results: " .. tostring(raw))
		return nil
	end
	if raw ~= nil then
		-- A broken record pays nobody rather than being read again and again.
		return PickleballRules.sanitizeResults(raw) or {}
	end
	local top = readTop(seasonId)
	if top == nil then
		return nil
	end
	local record = { SeasonId = seasonId, FrozenAt = os.time(), Top = top }
	local saved, result = pcall(function(): unknown
		return store:UpdateAsync(key, function(old: unknown): unknown
			-- Another server froze it first: keep theirs.
			return if old ~= nil then old else record
		end)
	end)
	if not saved then
		warnOnce("freeze", "couldn't save season results: " .. tostring(result))
		return nil
	end
	return PickleballRules.sanitizeResults(result) or {}
end

local function resultsFor(seasonId: number): { Entry }?
	while loading[seasonId] do
		task.wait(0.5)
	end
	local cached = frozen[seasonId]
	if cached then
		return cached
	end
	loading[seasonId] = true
	local ok, result = pcall(loadOrFreeze, seasonId)
	loading[seasonId] = nil
	if ok and result then
		frozen[seasonId] = result
		return result
	end
	return nil
end

local function waitForSession(player: Player): boolean
	local deadline = os.clock() + SESSION_WAIT
	while SessionService.get(player) == nil do
		if os.clock() > deadline or player.Parent == nil then
			return false
		end
		task.wait(0.5)
	end
	return true
end

local function grant(
	player: Player,
	seasonId: number,
	rank: number,
	prize: PickleballConfig.SeasonPrize
): ()
	-- Re-read after every yield: the player may have left, or claimed it.
	local data = PlayerDataService.get(player)
	if data == nil or player.Parent == nil or table.find(data.SeasonClaims, seasonId) then
		return
	end
	table.insert(data.SeasonClaims, seasonId)
	while #data.SeasonClaims > PlayerDataSchema.MAX_SEASON_CLAIMS do
		table.remove(data.SeasonClaims, 1)
	end
	SessionService.addCoins(player, prize.Coins)
	local itemName = ""
	if FurnitureRules.grantSpecial(data.Furniture, prize.Item, 1) then
		local info = FurnitureConfig.ByKey[prize.Item]
		itemName = if info then info.Name else prize.Item
	end
	ProgressService.sync(player)
	SeasonRemote:FireClient(player, {
		Kind = "Prize",
		SeasonId = seasonId,
		Rank = rank,
		Coins = prize.Coins,
		Item = itemName,
	})
end

local function claimPrizes(player: Player): ()
	if resultsStore == nil or claiming[player] then
		return
	end
	claiming[player] = true
	local ok, err = pcall(function(): nil
		local data = PlayerDataService.get(player)
		if data == nil then
			return nil
		end
		for _, seasonId in PickleballRules.claimableSeasons(data.SeasonClaims, os.time()) do
			local results = resultsFor(seasonId)
			local rank = if results then PickleballRules.rankOn(results, player.UserId) else nil
			local prize = if rank then PickleballRules.seasonPrize(rank) else nil
			if rank and prize and waitForSession(player) then
				grant(player, seasonId, rank, prize)
			end
		end
		return nil
	end)
	claiming[player] = nil
	if not ok then
		warn("[RecRank] prize check failed: " .. tostring(err))
	end
end

-- Lifecycle ----------------------------------------------------------------------------

function RecreationRankService.init(): ()
	local ok, store = pcall(function(): DataStore
		return DataStoreService:GetDataStore(DataConfig.RecSeasonsStoreName)
	end)
	if ok then
		resultsStore = store
	else
		warnOnce("results", "season results store unavailable: " .. tostring(store))
	end

	Players.PlayerAdded:Connect(function(player: Player)
		local board = lastBoard
		if board then
			SeasonRemote:FireClient(player, board)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		claiming[player] = nil
		-- Deferred: a forfeit by leaving is recorded in PlayerDataService's
		-- beforeRelease callbacks, which may run after this handler.
		local userId = player.UserId
		task.delay(1, flush, userId)
		queueBroadcast()
	end)
	PlayerDataService.onLoaded(function(player: Player)
		queueBroadcast()
		claimPrizes(player)
	end)
	game:BindToClose(function()
		for userId in pending do
			task.spawn(flush, userId)
		end
		local deadline = os.clock() + SHUTDOWN_WAIT
		while next(pending) ~= nil and os.clock() < deadline do
			task.wait(0.25)
		end
	end)
end

function RecreationRankService.start(): ()
	task.spawn(function()
		while true do
			local seasonId = currentSeason()
			local top = readTop(seasonId)
			if top then
				page, pageSeason = top, seasonId
			end
			broadcast()
			-- A season that ended while players were here pays them too.
			for _, player in Players:GetPlayers() do
				task.spawn(claimPrizes, player)
			end
			task.wait(BOARD.ReadInterval)
		end
	end)
	while true do
		task.wait(BOARD.WriteInterval)
		for userId in pending do
			task.spawn(flush, userId)
		end
	end
end

return RecreationRankService
