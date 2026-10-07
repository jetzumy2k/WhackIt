--!strict
--[[
	Global all-time leaderboard (docs/DATA_SCHEMA.md "Leaderboard store",
	docs/GAMEPLAY_RULES.md "Global leaderboard").

	* Writes: each player's lifetime Score, XP and current Coins go to three
	  OrderedDataStores (ScoreLeaderboard, XpLeaderboard, CoinsLeaderboard)
	  every LeaderboardWriteInterval seconds (each only when it changed) and
	  when they leave. Values come from the server's saved data, never from the
	  client.
	* Reads: the top LeaderboardSize of each store every LeaderboardReadInterval
	  seconds. The pages are merged with the live values of players in this
	  server (Lib/LeaderboardRules) into one snapshot: a top list per tab plus
	  everyone here (for "Your Rank"). Players joining or leaving re-send the
	  snapshot from the cached pages, without new DataStore calls.
	* The snapshot goes to every client (Leaderboard.Snapshot, server -> client
	  only); each client draws the board on the lobby's west wall
	  (LeaderboardController) and picks its own tab. Clients can't send
	  anything here, so they can never change a ranking.
	* Without DataStore access (e.g. Studio with API access off) the tabs rank
	  the players in this server instead and say so.
	All DataStore calls are wrapped in pcall; failures keep the last pages.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local DataConfig = require(ServerScriptService.Config.DataConfig)
local LeaderboardRules = require(ServerScriptService.Lib.LeaderboardRules)
local PlayerDataService = require(script.Parent.PlayerDataService)

local SnapshotRemote = ReplicatedStorage.Remotes.Leaderboard.Snapshot

local LeaderboardService = {}

-- Board on the lobby's west wall (x = -36), facing into the lobby (+X).
-- Bigger than before (was 13 x 10) so it reads from across the lobby.
LeaderboardService.BOARD_NAME = "LeaderboardBoard"
local BOARD_CENTER = Vector3.new(-35.2, 8.5, 17)
local BOARD_SIZE = Vector3.new(0.4, 12, 18)
local FRAME_COLOR = Color3.fromRGB(200, 160, 70) -- brushed gold trim
local PANEL_COLOR = Color3.fromRGB(28, 32, 50)

local STORE_NAMES: { [string]: string } = {
	Score = DataConfig.LeaderboardStoreName,
	Xp = DataConfig.XpLeaderboardStoreName,
	Coins = DataConfig.CoinsLeaderboardStoreName,
}

local stores: { [string]: OrderedDataStore } = {}
local globalOnline = false
-- Last top page read per stat (kept on failures).
local pages: { [string]: { LeaderboardRules.PageItem } } = {}
local lastWritten: { [Player]: { [string]: number } } = {}
local nameCache: { [number]: string } = {}
-- Warn once per kind: without DataStore access every call fails the same way.
local warned: { [string]: boolean } = {}

local function warnOnce(kind: string, message: string): ()
	if not warned[kind] then
		warned[kind] = true
		warn("[Leaderboard] " .. message)
	end
end

export type Snapshot = {
	Global: boolean,
	Note: string,
	Tabs: { [string]: { LeaderboardRules.Row } },
	Online: { LeaderboardRules.Row },
}

local function buildBoard(): ()
	-- One Model, always streamed to every client so the board never vanishes.
	local model = Instance.new("Model")
	model.Name = "LeaderboardArea"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	local frame = Instance.new("Part")
	frame.Name = "LeaderboardFrame"
	frame.Anchored = true
	frame.Size = BOARD_SIZE + Vector3.new(0.2, 0.8, 0.8)
	frame.Position = BOARD_CENTER - Vector3.new(0.15, 0, 0)
	frame.Color = FRAME_COLOR
	frame.Material = Enum.Material.Metal
	frame.Parent = model

	local board = Instance.new("Part")
	board.Name = LeaderboardService.BOARD_NAME
	board.Anchored = true
	board.Size = BOARD_SIZE
	board.Position = BOARD_CENTER
	board.Color = PANEL_COLOR
	board.Material = Enum.Material.SmoothPlastic
	board.Parent = model

	-- A small plaque under the board.
	local plaque = Instance.new("Part")
	plaque.Name = "LeaderboardPlaque"
	plaque.Anchored = true
	plaque.Size = Vector3.new(0.3, 0.9, 7)
	plaque.Position = BOARD_CENTER + Vector3.new(0.1, -BOARD_SIZE.Y / 2 - 0.9, 0)
	plaque.Color = FRAME_COLOR
	plaque.Material = Enum.Material.Metal
	plaque.Parent = model
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Right
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.3
	gui.Parent = plaque
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(40, 30, 20)
	text.Text = "Whack It Out! Stress Relief Dept. - Hall of Calm"
	text.Parent = gui

	model.PrimaryPart = board
	model.Parent = Workspace
end

local function nameFor(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local inServer = Players:GetPlayerByUserId(userId)
	if inServer then
		nameCache[userId] = inServer.Name
		return inServer.Name
	end
	local ok, name = pcall(function(): string
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local resolved = if ok and typeof(name) == "string" then name else "Player " .. userId
	nameCache[userId] = resolved
	return resolved
end

-- Everyone here whose data is loaded, with live values. Players still
-- loading are left out until their data arrives.
local function onlineRows(): { LeaderboardRules.Row }
	local rows: { LeaderboardRules.Row } = {}
	for _, player in Players:GetPlayers() do
		local data = PlayerDataService.get(player)
		if data then
			table.insert(rows, {
				UserId = player.UserId,
				Name = player.Name,
				Score = data.Score,
				Xp = data.Xp,
				Coins = data.Coins,
			})
		end
	end
	return rows
end

local function readPage(stat: string): ()
	local store: OrderedDataStore? = stores[stat]
	if store == nil then
		return
	end
	local ok, page = pcall(function(): { { key: string, value: number } }
		return store:GetSortedAsync(false, DataConfig.LeaderboardSize):GetCurrentPage()
	end)
	if not ok then
		warnOnce("read", "couldn't read the global board, keeping the last one: " .. tostring(page))
		return
	end
	local items: { LeaderboardRules.PageItem } = {}
	for _, item in page do
		local userId = tonumber(item.key)
		if userId and typeof(item.value) == "number" then
			table.insert(items, { UserId = userId, Value = item.value })
		end
	end
	pages[stat] = items
end

-- Builds the snapshot from the cached pages and the players here (yields
-- only to look up names of offline players, which are cached).
local function buildSnapshot(): Snapshot
	local online = onlineRows()
	local useGlobal = globalOnline and next(pages) ~= nil
	local rows = LeaderboardRules.merge(if useGlobal then pages else {}, online, nameFor)
	local tabs: { [string]: { LeaderboardRules.Row } } = {}
	for _, stat in LeaderboardRules.STATS do
		tabs[stat] = LeaderboardRules.rankBy(rows, stat, DataConfig.LeaderboardSize)
	end
	return {
		Global = useGlobal,
		Note = if useGlobal
			then "All servers, all time"
			else "This server only (global board offline)",
		Tabs = tabs,
		Online = online,
	}
end

local lastSnapshot: Snapshot? = nil

local function broadcast(): ()
	local snapshot = buildSnapshot()
	lastSnapshot = snapshot
	SnapshotRemote:FireAllClients(snapshot)
end

-- Joins and leaves within a moment are sent once.
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

local function refresh(): ()
	if globalOnline then
		for _, stat in LeaderboardRules.STATS do
			readPage(stat)
		end
	end
	broadcast()
end

local function writeStats(player: Player): ()
	local data = PlayerDataService.get(player)
	if data == nil or not globalOnline then
		return
	end
	local written = lastWritten[player] or {}
	lastWritten[player] = written
	local values: { [string]: number } = {
		Score = math.floor(data.Score),
		Xp = math.floor(data.Xp),
		Coins = math.floor(data.Coins),
	}
	for stat, value in values do
		local store: OrderedDataStore? = stores[stat]
		if store and written[stat] ~= value and value >= 0 then
			local ok, err = pcall(function()
				store:SetAsync(tostring(player.UserId), value)
			end)
			if ok then
				written[stat] = value
			else
				warnOnce("write", "couldn't save leaderboard stats: " .. tostring(err))
			end
		end
	end
end

function LeaderboardService.init(): ()
	globalOnline = true
	for stat, name in STORE_NAMES do
		local ok, ordered = pcall(function(): OrderedDataStore
			return DataStoreService:GetOrderedDataStore(name)
		end)
		if ok then
			stores[stat] = ordered
		else
			globalOnline = false
		end
	end

	buildBoard()
	Players.PlayerAdded:Connect(function(player: Player)
		-- Show them the board at once; the next broadcast includes them.
		local snapshot = lastSnapshot
		if snapshot then
			SnapshotRemote:FireClient(player, snapshot)
		end
		queueBroadcast()
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		-- Data is still readable here (PlayerDataService releases it in its own handler).
		task.spawn(function()
			writeStats(player)
			lastWritten[player] = nil
		end)
		queueBroadcast()
	end)
	PlayerDataService.onLoaded(function()
		queueBroadcast()
	end)
end

function LeaderboardService.start(): ()
	task.spawn(function()
		while true do
			refresh()
			task.wait(DataConfig.LeaderboardReadInterval)
		end
	end)
	while true do
		task.wait(DataConfig.LeaderboardWriteInterval)
		for _, player in Players:GetPlayers() do
			task.spawn(writeStats, player)
		end
	end
end

return LeaderboardService
