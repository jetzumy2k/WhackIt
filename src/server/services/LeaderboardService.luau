--!strict
--[[
	Global all-time leaderboard by lifetime Score (docs/DATA_SCHEMA.md).

	* Writes: each player's score goes to an OrderedDataStore every
	  LeaderboardWriteInterval seconds (only when it changed) and when they
	  leave. Scores come from the server's saved data, never from the client.
	* Reads: the top LeaderboardSize every LeaderboardReadInterval seconds,
	  shown on a board on the lobby's west wall (server-built, visible to all).
	* Without DataStore access (e.g. Studio with API access off) the board
	  ranks the players in this server instead and says so.
	All DataStore calls are wrapped in pcall; failures keep the last board.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local DataConfig = require(ServerScriptService.Config.DataConfig)
local LeaderboardRules = require(ServerScriptService.Lib.LeaderboardRules)
local PlayerDataService = require(script.Parent.PlayerDataService)

local LeaderboardService = {}

-- Board on the lobby's west wall (x = -36), facing into the lobby (+X).
local BOARD_POSITION = Vector3.new(-35.2, 7.5, 21)
local BOARD_SIZE = Vector3.new(0.4, 10, 13)
local TITLE = "TOP STRESS RELIEVERS"

local store: OrderedDataStore? = nil
local lastWritten: { [Player]: number } = {}
local nameCache: { [number]: string } = {}
local rowLabels: { TextLabel } = {}
local footer: TextLabel? = nil

local function label(parent: Instance, name: string, order: number, height: number): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.LayoutOrder = order
	text.Size = UDim2.fromScale(1, height)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Text = ""
	text.Parent = parent
	return text
end

local function buildBoard(): ()
	local board = Instance.new("Part")
	board.Name = "LeaderboardBoard"
	board.Anchored = true
	board.Size = BOARD_SIZE
	board.Position = BOARD_POSITION
	board.Color = Color3.fromRGB(35, 40, 60)
	board.Material = Enum.Material.SmoothPlastic

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Right
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = board

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.05, 0)
	padding.PaddingRight = UDim.new(0.05, 0)
	padding.PaddingTop = UDim.new(0.03, 0)
	padding.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = gui

	local title = label(gui, "Title", 0, 0.1)
	title.Text = TITLE
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextColor3 = Color3.fromRGB(255, 200, 90)
	for rank = 1, DataConfig.LeaderboardSize do
		table.insert(rowLabels, label(gui, "Row" .. rank, rank, 0.075))
	end
	local note = label(gui, "Footer", DataConfig.LeaderboardSize + 1, 0.06)
	note.TextTransparency = 0.4
	note.TextXAlignment = Enum.TextXAlignment.Center
	footer = note

	board.Parent = Workspace
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
	local resolved = if ok then name else "Player " .. userId
	nameCache[userId] = resolved
	return resolved
end

local function render(entries: { LeaderboardRules.Entry }, note: string): ()
	for rank, row in rowLabels do
		local entry = entries[rank]
		row.Text = if entry then LeaderboardRules.rowText(rank, entry) else ""
	end
	if footer then
		footer.Text = note
	end
end

local function localEntries(): { LeaderboardRules.Entry }
	local entries: { LeaderboardRules.Entry } = {}
	for _, player in Players:GetPlayers() do
		local data = PlayerDataService.get(player)
		if data then
			table.insert(
				entries,
				{ UserId = player.UserId, Name = player.Name, Score = data.Score }
			)
		end
	end
	return entries
end

local function readGlobal(): { LeaderboardRules.Entry }?
	local current = store
	if current == nil then
		return nil
	end
	local ok, page = pcall(function(): { { key: string, value: number } }
		local pages = current:GetSortedAsync(false, DataConfig.LeaderboardSize)
		return pages:GetCurrentPage()
	end)
	if not ok then
		return nil
	end
	local entries: { LeaderboardRules.Entry } = {}
	for _, item in page do
		local userId = tonumber(item.key)
		if userId then
			table.insert(entries, { UserId = userId, Name = nameFor(userId), Score = item.value })
		end
	end
	return entries
end

local function refreshBoard(): ()
	local global = readGlobal()
	if global then
		render(LeaderboardRules.rank(global, DataConfig.LeaderboardSize), "All servers, all time")
	else
		render(
			LeaderboardRules.rank(localEntries(), DataConfig.LeaderboardSize),
			"This server only (global board offline)"
		)
	end
end

local function writeScore(player: Player): ()
	local current = store
	local data = PlayerDataService.get(player)
	if current == nil or data == nil or lastWritten[player] == data.Score then
		return
	end
	local score = math.floor(data.Score)
	local ok = pcall(function()
		current:SetAsync(tostring(player.UserId), score)
	end)
	if ok then
		lastWritten[player] = score
	end
end

function LeaderboardService.init(): ()
	local ok, ordered = pcall(function(): OrderedDataStore
		return DataStoreService:GetOrderedDataStore(DataConfig.LeaderboardStoreName)
	end)
	store = if ok then ordered else nil

	buildBoard()
	Players.PlayerRemoving:Connect(function(player: Player)
		-- Data is still readable here (PlayerDataService releases it in its own handler).
		task.spawn(writeScore, player)
		lastWritten[player] = nil
	end)
end

function LeaderboardService.start(): ()
	task.spawn(function()
		while true do
			refreshBoard()
			task.wait(DataConfig.LeaderboardReadInterval)
		end
	end)
	while true do
		task.wait(DataConfig.LeaderboardWriteInterval)
		for _, player in Players:GetPlayers() do
			task.spawn(writeScore, player)
		end
	end
end

return LeaderboardService
