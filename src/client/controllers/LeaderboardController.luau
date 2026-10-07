--!strict
--[[
	Draws the leaderboard on the lobby's west wall (LeaderboardService builds
	the board; this client draws on it). Display only: rankings come from the
	server's Leaderboard.Snapshot and nothing is ever sent back.

	  * Tabs: Top Score, Top Level, Top Coins (this player's choice, local).
	  * Columns: Rank, Player, Score, Level, Coins ("-" when unknown).
	  * Rank #1 gets a gold row and outline, #2 silver and #3 bronze badges.
	  * "Your Rank": your place on the board, or in this server and what the
	    board's last place has.

	The rows are built once; a snapshot or a tab switch only changes their text
	and colours, and rows whose player or value changed fade and slide in. No
	per-frame work. The SurfaceGui lives in PlayerGui (so the tabs can be
	clicked) and survives respawns.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LevelRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LevelRules"))
local ProgressController = require(script.Parent.ProgressController)

local LeaderboardController = {}

-- The board's "YOU: ..." line as last shown (Player Panel).
local yourLine = ""

type Row = { UserId: number, Name: string, Score: number?, Xp: number?, Coins: number? }
type Snapshot = {
	Global: boolean,
	Note: string,
	Tabs: { [string]: { Row } },
	Online: { Row },
}
type RowView = {
	Group: CanvasGroup,
	Stroke: UIStroke,
	Badge: Frame,
	BadgeText: TextLabel,
	Cells: { [string]: TextLabel },
	Shown: string, -- what it showed last, to animate only real changes
}

local TABS = {
	{ Stat = "Score", Label = "Top Score" },
	{ Stat = "Xp", Label = "Top Level" },
	{ Stat = "Coins", Label = "Top Coins" },
}
-- Column: key, header, width (fraction of the row), alignment.
local COLUMNS = {
	{ Key = "Rank", Header = "RANK", Width = 0.11 },
	{ Key = "Name", Header = "PLAYER", Width = 0.4 },
	{ Key = "Score", Header = "SCORE", Width = 0.19 },
	{ Key = "Xp", Header = "LEVEL", Width = 0.12 },
	{ Key = "Coins", Header = "COINS", Width = 0.18 },
}
local ROWS = 10
local PIXELS_PER_STUD = 50
local MAX_DISTANCE = 120

local TEXT = Color3.fromRGB(235, 238, 245)
local MUTED = Color3.fromRGB(150, 160, 185)
local GOLD = Color3.fromRGB(255, 200, 70)
local SILVER = Color3.fromRGB(205, 210, 222)
local BRONZE = Color3.fromRGB(210, 135, 75)
local ROW_A = Color3.fromRGB(40, 46, 70)
local ROW_B = Color3.fromRGB(34, 39, 60)
local TAB = Color3.fromRGB(55, 62, 92)
local TAB_ACTIVE = Color3.fromRGB(70, 140, 230)
local CHANGE_SECONDS = 0.35

local localPlayer = Players.LocalPlayer

-- Formatting ---------------------------------------------------------------

local function thousands(value: number): string
	local digits = tostring(math.floor(math.max(0, value)))
	local formatted = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

local function cellText(row: Row, key: string): string
	if key == "Name" then
		return row.Name
	elseif key == "Score" then
		return if row.Score then thousands(row.Score) else "-"
	elseif key == "Xp" then
		return if row.Xp then "Lv " .. LevelRules.levelFor(row.Xp) else "-"
	elseif key == "Coins" then
		return if row.Coins then thousands(row.Coins) else "-"
	end
	return ""
end

local function statValue(row: Row, stat: string): number?
	if stat == "Score" then
		return row.Score
	elseif stat == "Xp" then
		return row.Xp
	end
	return row.Coins
end

local function statText(stat: string, value: number): string
	if stat == "Xp" then
		return "Lv " .. LevelRules.levelFor(value)
	end
	return thousands(value) .. (if stat == "Coins" then " coins" else " score")
end

-- Snapshot parsing (the server is trusted, but a bad payload must not break the UI).

local function parseRow(raw: unknown): Row?
	if typeof(raw) ~= "table" then
		return nil
	end
	local data = raw :: { [string]: unknown }
	if typeof(data.UserId) ~= "number" or typeof(data.Name) ~= "string" then
		return nil
	end
	local function number(value: unknown): number?
		return if typeof(value) == "number" and value == value then value else nil
	end
	return {
		UserId = data.UserId :: number,
		Name = data.Name :: string,
		Score = number(data.Score),
		Xp = number(data.Xp),
		Coins = number(data.Coins),
	}
end

local function parseRows(raw: unknown): { Row }
	local rows: { Row } = {}
	if typeof(raw) == "table" then
		for _, item in raw :: { unknown } do
			local row = parseRow(item)
			if row then
				table.insert(rows, row)
			end
		end
	end
	return rows
end

local function parseSnapshot(payload: unknown): Snapshot?
	if typeof(payload) ~= "table" then
		return nil
	end
	local data = payload :: { [string]: unknown }
	local tabs: { [string]: { Row } } = {}
	local rawTabs = if typeof(data.Tabs) == "table" then data.Tabs :: { [string]: unknown } else {}
	for _, tab in TABS do
		tabs[tab.Stat] = parseRows(rawTabs[tab.Stat])
	end
	return {
		Global = data.Global == true,
		Note = if typeof(data.Note) == "string" then data.Note else "",
		Tabs = tabs,
		Online = parseRows(data.Online),
	}
end

-- UI -----------------------------------------------------------------------

local function textLabel(parent: Instance, name: string, text: string, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = parent
	return label
end

local function corner(parent: Instance, radius: number): ()
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(radius, 0)
	c.Parent = parent
end

-- Places `count` cells across `parent` by COLUMNS widths.
local function columnCells(
	parent: Instance,
	color: Color3,
	makeText: (key: string) -> string
): { [string]: TextLabel }
	local cells: { [string]: TextLabel } = {}
	local x = 0
	for _, column in COLUMNS do
		if column.Key ~= "Rank" then
			local cell = textLabel(parent, column.Key, makeText(column.Key), color)
			cell.Position = UDim2.fromScale(x + 0.01, 0.15)
			cell.Size = UDim2.fromScale(column.Width - 0.02, 0.7)
			cell.TextXAlignment = if column.Key == "Name"
				then Enum.TextXAlignment.Left
				else Enum.TextXAlignment.Right
			cells[column.Key] = cell
		end
		x += column.Width
	end
	return cells
end

local function buildRow(parent: Instance, index: number): RowView
	local group = Instance.new("CanvasGroup")
	group.Name = "Row" .. index
	group.Size = UDim2.fromScale(1, 0.052)
	group.Position = UDim2.fromScale(0, 0.3 + (index - 1) * 0.055)
	group.BackgroundColor3 = if index % 2 == 1 then ROW_A else ROW_B
	group.Parent = parent
	corner(group, 0.25)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 0
	stroke.Color = GOLD
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = group

	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromScale(COLUMNS[1].Width / 2, 0.5)
	badge.Size = UDim2.fromScale(0.06, 0.85)
	badge.BackgroundColor3 = TAB
	badge.Parent = group
	corner(badge, 0.5)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = badge
	local badgeText = textLabel(badge, "Rank", tostring(index), Color3.fromRGB(30, 30, 40))
	badgeText.Size = UDim2.fromScale(1, 1)

	return {
		Group = group,
		Stroke = stroke,
		Badge = badge,
		BadgeText = badgeText,
		Cells = columnCells(group, TEXT, function()
			return ""
		end),
		Shown = "",
	}
end

local function styleRow(view: RowView, rank: number, filled: boolean): ()
	local badgeColor = if rank == 1
		then GOLD
		elseif rank == 2 then SILVER
		elseif rank == 3 then BRONZE
		else TAB
	view.Badge.BackgroundColor3 = badgeColor
	view.BadgeText.TextColor3 = if rank <= 3 then Color3.fromRGB(30, 30, 40) else TEXT
	if rank == 1 and filled then
		-- Rank #1: a warm gold row with a gold outline and gold name.
		view.Group.BackgroundColor3 = Color3.fromRGB(95, 78, 35)
		view.Stroke.Thickness = 2
		view.Stroke.Color = GOLD
		view.Cells.Name.TextColor3 = GOLD
	else
		view.Group.BackgroundColor3 = if rank % 2 == 1 then ROW_A else ROW_B
		view.Stroke.Thickness = if filled and rank <= 3 then 1 else 0
		view.Stroke.Color = if rank == 2 then SILVER else BRONZE
		view.Cells.Name.TextColor3 = TEXT
	end
end

function LeaderboardController.start(): ()
	local remote = ReplicatedStorage:WaitForChild("Remotes")
		:WaitForChild("Leaderboard")
		:WaitForChild("Snapshot")
	assert(remote:IsA("RemoteEvent"), "Leaderboard.Snapshot must be a RemoteEvent")
	local area = Workspace:WaitForChild("LeaderboardArea")
	local board = area:WaitForChild("LeaderboardBoard")
	assert(board:IsA("BasePart"), "LeaderboardBoard must be a part")

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Leaderboard"
	gui.ResetOnSpawn = false
	gui.Adornee = board
	gui.Face = Enum.NormalId.Right
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.MaxDistance = MAX_DISTANCE
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(0.94, 0.94)
	root.Parent = gui

	local title = textLabel(root, "Title", "HALL OF CALM: TOP STRESS RELIEVERS", GOLD)
	title.Size = UDim2.fromScale(1, 0.12)

	local activeStat = "Score"
	local snapshot: Snapshot? = nil
	local tabButtons: { [string]: TextButton } = {}
	local views: { RowView } = {}
	local render: (animate: boolean) -> ()

	for index, tab in TABS do
		local button = Instance.new("TextButton")
		button.Name = tab.Stat
		button.Position = UDim2.fromScale((index - 1) * 0.34, 0.135)
		button.Size = UDim2.fromScale(0.32, 0.075)
		button.BackgroundColor3 = TAB
		button.Font = Enum.Font.FredokaOne
		button.TextScaled = true
		button.TextColor3 = TEXT
		button.Text = tab.Label
		button.AutoButtonColor = true
		button.Parent = root
		corner(button, 0.3)
		button.Activated:Connect(function()
			if activeStat ~= tab.Stat then
				activeStat = tab.Stat
				render(false)
			end
		end)
		tabButtons[tab.Stat] = button
	end

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Position = UDim2.fromScale(0, 0.23)
	header.Size = UDim2.fromScale(1, 0.06)
	header.Parent = root
	local headerCells = columnCells(header, MUTED, function(key: string): string
		for _, column in COLUMNS do
			if column.Key == key then
				return column.Header
			end
		end
		return ""
	end)
	local rankHeader = textLabel(header, "Rank", "RANK", MUTED)
	rankHeader.Size = UDim2.fromScale(COLUMNS[1].Width, 0.7)
	rankHeader.Position = UDim2.fromScale(0, 0.15)

	for index = 1, ROWS do
		table.insert(views, buildRow(root, index))
	end

	local yours = textLabel(root, "YourRank", "", TEXT)
	yours:GetPropertyChangedSignal("Text"):Connect(function()
		yourLine = yours.Text
	end)
	yours.Position = UDim2.fromScale(0, 0.86)
	yours.Size = UDim2.fromScale(1, 0.07)
	local note = textLabel(root, "Note", "Loading the board...", MUTED)
	note.Position = UDim2.fromScale(0, 0.94)
	note.Size = UDim2.fromScale(1, 0.05)

	-- Your current values: live from your own stats (the server's, shown to you).
	local function myRow(): Row
		local stats = localPlayer:FindFirstChild("leaderstats")
		local score = if stats then stats:FindFirstChild("Score") else nil
		local coins = if stats then stats:FindFirstChild("Coins") else nil
		local progress = ProgressController.get()
		return {
			UserId = localPlayer.UserId,
			Name = localPlayer.Name,
			Score = if score and score:IsA("IntValue") then score.Value else nil,
			Xp = if progress then progress.Xp else nil,
			Coins = if coins and coins:IsA("IntValue") then coins.Value else nil,
		}
	end

	local function renderYours(): ()
		local current = snapshot
		if current == nil then
			yours.Text = ""
			return
		end
		local me = myRow()
		local myValue = statValue(me, activeStat)
		if myValue == nil then
			yours.Text = "YOU: your stats are still loading..."
			return
		end
		local list = current.Tabs[activeStat]
		for index, row in list do
			if row.UserId == me.UserId then
				yours.Text = string.format(
					"YOU: #%d on the board - %s",
					index,
					statText(activeStat, myValue)
				)
				return
			end
		end
		-- Your place among the players in this server (with your live value).
		local here = 1
		for _, row in current.Online do
			local value = statValue(row, activeStat)
			if row.UserId ~= me.UserId and value and value > myValue then
				here += 1
			end
		end
		local last = list[#list]
		local lastValue = if last then statValue(last, activeStat) else nil
		if #list < ROWS or lastValue == nil then
			yours.Text = string.format(
				"YOU: #%d in this server - %s. There's room on the board!",
				here,
				statText(activeStat, myValue)
			)
		else
			yours.Text = string.format(
				"YOU: #%d in this server - %s. The board starts at %s",
				here,
				statText(activeStat, myValue),
				statText(activeStat, lastValue)
			)
		end
	end

	function render(animate: boolean): ()
		for stat, button in tabButtons do
			button.BackgroundColor3 = if stat == activeStat then TAB_ACTIVE else TAB
		end
		for key, cell in headerCells do
			cell.TextColor3 = if key == activeStat then GOLD else MUTED
		end
		local current = snapshot
		local list = if current then current.Tabs[activeStat] else {}
		for rank, view in views do
			local row = list[rank]
			local signature = if row
				then string.format(
					"%d|%s|%s",
					row.UserId,
					tostring(statValue(row, activeStat)),
					activeStat
				)
				else ""
			for _, column in COLUMNS do
				local cell = view.Cells[column.Key]
				if cell then
					cell.Text = if row then cellText(row, column.Key) else ""
					cell.TextColor3 = if column.Key == activeStat and row then GOLD else TEXT
				end
			end
			styleRow(view, rank, row ~= nil)
			view.Group.Visible = row ~= nil
			-- Fade and slide in rows that changed (not on a tab switch).
			if animate and signature ~= view.Shown and row then
				view.Group.GroupTransparency = 1
				local target = view.Group.Position
				view.Group.Position = target + UDim2.fromScale(0.03, 0)
				local info = TweenInfo.new(
					CHANGE_SECONDS + rank * 0.03,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out
				)
				TweenService:Create(view.Group, info, { GroupTransparency = 0, Position = target })
					:Play()
			end
			view.Shown = signature
		end
		if current then
			note.Text = current.Note
			if #list == 0 then
				note.Text = "No rankings yet: be the first! (" .. current.Note .. ")"
			end
		end
		renderYours()
	end

	remote.OnClientEvent:Connect(function(payload: unknown)
		local parsed = parseSnapshot(payload)
		if parsed then
			snapshot = parsed
			render(true)
		end
	end)
	-- Your own line follows your stats as they change (text only).
	ProgressController.Changed:Connect(renderYours)
	local function watchStats(stats: Instance): ()
		for _, name in { "Score", "Coins" } do
			local value = stats:WaitForChild(name, 10)
			if value and value:IsA("IntValue") then
				value.Changed:Connect(renderYours)
			end
		end
	end
	task.spawn(function()
		local stats = localPlayer:WaitForChild("leaderstats", 30)
		if stats then
			watchStats(stats)
		end
	end)

	render(false)
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

-- The board's "YOU: ..." line for the tab last viewed, or "" before the
-- first snapshot (display only).
function LeaderboardController.yourLine(): string
	return yourLine
end

return LeaderboardController
