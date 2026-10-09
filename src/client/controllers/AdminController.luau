--!strict
--[[
	Admin panel (docs/ADMIN.md). Shown only when the server's Admin.State says
	this player is an admin, but that is display only: the server re-checks
	admin rights, bounds and targets on every request (AdminService).

	Built on Lib/PanelKit (redesigned 2026-10-07): a wide window with a sidebar
	(a top strip on narrow screens), collapsible section cards and a scrolling
	content area. Open with the "Admin" button or F2; close with X or F2.

	Tabs:
	  Dashboard   server info, game status, everyone here (Manage / Moderate)
	  Players     set level, set damage, unlock / lock bosses for anyone here
	  Bosses      create a custom boss where you stand; move or delete them
	  Events      create, schedule, stop and review events (every server)
	  Drop Rates  office boss buff drop chances and the Lucky window (all servers)
	  Announce    a message on every player's screen in this server
	  Moderation  ban, suspend or unban by player or username
	Store opening hours stay in the Store panel's Admin tab.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AnnouncementConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("AnnouncementConfig"))
local Attributes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attributes"))
local BossConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BossConfig"))
local CustomBossConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("CustomBossConfig"))
local DropRateConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("DropRateConfig"))
local DropRateRules =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DropRateRules"))
local BagRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BagRules"))
local EventConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("EventConfig"))
local EventRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EventRules"))
local HammerConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("HammerConfig"))
local PetConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("PetConfig"))
local StoreConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StoreConfig"))

local LocalTime = require(script.Parent.Parent.Lib.LocalTime)
local PanelKit = require(script.Parent.Parent.Lib.PanelKit)
local Responsive = require(script.Parent.Parent.Lib.Responsive)

local AdminController = {}

local TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local TAB_COLOR = Color3.fromRGB(70, 70, 90)
local TAB_ACTIVE_COLOR = Color3.fromRGB(70, 140, 230)
local ADMIN_COLOR = Color3.fromRGB(150, 80, 200)
local GOOD_COLOR = Color3.fromRGB(80, 190, 90)
local DANGER_COLOR = Color3.fromRGB(200, 80, 80)
local MUTED_COLOR = Color3.fromRGB(90, 90, 100)
local MIN_TOUCH_SIZE = 44
local CONFIRM_SECONDS = 3
local ALL_BOSSES = "*"
local RESPAWN_TEXT: { [string]: string } = { Continuous = "Respawns", Once = "One time" }

local TABS = {
	{ Id = "Dashboard", Label = "Dashboard" },
	{ Id = "Players", Label = "Players" },
	{ Id = "Bosses", Label = "Bosses" },
	{ Id = "Events", Label = "Events" },
	{ Id = "Drops", Label = "Drop Rates" },
	{ Id = "Announce", Label = "Announce" },
	{ Id = "Rewards", Label = "Rewards" },
	{ Id = "History", Label = "History" },
	{ Id = "Moderation", Label = "Moderation" },
}
-- Desktop shortcut for admins.
local TOGGLE_KEY = Enum.KeyCode.F2
-- Cards that start folded up (Tab/Title), so long pages stay readable.
local START_COLLAPSED = {
	["Players/Unlock bosses"] = true,
	["Moderation/...or a username (used when filled in)"] = true,
	["Events/Event history"] = true,
}
local EVENT_TIMING = { "Start now", "Schedule (start and end)" }
local DISCOUNT_SCOPES = { "All hammers", "Selected hammers" }
-- "All bosses" first, then every office boss.
local DROP_BOSS_CHOICES: { string } = { EventRules.ALL_BOSSES }
for _, boss in BossConfig.List do
	table.insert(DROP_BOSS_CHOICES, boss.Id)
end
-- Rewards an admin can give (AdminService checks every one).
local REWARD_KINDS: { { Key: string, Text: string } } = {
	{ Key = "Coins", Text = "Coins" },
	{ Key = "Xp", Text = "XP" },
	{ Key = "Item", Text = "Store item (boost, bundle, egg, Mystery Hammer)" },
	{ Key = "Hammer", Text = "Hammer" },
	{ Key = "Pet", Text = "Pet" },
}
-- History filters (HistoryService). Key nil = everything.
local HISTORY_MODES = { "Player", "Admin" }
local HISTORY_TYPES: { { Key: string?, Text: string } } = {
	{ Key = nil, Text = "Everything" },
	{ Key = "Admin", Text = "Admin actions" },
	{ Key = "Purchase", Text = "Purchases" },
	{ Key = "Buff", Text = "Boosts used" },
	{ Key = "Item", Text = "Items opened" },
	{ Key = "Egg", Text = "Eggs" },
	{ Key = "Pet", Text = "Pets" },
	{ Key = "Event", Text = "Event rewards" },
}
local HISTORY_DAYS: { { Days: number, Text: string } } = {
	{ Days = 0, Text = "All time" },
	{ Days = 1, Text = "Last 24 hours" },
	{ Days = 7, Text = "Last 7 days" },
	{ Days = 30, Text = "Last 30 days" },
}
local HISTORY_ACTIONS: { { Key: string?, Text: string } } = {
	{ Key = nil, Text = "Every action" },
	{ Key = "Reward", Text = "Rewards" },
	{ Key = "Event", Text = "Events" },
	{ Key = "SetLevel", Text = "Set level" },
	{ Key = "SetDamage", Text = "Set damage" },
	{ Key = "Unlock", Text = "Unlocks" },
	{ Key = "Bypass", Text = "Bypass" },
	{ Key = "Action", Text = "Other" },
}

-- Hammers a sale can cover (free ones are always free).
local SALE_HAMMERS: { HammerConfig.HammerDefinition } = {}
for _, hammer in HammerConfig.List do
	if hammer.Price > 0 then
		table.insert(SALE_HAMMERS, hammer)
	end
end

type CustomBoss = {
	Id: string,
	Name: string,
	LookId: string,
	MaxHealth: number,
	ScoreReward: number,
	CoinReward: number,
	RespawnMode: string,
	Defeated: boolean,
}

type Choice = { Key: string, Text: string }

-- A running or scheduled event (EventService.adminView).
type AdminEvent = {
	Id: string,
	Name: string,
	Type: string,
	StartTime: number,
	EndTime: number,
	Summary: string,
	CreatedByName: string,
	Active: boolean,
	Config: { [string]: unknown }, -- its settings, to edit it
}

-- An event that ended or was stopped.
type EventHistoryItem = {
	Name: string,
	Type: string,
	StartTime: number,
	EndTime: number,
	Summary: string,
	CreatedByName: string,
	StoppedByName: string, -- "" when it ran out on its own
	Id: string,
	Status: string, -- "Completed" | "Stopped" | "Cancelled" | "Removed" ("" for old entries)
	PlannedEndTime: number, -- 0 for old entries
}

-- One history line (HistoryService entry, from Admin.HistoryResult).
type HistoryLine = {
	At: number,
	Type: string,
	Action: string,
	Text: string,
	Status: string,
	By: string,
	TargetName: string,
	TargetUserId: number,
}

type HistoryView = {
	Mode: string,
	Page: number,
	HasMore: boolean,
	Entries: { HistoryLine },
}

type State = {
	IsAdmin: boolean,
	CustomBosses: { CustomBoss },
	DropRates: DropRateRules.Settings?,
	DamageOverrides: { [string]: number },
	MaxSetLevel: number,
	MaxSetDamage: number,
	BanDurations: { Choice },
	BanReasons: { Choice },
	Events: { AdminEvent },
	EventHistory: { EventHistoryItem },
	NextWorldEggAt: number,
	WorldEggs: number,
	Bypass: boolean,
}

local localPlayer = Players.LocalPlayer
-- Set once the window exists; let the Player Panel open this one.
local openPanel: (() -> ())? = nil
local isAdminNow = false

local function corner(parent: Instance): ()
	Instance.new("UICorner").Parent = parent
end

local function stringField(data: { [string]: unknown }, key: string): string
	local value = data[key]
	return if typeof(value) == "string" then value else ""
end

local function numberField(data: { [string]: unknown }, key: string): number
	local value = data[key]
	return if typeof(value) == "number" then value else 0
end

-- Server messages are still checked so a malformed one can't break the UI.
local function parseState(payload: unknown): State?
	if typeof(payload) ~= "table" then
		return nil
	end
	local data = payload :: { [string]: unknown }
	local state: State = {
		IsAdmin = data.IsAdmin == true,
		CustomBosses = {},
		DropRates = (DropRateRules.parse(data.DropRates)),
		DamageOverrides = {},
		MaxSetLevel = numberField(data, "MaxSetLevel"),
		MaxSetDamage = numberField(data, "MaxSetDamage"),
		BanDurations = {},
		BanReasons = {},
		Events = {},
		EventHistory = {},
		NextWorldEggAt = numberField(data, "NextWorldEggAt"),
		Bypass = data.Bypass == true,
		WorldEggs = numberField(data, "WorldEggs"),
	}
	local eventView = data.Events
	if typeof(eventView) == "table" then
		local view = eventView :: { [string]: unknown }
		if typeof(view.Events) == "table" then
			for _, raw in view.Events :: { unknown } do
				if typeof(raw) == "table" then
					local event = raw :: { [string]: unknown }
					table.insert(state.Events, {
						Id = stringField(event, "Id"),
						Name = stringField(event, "Name"),
						Type = stringField(event, "Type"),
						StartTime = numberField(event, "StartTime"),
						EndTime = numberField(event, "EndTime"),
						Summary = stringField(event, "Summary"),
						CreatedByName = stringField(event, "CreatedByName"),
						Active = event.Active == true,
						Config = if typeof(event.Config) == "table"
							then event.Config :: { [string]: unknown }
							else {},
					})
				end
			end
		end
		if typeof(view.History) == "table" then
			for _, raw in view.History :: { unknown } do
				if typeof(raw) == "table" then
					local entry = raw :: { [string]: unknown }
					table.insert(state.EventHistory, {
						Name = stringField(entry, "Name"),
						Type = stringField(entry, "Type"),
						StartTime = numberField(entry, "StartTime"),
						EndTime = numberField(entry, "EndTime"),
						Summary = stringField(entry, "Summary"),
						CreatedByName = stringField(entry, "CreatedByName"),
						StoppedByName = stringField(entry, "StoppedByName"),
						Id = stringField(entry, "Id"),
						Status = stringField(entry, "Status"),
						PlannedEndTime = numberField(entry, "PlannedEndTime"),
					})
				end
			end
		end
	end
	if typeof(data.CustomBosses) == "table" then
		for _, raw in data.CustomBosses :: { unknown } do
			if typeof(raw) == "table" then
				local boss = raw :: { [string]: unknown }
				table.insert(state.CustomBosses, {
					Id = stringField(boss, "Id"),
					Name = stringField(boss, "Name"),
					LookId = stringField(boss, "LookId"),
					MaxHealth = numberField(boss, "MaxHealth"),
					ScoreReward = numberField(boss, "ScoreReward"),
					CoinReward = numberField(boss, "CoinReward"),
					RespawnMode = stringField(boss, "RespawnMode"),
					Defeated = boss.Defeated == true,
				})
			end
		end
	end
	if typeof(data.DamageOverrides) == "table" then
		for userId, damage in data.DamageOverrides :: { [unknown]: unknown } do
			if typeof(userId) == "string" and typeof(damage) == "number" then
				state.DamageOverrides[userId] = damage
			end
		end
	end
	if typeof(data.BanDurations) == "table" then
		for _, raw in data.BanDurations :: { unknown } do
			if typeof(raw) == "table" then
				local text = stringField(raw :: { [string]: unknown }, "Label")
				table.insert(state.BanDurations, { Key = text, Text = text })
			end
		end
	end
	if typeof(data.BanReasons) == "table" then
		for _, raw in data.BanReasons :: { unknown } do
			if typeof(raw) == "table" then
				local reason = raw :: { [string]: unknown }
				table.insert(
					state.BanReasons,
					{ Key = stringField(reason, "Key"), Text = stringField(reason, "Text") }
				)
			end
		end
	end
	return state
end

-- Drop rate form fields, in the order of DropRateRules.Settings.
local DROP_FIELDS = {
	"NormalMin",
	"NormalMax",
	"LuckyMin",
	"LuckyMax",
	"LuckyEveryMinutes",
	"LuckyLastsMinutes",
}

local function percentText(chance: number): string
	return string.format("%g%%", chance * 100)
end

local function bossName(bossId: string): string
	local boss = BossConfig.ById[bossId]
	return if boss then boss.DisplayName else bossId
end

function AdminController.start(): ()
	local remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Admin")
	local function remote(name: string): RemoteEvent
		local instance = remotes:WaitForChild(name)
		assert(instance:IsA("RemoteEvent"), "Admin." .. name .. " must be a RemoteEvent")
		return instance
	end
	local setLevelRemote = remote("SetLevel")
	local setDamageRemote = remote("SetDamage")
	local setUnlockRemote = remote("SetUnlock")
	local createBossRemote = remote("CreateBoss")
	local editBossRemote = remote("EditBoss")
	local moderateRemote = remote("Moderate")
	local setDropRatesRemote = remote("SetDropRates")
	local announceRemote = remote("Announce")
	local eventsRemote = remote("Events")
	local spawnEggRemote = remote("SpawnEgg")
	local rewardRemote = remote("Reward")
	local historyRemote = remote("History")
	local historyResultRemote = remote("HistoryResult")
	local bypassRemote = remote("Bypass")
	local stateRemote = remote("State")

	local state: State? = nil
	local activeTab = "Dashboard"
	-- Form values survive re-renders (the server re-sends state after changes).
	local texts: { [string]: string } = {
		Level = "",
		Damage = "",
		BossName = "",
		Health = "500",
		Score = "300",
		Coins = "50",
		Username = "",
		Note = "",
		Announcement = "",
		EventName = "",
		EventStart = "",
		EventEnd = "",
		DropChance = "10",
		Discount = "20",
	}
	local picks: { [string]: number } = {
		UnlockIndex = 1,
		LookIndex = 1,
		RespawnIndex = 1,
		DurationIndex = 1,
		ReasonIndex = 1,
		AnnounceIndex = math.max(
			1,
			table.find(AnnouncementConfig.Durations, AnnouncementConfig.DefaultSeconds) or 1
		),
		EventTypeIndex = 1,
		EventTimingIndex = 1,
		EventDurationIndex = 2,
		XpMultIndex = math.max(1, table.find(EventConfig.XpMultipliers, 2) or 1),
		SpawnBossIndex = 1,
		SpawnLocationIndex = 1,
		SpawnQuantityIndex = 1,
		DropBossIndex = 1,
		DropItemIndex = 1,
		DiscountScopeIndex = 1,
		EggRarityIndex = 1,
		EggHuntRarityIndex = 2,
		EggHuntIntervalIndex = 2,
		EggHuntMaxIndex = 3,
		RewardKindIndex = 1,
		RewardKeyIndex = 1,
		HistoryModeIndex = 1,
		HistoryTypeIndex = 1,
		HistoryDaysIndex = 1,
		HistoryDayIndex = 1,
		HistoryActionIndex = 1,
	}
	-- Hammers ticked for a "Selected hammers" sale.
	local saleHammers: { [string]: boolean } = {}
	-- The event being edited in the Events tab (nil = creating a new one).
	local editingId: string? = nil
	local rewardUserId = localPlayer.UserId
	local historyUserId = localPlayer.UserId
	local historyView: HistoryView? = nil
	-- Drop rate texts as last sent by the server: a field the admin hasn't
	-- edited follows the server, an edited one keeps the admin's text.
	local serverDropTexts: { [string]: string } = {}
	local targetUserId = localPlayer.UserId
	local modUserId = 0

	local window = PanelKit.window({
		Name = "Admin",
		Title = "Admin Panel",
		Subtitle = "Every action is checked and logged by the server.",
		Accent = ADMIN_COLOR,
		DisplayOrder = 6,
	}, localPlayer:WaitForChild("PlayerGui"))
	local list = window.Content

	-- The HUD button (only for admins), top of the shared column (Lib/Responsive).
	local open = Responsive.dockButton("OpenAdmin", "🛡️", "Admin", ADMIN_COLOR, 1)
	open.Visible = false

	-- Where the page helpers below add things: the page, or the open card.
	local container: Instance = list
	local collapsed: { [string]: boolean } = table.clone(START_COLLAPSED)

	local function note(text: string, _height: number?): TextLabel
		return PanelKit.text(container, text, "Muted")
	end

	-- Starts a new (collapsible) card; the rows after it go inside.
	local function heading(text: string): ()
		local key = activeTab .. "/" .. text
		local section = PanelKit.section(list, text, true, not collapsed[key], function(expanded)
			collapsed[key] = not expanded
		end)
		container = section.Body
	end

	local function row(): Frame
		return PanelKit.row(container)
	end

	local function rowButton(parent: Frame, text: string, color: Color3, width: number): TextButton
		local clickable = PanelKit.button(parent, text, color)
		clickable.Size = UDim2.new(width, -8, 1, 0)
		return clickable
	end

	local function rowLabel(parent: Frame, text: string, width: number): TextLabel
		local line = Instance.new("TextLabel")
		line.Name = "Label"
		line.LayoutOrder = #parent:GetChildren()
		line.BackgroundTransparency = 1
		line.Size = UDim2.new(width, -8, 1, 0)
		line.Font = PanelKit.FONT
		line.TextColor3 = TEXT_COLOR
		line.TextWrapped = true
		PanelKit.setTextSize(line, PanelKit.TEXT_SIZE)
		line.TextXAlignment = Enum.TextXAlignment.Left
		line.Text = text
		line.Parent = parent
		return line
	end

	-- A text box whose value is kept in `texts[key]`.
	local function rowBox(
		parent: Frame,
		key: string,
		placeholder: string,
		width: number,
		numeric: boolean
	): TextBox
		local box = Instance.new("TextBox")
		box.Name = key
		box.LayoutOrder = #parent:GetChildren()
		box.Size = UDim2.new(width, -8, 1, 0)
		box.BackgroundColor3 = PanelKit.Colors.Field
		box.TextColor3 = TEXT_COLOR
		box.PlaceholderText = placeholder
		box.PlaceholderColor3 = PanelKit.Colors.Muted
		box.Font = PanelKit.FONT
		box.TextSize = PanelKit.TEXT_SIZE
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.ClearTextOnFocus = false
		box.Text = texts[key] or ""
		box.Parent = parent
		corner(box)
		local inset = Instance.new("UIPadding")
		inset.PaddingLeft = UDim.new(0, 10)
		inset.PaddingRight = UDim.new(0, 10)
		inset.Parent = box
		box:GetPropertyChangedSignal("Text"):Connect(function()
			local text = box.Text
			if numeric then
				local digits = string.gsub(text, "%D", "")
				if digits ~= text then
					box.Text = digits
					return
				end
			end
			texts[key] = text
		end)
		return box
	end

	-- "< Name >" picker over `count` choices; `picks[key]` holds the 1-based index.
	local function cycler(
		parent: Frame,
		key: string,
		count: number,
		textFor: (index: number) -> string,
		width: number,
		onChange: () -> ()
	): ()
		local current = math.clamp(picks[key] or 1, 1, math.max(count, 1))
		picks[key] = current
		local previous = rowButton(parent, "<", TAB_COLOR, 0)
		previous.Size = UDim2.new(0, MIN_TOUCH_SIZE, 1, 0)
		local shown = rowLabel(parent, if count > 0 then textFor(current) else "-", width)
		shown.Size = UDim2.new(width, -(2 * MIN_TOUCH_SIZE + 8), 1, 0)
		shown.TextXAlignment = Enum.TextXAlignment.Center
		local following = rowButton(parent, ">", TAB_COLOR, 0)
		following.Size = UDim2.new(0, MIN_TOUCH_SIZE, 1, 0)
		local function step(delta: number): ()
			if count == 0 then
				return
			end
			picks[key] = (picks[key] - 1 + delta) % count + 1
			onChange()
		end
		previous.Activated:Connect(function()
			step(-1)
		end)
		following.Activated:Connect(function()
			step(1)
		end)
	end

	-- A small "Are you sure?" dialog over the panel: [Cancel] [Confirm].
	local confirmDialog = PanelKit.confirmDialog(window, DANGER_COLOR)
	local function askConfirm(message: string, action: () -> ()): ()
		confirmDialog.ask(message, "Confirm", action)
	end

	-- A button that needs a second click within CONFIRM_SECONDS.
	local function confirmButton(clickable: TextButton, action: () -> ()): ()
		local armedAt = 0
		local original = clickable.Text
		clickable.Activated:Connect(function()
			if os.clock() - armedAt <= CONFIRM_SECONDS then
				armedAt = 0
				clickable.Text = original
				action()
				return
			end
			armedAt = os.clock()
			clickable.Text = "Click again"
			task.delay(CONFIRM_SECONDS, function()
				if clickable.Parent and os.clock() - armedAt >= CONFIRM_SECONDS then
					clickable.Text = original
				end
			end)
		end)
	end

	local render: () -> ()

	local function uptimeText(seconds: number): string
		local minutes = math.floor(seconds / 60)
		return string.format("%dh %02dm", minutes // 60, minutes % 60)
	end

	local function dashboardPage(current: State): ()
		heading("Server")
		local serverGrid = PanelKit.grid(container, 170, 74)
		PanelKit.statTile(
			serverGrid,
			"Players",
			string.format("%d / %d", #Players:GetPlayers(), Players.MaxPlayers)
		)
		PanelKit.statTile(serverGrid, "Uptime", uptimeText(Workspace.DistributedGameTime))
		PanelKit.statTile(serverGrid, "Place version", tostring(game.PlaceVersion))
		PanelKit.statTile(
			serverGrid,
			"Server",
			if game.JobId == "" then "Studio" else string.sub(game.JobId, 1, 8)
		)

		heading("Game")
		local gameGrid = PanelKit.grid(container, 170, 74)
		PanelKit.statTile(
			gameGrid,
			"Custom bosses",
			string.format("%d / %d", #current.CustomBosses, CustomBossConfig.MaxBosses)
		)
		local overrides = 0
		for _ in current.DamageOverrides do
			overrides += 1
		end
		PanelKit.statTile(gameGrid, "Admin damage on", tostring(overrides))
		local rates = current.DropRates
		if rates then
			local lucky = DropRateRules.isLucky(rates, Workspace:GetServerTimeNow())
			PanelKit.statTile(
				gameGrid,
				"Buff drops now",
				if lucky
					then string.format(
						"Lucky %s-%s",
						percentText(rates.LuckyMin),
						percentText(rates.LuckyMax)
					)
					else string.format(
						"%s-%s",
						percentText(rates.NormalMin),
						percentText(rates.NormalMax)
					),
				if lucky then PanelKit.Colors.Heading else nil
			)
		end

		heading("Players in this server")
		local players = Players:GetPlayers()
		table.sort(players, function(a, b)
			return a.DisplayName < b.DisplayName
		end)
		for _, player in players do
			local playerRow = row()
			local level = player:GetAttribute(Attributes.Level)
			local stats = player:FindFirstChild("leaderstats")
			local score = if stats then stats:FindFirstChild("Score") else nil
			rowLabel(
				playerRow,
				string.format(
					"%s (@%s)   Lv %s   Score %s",
					player.DisplayName,
					player.Name,
					if typeof(level) == "number" then tostring(level) else "-",
					if score and score:IsA("IntValue") then tostring(score.Value) else "-"
				),
				0.56
			)
			rowButton(playerRow, "Manage", TAB_ACTIVE_COLOR, 0.22).Activated:Connect(function()
				targetUserId = player.UserId
				activeTab = "Players"
				render()
			end)
			local moderate = rowButton(playerRow, "Moderate", MUTED_COLOR, 0.22)
			if player == localPlayer then
				PanelKit.setDisabled(moderate, true)
			else
				moderate.Activated:Connect(function()
					modUserId = player.UserId
					activeTab = "Moderation"
					render()
				end)
			end
		end
	end

	local function playersPage(current: State): ()
		local players = Players:GetPlayers()
		table.sort(players, function(a, b)
			return a.DisplayName < b.DisplayName
		end)
		local targetIndex = 1
		for index, player in players do
			if player.UserId == targetUserId then
				targetIndex = index
			end
		end
		local target = players[targetIndex]
		targetUserId = if target then target.UserId else localPlayer.UserId

		heading("Your boss access")
		note(
			if current.Bypass
				then "Bypass is ON: every office door and boss is open to you this session. Your progress isn't changed. Normal players are unaffected."
				else "Bypass is OFF: you follow the normal boss requirements. Turn it on to reach any office or boss (this session only; the server checks it)."
		)
		local bypassRow = row()
		rowButton(
			bypassRow,
			if current.Bypass then "Turn bypass OFF" else "Turn bypass ON",
			if current.Bypass then MUTED_COLOR else ADMIN_COLOR,
			1
		).Activated:Connect(function()
			bypassRemote:FireServer(not current.Bypass)
		end)

		heading("Player")
		local targetRow = row()
		local pick = { Index = targetIndex }
		local previous = rowButton(targetRow, "<", TAB_COLOR, 0)
		previous.Size = UDim2.new(0, MIN_TOUCH_SIZE, 1, 0)
		local shown = rowLabel(
			targetRow,
			if target then string.format("%s (@%s)", target.DisplayName, target.Name) else "Nobody",
			0.8
		)
		shown.Size = UDim2.new(1, -(2 * MIN_TOUCH_SIZE + 16), 1, 0)
		shown.TextXAlignment = Enum.TextXAlignment.Center
		local following = rowButton(targetRow, ">", TAB_COLOR, 0)
		following.Size = UDim2.new(0, MIN_TOUCH_SIZE, 1, 0)
		local function step(delta: number): ()
			if #players == 0 then
				return
			end
			pick.Index = (pick.Index - 1 + delta) % #players + 1
			targetUserId = players[pick.Index].UserId
			render()
		end
		previous.Activated:Connect(function()
			step(-1)
		end)
		following.Activated:Connect(function()
			step(1)
		end)

		heading("Level")
		local levelRow = row()
		rowBox(levelRow, "Level", string.format("1 to %d", current.MaxSetLevel), 0.5, true)
		rowButton(levelRow, "Set level", GOOD_COLOR, 0.5).Activated:Connect(function()
			local level = tonumber(texts.Level)
			if level then
				setLevelRemote:FireServer(targetUserId, level)
			end
		end)

		heading("Damage per hit")
		local override = current.DamageOverrides[tostring(targetUserId)]
		note(
			if override
				then string.format(
					"Now: %d per hit. Hits with admin damage earn no score, coins or XP.",
					override
				)
				else "Now: normal hammer damage. Admin damage lasts until they leave and earns no rewards.",
			40
		)
		local damageRow = row()
		rowBox(damageRow, "Damage", string.format("1 to %d", current.MaxSetDamage), 0.4, true)
		rowButton(damageRow, "Set damage", GOOD_COLOR, 0.3).Activated:Connect(function()
			local damage = tonumber(texts.Damage)
			if damage then
				setDamageRemote:FireServer(targetUserId, damage)
			end
		end)
		rowButton(damageRow, "Normal", MUTED_COLOR, 0.3).Activated:Connect(function()
			setDamageRemote:FireServer(targetUserId, 0)
		end)

		heading("Unlock bosses")
		local bossRow = row()
		cycler(bossRow, "UnlockIndex", #BossConfig.List, function(index)
			return BossConfig.List[index].DisplayName
		end, 0.7, render)
		local unlockRow = row()
		rowButton(unlockRow, "Unlock", GOOD_COLOR, 0.5).Activated:Connect(function()
			local boss = BossConfig.List[picks.UnlockIndex]
			if boss then
				setUnlockRemote:FireServer(targetUserId, boss.Id, true)
			end
		end)
		rowButton(unlockRow, "Remove unlock", MUTED_COLOR, 0.5).Activated:Connect(function()
			local boss = BossConfig.List[picks.UnlockIndex]
			if boss then
				setUnlockRemote:FireServer(targetUserId, boss.Id, false)
			end
		end)
		local allRow = row()
		rowButton(allRow, "Unlock all", GOOD_COLOR, 0.5).Activated:Connect(function()
			setUnlockRemote:FireServer(targetUserId, ALL_BOSSES, true)
		end)
		confirmButton(rowButton(allRow, "Reset admin unlocks", DANGER_COLOR, 0.5), function()
			setUnlockRemote:FireServer(targetUserId, ALL_BOSSES, false)
		end)
		note(
			"Admin unlocks open a boss even without the defeats or level it normally needs. Earned unlocks are never removed.",
			40
		)
	end

	local function bossesPage(current: State): ()
		note(
			string.format(
				"Fictional everyday annoyances only: no real people or groups. The boss appears where you stand, in every server. Each player who deals 10%% of its HP gets a random %d-minute store boost. A one-time boss is gone for good after its first defeat.",
				CustomBossConfig.BuffDropSeconds // 60
			),
			76
		)
		heading("New boss")
		local nameRow = row()
		rowLabel(nameRow, "Name", 0.25)
		rowBox(
			nameRow,
			"BossName",
			string.format("e.g. Printer Jam (max %d)", CustomBossConfig.NameMaxLength),
			0.75,
			false
		)
		local lookRow = row()
		rowLabel(lookRow, "Look", 0.25)
		cycler(lookRow, "LookIndex", #CustomBossConfig.LookIds, function(index)
			return bossName(CustomBossConfig.LookIds[index])
		end, 0.55, render)
		local respawnRow = row()
		rowLabel(respawnRow, "Respawn", 0.25)
		cycler(respawnRow, "RespawnIndex", #CustomBossConfig.RespawnModes, function(index)
			return RESPAWN_TEXT[CustomBossConfig.RespawnModes[index]] or "-"
		end, 0.55, render)
		local statsRow = row()
		rowLabel(statsRow, "HP", 0.1)
		rowBox(statsRow, "Health", "HP", 0.23, true)
		rowLabel(statsRow, "Score", 0.15)
		rowBox(statsRow, "Score", "Score", 0.2, true)
		rowLabel(statsRow, "Coins", 0.14)
		rowBox(statsRow, "Coins", "Coins", 0.18, true)
		local createRow = row()
		rowButton(createRow, "Create boss here", GOOD_COLOR, 1).Activated:Connect(function()
			createBossRemote:FireServer({
				Name = texts.BossName,
				LookId = CustomBossConfig.LookIds[picks.LookIndex],
				MaxHealth = tonumber(texts.Health) or 0,
				ScoreReward = tonumber(texts.Score) or 0,
				CoinReward = tonumber(texts.Coins) or 0,
				RespawnMode = CustomBossConfig.RespawnModes[picks.RespawnIndex],
			})
		end)

		heading(
			string.format(
				"Custom bosses (%d / %d)",
				#current.CustomBosses,
				CustomBossConfig.MaxBosses
			)
		)
		if #current.CustomBosses == 0 then
			note("None yet.", 24)
		end
		for _, boss in current.CustomBosses do
			local bossRow = row()
			rowLabel(
				bossRow,
				string.format(
					"%s  (%d HP, %s, %s)",
					boss.Name,
					boss.MaxHealth,
					bossName(boss.LookId),
					if boss.Defeated
						then "defeated"
						else string.lower(RESPAWN_TEXT[boss.RespawnMode] or "respawns")
				),
				0.56
			)
			rowButton(bossRow, "Move here", TAB_ACTIVE_COLOR, 0.22).Activated:Connect(function()
				editBossRemote:FireServer("Move", boss.Id)
			end)
			confirmButton(rowButton(bossRow, "Delete", DANGER_COLOR, 0.22), function()
				editBossRemote:FireServer("Delete", boss.Id)
			end)
		end
	end

	local function dropsPage(current: State): ()
		local default = DropRateConfig.Default
		note(
			string.format(
				"Office bosses only (custom bosses always drop). Chances are 0 to 1: 0.30 = 30%%. Each qualifying player's roll uses a random chance between Min and Max. The Lucky range applies for 'Lasts' minutes at the start of every 'Every' minutes (UTC), in every server. Defaults: normal %s to %s, lucky %s to %s for %d min every %d min.",
				percentText(default.NormalMin),
				percentText(default.NormalMax),
				percentText(default.LuckyMin),
				percentText(default.LuckyMax),
				default.LuckyLastsMinutes,
				default.LuckyEveryMinutes
			),
			96
		)
		local rates = current.DropRates
		if rates then
			local lucky = DropRateRules.isLucky(rates, Workspace:GetServerTimeNow())
			local minutes = math.ceil(
				DropRateRules.secondsUntilChange(rates, Workspace:GetServerTimeNow()) / 60
			)
			note(
				if lucky
					then string.format(
						"Lucky window is ON now (%s to %s), ends in about %d min.",
						percentText(rates.LuckyMin),
						percentText(rates.LuckyMax),
						minutes
					)
					else string.format(
						"Normal chance now (%s to %s). Next Lucky window in about %d min.",
						percentText(rates.NormalMin),
						percentText(rates.NormalMax),
						minutes
					),
				40
			)
		else
			note("Waiting for the server's drop rates...", 24)
		end

		heading("Normal chance (most of the time)")
		local normalRow = row()
		rowLabel(normalRow, "Min", 0.15)
		rowBox(normalRow, "NormalMin", "e.g. 0.0005", 0.35, false)
		rowLabel(normalRow, "Max", 0.15)
		rowBox(normalRow, "NormalMax", "e.g. 0.10", 0.35, false)
		heading("Lucky chance (during the Lucky window)")
		local luckyRow = row()
		rowLabel(luckyRow, "Min", 0.15)
		rowBox(luckyRow, "LuckyMin", "e.g. 0.10", 0.35, false)
		rowLabel(luckyRow, "Max", 0.15)
		rowBox(luckyRow, "LuckyMax", "e.g. 0.30", 0.35, false)
		heading("Lucky window (minutes)")
		local windowRow = row()
		rowLabel(windowRow, "Every", 0.15)
		rowBox(windowRow, "LuckyEveryMinutes", "e.g. 120", 0.35, true)
		rowLabel(windowRow, "Lasts", 0.15)
		rowBox(windowRow, "LuckyLastsMinutes", "e.g. 10", 0.35, true)

		local saveRow = row()
		rowButton(saveRow, "Save for all servers", GOOD_COLOR, 0.5).Activated:Connect(function()
			local payload: { [string]: number? } = {}
			for _, key in DROP_FIELDS do
				payload[key] = tonumber(texts[key])
			end
			setDropRatesRemote:FireServer(payload)
		end)
		confirmButton(rowButton(saveRow, "Reset to defaults", DANGER_COLOR, 0.5), function()
			-- Let every field follow the defaults the server sends back.
			for _, key in DROP_FIELDS do
				texts[key] = nil
			end
			setDropRatesRemote:FireServer("Reset")
		end)
	end

	local function typeLabel(eventType: string): string
		local info = EventConfig.TypeInfo[eventType]
		return if info then info.Icon .. " " .. info.Label else eventType
	end

	-- The settings the server needs for the chosen event type.
	local function eventSettings(eventType: string): { [string]: unknown }
		if eventType == "XpBoost" then
			return { Multiplier = EventConfig.XpMultipliers[picks.XpMultIndex] }
		elseif eventType == "BossSpawn" then
			local location = EventConfig.Locations[picks.SpawnLocationIndex]
			return {
				BossId = EventConfig.BossLookIds[picks.SpawnBossIndex],
				LocationId = if location then location.Id else "",
				Quantity = picks.SpawnQuantityIndex,
			}
		elseif eventType == "BossDrop" then
			return {
				BossId = DROP_BOSS_CHOICES[picks.DropBossIndex],
				ItemKey = EventConfig.DropItems[picks.DropItemIndex],
				ChancePercent = tonumber(texts.DropChance) or 0,
			}
		elseif eventType == "EggHunt" then
			return {
				EggRarity = PetConfig.Rarities[picks.EggHuntRarityIndex],
				IntervalMinutes = EventConfig.EggHuntIntervals[picks.EggHuntIntervalIndex],
				MaxEggs = picks.EggHuntMaxIndex,
			}
		end
		local ids: { string } = {}
		if picks.DiscountScopeIndex == 2 then
			for _, hammer in SALE_HAMMERS do
				if saleHammers[hammer.Id] then
					table.insert(ids, hammer.Id)
				end
			end
		end
		return { Percent = tonumber(texts.Discount) or 0, HammerIds = ids }
	end

	local function stringIn(config: { [string]: unknown }, key: string): string
		local value = config[key]
		return if typeof(value) == "string" then value else ""
	end

	local function numberIn(config: { [string]: unknown }, key: string): number
		local value = config[key]
		return if typeof(value) == "number" then value else 0
	end

	-- Fills the event form from an existing event, to edit it.
	local function loadForEdit(event: AdminEvent): ()
		editingId = event.Id
		local config = event.Config
		picks.EventTypeIndex = table.find(EventConfig.Types, event.Type) or 1
		texts.EventName = event.Name
		picks.EventTimingIndex = 2
		-- A running event keeps its start (the server ignores a new one).
		texts.EventStart = LocalTime.format(math.max(event.StartTime, os.time()))
		texts.EventEnd = LocalTime.format(event.EndTime)
		if event.Type == "XpBoost" then
			picks.XpMultIndex = table.find(
				EventConfig.XpMultipliers,
				numberIn(config, "Multiplier")
			) or 1
		elseif event.Type == "BossSpawn" then
			picks.SpawnBossIndex = table.find(EventConfig.BossLookIds, stringIn(config, "BossId"))
				or 1
			for index, location in EventConfig.Locations do
				if location.Id == config.LocationId then
					picks.SpawnLocationIndex = index
				end
			end
			picks.SpawnQuantityIndex = math.max(1, numberIn(config, "Quantity"))
		elseif event.Type == "BossDrop" then
			picks.DropBossIndex = table.find(DROP_BOSS_CHOICES, stringIn(config, "BossId")) or 1
			picks.DropItemIndex = table.find(EventConfig.DropItems, stringIn(config, "ItemKey"))
				or 1
			texts.DropChance = tostring(numberIn(config, "ChancePercent"))
		elseif event.Type == "StoreDiscount" then
			texts.Discount = tostring(numberIn(config, "Percent"))
			table.clear(saleHammers)
			local ids = config.HammerIds
			local count = 0
			if typeof(ids) == "table" then
				for _, id in ids :: { unknown } do
					if typeof(id) == "string" then
						saleHammers[id] = true
						count += 1
					end
				end
			end
			picks.DiscountScopeIndex = if count > 0 then 2 else 1
		elseif event.Type == "EggHunt" then
			picks.EggHuntRarityIndex = table.find(PetConfig.Rarities, stringIn(config, "EggRarity"))
				or 1
			picks.EggHuntIntervalIndex = table.find(
				EventConfig.EggHuntIntervals,
				numberIn(config, "IntervalMinutes")
			) or 1
			picks.EggHuntMaxIndex = math.max(1, numberIn(config, "MaxEggs"))
		end
		render()
	end

	local function eventsPage(current: State): ()
		note(
			"Events run in every server and start and end on their own. Several can run at once: the highest XP multiplier and the biggest discount apply (they never multiply together). Robux store prices are set in the Creator Hub, so sales are for Hammer Shop coin prices.",
			60
		)
		local now = Workspace:GetServerTimeNow()

		heading(
			string.format("Running and scheduled (%d / %d)", #current.Events, EventConfig.MaxEvents)
		)
		if #current.Events == 0 then
			note("None right now. Create one below.")
		end
		for _, event in current.Events do
			local eventRow = row()
			rowLabel(
				eventRow,
				string.format(
					"%s  [%s]",
					event.Name,
					if event.Active then "ACTIVE" else "SCHEDULED"
				),
				0.72
			)
			rowButton(eventRow, "Edit", TAB_ACTIVE_COLOR, 0.28).Activated:Connect(function()
				loadForEdit(event)
			end)
			local actions = row()
			if not event.Active then
				rowButton(actions, "Start now", GOOD_COLOR, 0.34).Activated:Connect(function()
					askConfirm(string.format("Start %q now?", event.Name), function()
						eventsRemote:FireServer({ Action = "StartNow", EventId = event.Id })
					end)
				end)
			end
			rowButton(actions, if event.Active then "Stop" else "Cancel", DANGER_COLOR, 0.33).Activated:Connect(
				function()
					askConfirm(
						if event.Active
							then string.format("Stop %q now?", event.Name)
							else string.format("Cancel %q?", event.Name),
						function()
							eventsRemote:FireServer({ Action = "Stop", EventId = event.Id })
						end
					)
				end
			)
			rowButton(actions, "Force remove", DANGER_COLOR, 0.33).Activated:Connect(function()
				askConfirm(
					string.format(
						"Force remove %q? It stops at once (bosses, eggs, drops, prices, XP), even if saving fails.",
						event.Name
					),
					function()
						eventsRemote:FireServer({ Action = "ForceRemove", EventId = event.Id })
					end
				)
			end)
			note(
				string.format(
					"%s: %s. %s to %s (your time); %s. By %s.",
					typeLabel(event.Type),
					event.Summary,
					LocalTime.format(event.StartTime),
					LocalTime.format(event.EndTime),
					if event.Active
						then "ends in " .. EventRules.countdown(event.EndTime - now)
						else "starts in " .. EventRules.countdown(event.StartTime - now),
					event.CreatedByName
				)
			)
		end

		heading(if editingId then "Edit event" else "Create event")
		if editingId then
			note(
				"Editing: change what you need and SAVE CHANGES. A running event keeps its start time."
			)
		end
		local typeRow = row()
		rowLabel(typeRow, "Type", 0.25)
		cycler(typeRow, "EventTypeIndex", #EventConfig.Types, function(index)
			return typeLabel(EventConfig.Types[index])
		end, 0.75, render)
		local eventType = EventConfig.Types[picks.EventTypeIndex]

		local nameRow = row()
		rowLabel(nameRow, "Name", 0.25)
		rowBox(nameRow, "EventName", "Optional, e.g. Weekend XP Boost", 0.75, false)

		local whenRow = row()
		rowLabel(whenRow, "When", 0.25)
		cycler(whenRow, "EventTimingIndex", #EVENT_TIMING, function(index)
			return EVENT_TIMING[index]
		end, 0.75, render)
		local scheduled = picks.EventTimingIndex == 2
		if scheduled then
			local startRow = row()
			rowLabel(startRow, "Start", 0.25)
			rowBox(startRow, "EventStart", LocalTime.FORMAT_HINT .. " (your time)", 0.75, false)
			local endRow = row()
			rowLabel(endRow, "End", 0.25)
			rowBox(endRow, "EventEnd", LocalTime.FORMAT_HINT .. " (your time)", 0.75, false)
		else
			local durationRow = row()
			rowLabel(durationRow, "For", 0.25)
			cycler(durationRow, "EventDurationIndex", #EventConfig.Durations, function(index)
				return EventConfig.Durations[index].Label
			end, 0.75, render)
		end

		if eventType == "XpBoost" then
			local multRow = row()
			rowLabel(multRow, "XP", 0.25)
			cycler(multRow, "XpMultIndex", #EventConfig.XpMultipliers, function(index)
				return string.format(
					"%sx XP from bosses",
					tostring(EventConfig.XpMultipliers[index])
				)
			end, 0.75, render)
		elseif eventType == "BossSpawn" then
			local bossRow = row()
			rowLabel(bossRow, "Boss", 0.25)
			cycler(bossRow, "SpawnBossIndex", #EventConfig.BossLookIds, function(index)
				return bossName(EventConfig.BossLookIds[index])
			end, 0.75, render)
			local locationRow = row()
			rowLabel(locationRow, "Where", 0.25)
			cycler(locationRow, "SpawnLocationIndex", #EventConfig.Locations, function(index)
				return EventConfig.Locations[index].Label
			end, 0.75, render)
			local quantityRow = row()
			rowLabel(quantityRow, "How many", 0.25)
			cycler(quantityRow, "SpawnQuantityIndex", EventConfig.MaxBossQuantity, function(index)
				return tostring(index)
			end, 0.75, render)
			note(
				"Event bosses copy the office boss (HP, rewards, look), are open to everyone and vanish when the event ends."
			)
		elseif eventType == "BossDrop" then
			local scopeRow = row()
			rowLabel(scopeRow, "From", 0.25)
			cycler(scopeRow, "DropBossIndex", #DROP_BOSS_CHOICES, function(index)
				local bossId = DROP_BOSS_CHOICES[index]
				return if bossId == EventRules.ALL_BOSSES then "All bosses" else bossName(bossId)
			end, 0.75, render)
			local itemRow = row()
			rowLabel(itemRow, "Drops", 0.25)
			cycler(itemRow, "DropItemIndex", #EventConfig.DropItems, function(index)
				local product = StoreConfig.ByKey[EventConfig.DropItems[index]]
				return if product then BagRules.itemText(product) else "-"
			end, 0.75, render)
			local chanceRow = row()
			rowLabel(chanceRow, "Chance %", 0.25)
			rowBox(
				chanceRow,
				"DropChance",
				string.format(
					"%d to %d",
					EventConfig.MinDropChancePercent,
					EventConfig.MaxDropChancePercent
				),
				0.75,
				true
			)
			note("Rolled once per qualifying player (10% of the boss's HP) per defeat.")
		elseif eventType == "EggHunt" then
			local rarityRow = row()
			rowLabel(rarityRow, "Egg", 0.25)
			cycler(rarityRow, "EggHuntRarityIndex", #PetConfig.Rarities, function(index)
				return PetConfig.Rarities[index] .. " Egg"
			end, 0.75, render)
			local intervalRow = row()
			rowLabel(intervalRow, "Every", 0.25)
			cycler(
				intervalRow,
				"EggHuntIntervalIndex",
				#EventConfig.EggHuntIntervals,
				function(index)
					return string.format("%d minutes", EventConfig.EggHuntIntervals[index])
				end,
				0.75,
				render
			)
			local maxRow = row()
			rowLabel(maxRow, "At once", 0.25)
			cycler(maxRow, "EggHuntMaxIndex", EventConfig.MaxEggHuntEggs, function(index)
				return string.format("up to %d eggs", index)
			end, 0.75, render)
			note(
				"Eggs appear at the outdoor egg spots (no announcement per egg: the event's start notice tells players). The first player to claim each egg gets it; unclaimed eggs vanish when the hunt ends."
			)
		else
			local percentRow = row()
			rowLabel(percentRow, "% off", 0.25)
			rowBox(
				percentRow,
				"Discount",
				string.format(
					"%d to %d",
					EventConfig.MinDiscountPercent,
					EventConfig.MaxDiscountPercent
				),
				0.75,
				true
			)
			local scopeRow = row()
			rowLabel(scopeRow, "On", 0.25)
			cycler(scopeRow, "DiscountScopeIndex", #DISCOUNT_SCOPES, function(index)
				return DISCOUNT_SCOPES[index]
			end, 0.75, render)
			if picks.DiscountScopeIndex == 2 then
				local grid = PanelKit.grid(container, 160, PanelKit.ROW_HEIGHT)
				for _, hammer in SALE_HAMMERS do
					local on = saleHammers[hammer.Id] == true
					local toggle = PanelKit.button(
						grid,
						(if on then "[x] " else "[ ] ") .. hammer.DisplayName,
						if on then GOOD_COLOR else MUTED_COLOR
					)
					toggle.Activated:Connect(function()
						saleHammers[hammer.Id] = not on
						render()
					end)
				end
			end
		end

		local timeError = note("")
		timeError.TextColor3 = PanelKit.Colors.Danger
		local startRow = row()
		local saveLabel = if editingId
			then "SAVE CHANGES"
			elseif scheduled then "SCHEDULE EVENT"
			else "START EVENT"
		rowButton(startRow, saveLabel, GOOD_COLOR, if editingId then 0.6 else 1).Activated:Connect(
			function()
				local payload: { [string]: unknown } = {
					Action = if editingId then "Update" else "Create",
					EventId = editingId,
					Type = eventType,
					Name = texts.EventName,
					Config = eventSettings(eventType),
				}
				if scheduled then
					local startsAt = LocalTime.parse(texts.EventStart or "")
					local endsAt = LocalTime.parse(texts.EventEnd or "")
					if startsAt == nil or endsAt == nil then
						timeError.Text = "Use " .. LocalTime.FORMAT_HINT .. " for both times."
						return
					end
					payload.StartsAt = startsAt
					payload.EndsAt = endsAt
				else
					payload.DurationSeconds =
						EventConfig.Durations[picks.EventDurationIndex].Seconds
				end
				timeError.Text = ""
				eventsRemote:FireServer(payload)
				editingId = nil
			end
		)
		if editingId then
			rowButton(startRow, "Cancel edit", MUTED_COLOR, 0.4).Activated:Connect(function()
				editingId = nil
				render()
			end)
		end

		heading("World eggs")
		note(
			string.format(
				"An egg (Common or Rare) appears outside on its own every %d hours while none is out. Next one: %s (your time). Eggs out in this server now: %d. Players find it from an announcement; the first to claim it gets it.",
				PetConfig.WorldEggIntervalSeconds // 3600,
				if current.NextWorldEggAt > 0 then LocalTime.format(current.NextWorldEggAt) else "-",
				current.WorldEggs
			)
		)
		local eggRow = row()
		rowLabel(eggRow, "Rarity", 0.25)
		cycler(eggRow, "EggRarityIndex", #PetConfig.Rarities, function(index)
			return PetConfig.Rarities[index] .. " Egg"
		end, 0.75, render)
		local spawnRow = row()
		rowButton(spawnRow, "SPAWN EGG NOW (this server)", GOOD_COLOR, 1).Activated:Connect(
			function()
				spawnEggRemote:FireServer(PetConfig.Rarities[picks.EggRarityIndex])
			end
		)

		heading("Event history")
		if #current.EventHistory == 0 then
			note("No events have ended yet.")
		end
		for _, entry in current.EventHistory do
			local status = if entry.Status ~= ""
				then entry.Status
				elseif entry.StoppedByName ~= "" then "Stopped"
				else "Completed"
			local minutes = math.max(0, math.floor((entry.EndTime - entry.StartTime) / 60))
			local entryRow = row()
			rowLabel(entryRow, string.format("%s  [%s]", entry.Name, string.upper(status)), 0.72)
			rowButton(entryRow, "Delete", DANGER_COLOR, 0.28).Activated:Connect(function()
				askConfirm(string.format("Delete %q from the history?", entry.Name), function()
					eventsRemote:FireServer({ Action = "DeleteHistory", EventId = entry.Id })
				end)
			end)
			note(
				string.format(
					"%s: %s. Started %s, ended %s (ran %d min%s). Created by %s.%s",
					typeLabel(entry.Type),
					entry.Summary,
					LocalTime.format(entry.StartTime),
					LocalTime.format(entry.EndTime),
					minutes,
					if entry.PlannedEndTime > 0
						then ", planned to end " .. LocalTime.format(entry.PlannedEndTime)
						else "",
					entry.CreatedByName,
					if entry.StoppedByName ~= ""
						then string.format(
							" %s by %s at %s.",
							status,
							entry.StoppedByName,
							LocalTime.format(entry.EndTime)
						)
						else ""
				)
			)
		end
	end

	local function rewardKeys(kind: string): { Choice }
		local keys: { Choice } = {}
		if kind == "Item" then
			for _, product in StoreConfig.Products do
				table.insert(keys, { Key = product.Key, Text = BagRules.itemText(product) })
			end
		elseif kind == "Hammer" then
			for _, hammer in SALE_HAMMERS do
				table.insert(keys, { Key = hammer.Id, Text = hammer.DisplayName })
			end
		elseif kind == "Pet" then
			for _, species in PetConfig.Species do
				table.insert(keys, {
					Key = species.Id,
					Text = species.Emoji .. " " .. species.Name .. " (" .. species.Rarity .. ")",
				})
			end
		end
		return keys
	end

	local function rewardsPage(): ()
		note(
			"Give a player in this server something the game already has. Every reward (and any failure) is saved in the admin log and in the player's history."
		)
		local others = Players:GetPlayers()
		table.sort(others, function(a, b)
			return a.DisplayName < b.DisplayName
		end)
		local index = 1
		for i, other in others do
			if other.UserId == rewardUserId then
				index = i
			end
		end
		local target = others[index]
		rewardUserId = if target then target.UserId else 0
		picks.RewardTarget = index

		heading("Who")
		local whoRow = row()
		cycler(
			whoRow,
			"RewardTarget",
			#others,
			function(i)
				local p = others[i]
				return if p then string.format("%s (@%s)", p.DisplayName, p.Name) else "-"
			end,
			1,
			function()
				local p = others[picks.RewardTarget]
				rewardUserId = if p then p.UserId else 0
				render()
			end
		)

		heading("What")
		local kindRow = row()
		rowLabel(kindRow, "Reward", 0.25)
		cycler(
			kindRow,
			"RewardKindIndex",
			#REWARD_KINDS,
			function(i)
				return REWARD_KINDS[i].Text
			end,
			0.75,
			function()
				picks.RewardKeyIndex = 1
				render()
			end
		)
		local kind = REWARD_KINDS[picks.RewardKindIndex].Key
		local keys = rewardKeys(kind)
		if #keys > 0 then
			local keyRow = row()
			rowLabel(keyRow, "Which", 0.25)
			cycler(keyRow, "RewardKeyIndex", #keys, function(i)
				return keys[i].Text
			end, 0.75, render)
		end
		if kind ~= "Hammer" and kind ~= "Pet" then
			local amountRow = row()
			rowLabel(amountRow, "Amount", 0.25)
			rowBox(amountRow, "RewardAmount", "e.g. 500", 0.75, true)
		end
		local reasonRow = row()
		rowLabel(reasonRow, "Reason", 0.25)
		rowBox(reasonRow, "RewardReason", "Optional, e.g. Event compensation", 0.75, false)

		local giveRow = row()
		rowButton(giveRow, "GIVE REWARD", GOOD_COLOR, 1).Activated:Connect(function()
			local who = Players:GetPlayerByUserId(rewardUserId)
			if who == nil then
				return
			end
			local key = if #keys > 0 then keys[picks.RewardKeyIndex] else nil
			local amount = tonumber(texts.RewardAmount) or 0
			local what = if kind == "Hammer" or kind == "Pet"
				then (if key then key.Text else kind)
				else string.format(
					"%d x %s",
					amount,
					if key then key.Text else REWARD_KINDS[picks.RewardKindIndex].Text
				)
			askConfirm(string.format("Give %s to %s?", what, who.DisplayName), function()
				rewardRemote:FireServer({
					UserId = rewardUserId,
					Kind = kind,
					Key = if key then key.Key else nil,
					Amount = amount,
					Reason = texts.RewardReason,
				})
			end)
		end)
	end

	local function requestHistory(page: number): ()
		if HISTORY_MODES[picks.HistoryModeIndex] == "Admin" then
			historyRemote:FireServer({
				Mode = "Admin",
				DaysAgo = picks.HistoryDayIndex - 1,
				Action = HISTORY_ACTIONS[picks.HistoryActionIndex].Key,
				Page = page,
			})
		else
			local payload: { [string]: unknown } = {
				Mode = "Player",
				Type = HISTORY_TYPES[picks.HistoryTypeIndex].Key,
				Days = HISTORY_DAYS[picks.HistoryDaysIndex].Days,
				Page = page,
			}
			if (texts.HistoryUsername or "") ~= "" then
				payload.Username = texts.HistoryUsername
			else
				payload.UserId = historyUserId
			end
			historyRemote:FireServer(payload)
		end
	end

	local function historyPage(): ()
		heading("Show")
		local modeRow = row()
		cycler(
			modeRow,
			"HistoryModeIndex",
			#HISTORY_MODES,
			function(i)
				return if HISTORY_MODES[i] == "Admin"
					then "Admin log (all admin actions)"
					else "A player's history"
			end,
			1,
			function()
				historyView = nil
				render()
			end
		)
		if HISTORY_MODES[picks.HistoryModeIndex] == "Admin" then
			local dayRow = row()
			rowLabel(dayRow, "Day", 0.25)
			cycler(dayRow, "HistoryDayIndex", 8, function(i)
				return if i == 1
					then "Today (UTC)"
					elseif i == 2 then "Yesterday"
					else string.format("%d days ago", i - 1)
			end, 0.75, render)
			local actionRow = row()
			rowLabel(actionRow, "Action", 0.25)
			cycler(actionRow, "HistoryActionIndex", #HISTORY_ACTIONS, function(i)
				return HISTORY_ACTIONS[i].Text
			end, 0.75, render)
		else
			local players = Players:GetPlayers()
			table.sort(players, function(a, b)
				return a.DisplayName < b.DisplayName
			end)
			local index = 1
			for i, other in players do
				if other.UserId == historyUserId then
					index = i
				end
			end
			historyUserId = if players[index] then players[index].UserId else localPlayer.UserId
			picks.HistoryPlayer = index
			local playerRow = row()
			cycler(
				playerRow,
				"HistoryPlayer",
				#players,
				function(i)
					local p = players[i]
					return if p then string.format("%s (@%s)", p.DisplayName, p.Name) else "-"
				end,
				1,
				function()
					local p = players[picks.HistoryPlayer]
					historyUserId = if p then p.UserId else localPlayer.UserId
					render()
				end
			)
			local nameRow = row()
			rowBox(nameRow, "HistoryUsername", "...or any username (used when filled in)", 1, false)
			local typeRow = row()
			rowLabel(typeRow, "Type", 0.25)
			cycler(typeRow, "HistoryTypeIndex", #HISTORY_TYPES, function(i)
				return HISTORY_TYPES[i].Text
			end, 0.75, render)
			local daysRow = row()
			rowLabel(daysRow, "Period", 0.25)
			cycler(daysRow, "HistoryDaysIndex", #HISTORY_DAYS, function(i)
				return HISTORY_DAYS[i].Text
			end, 0.75, render)
		end
		local loadRow = row()
		rowButton(loadRow, "LOAD", TAB_ACTIVE_COLOR, 1).Activated:Connect(function()
			requestHistory(1)
		end)

		local view = historyView
		heading(if view then string.format("Results (page %d)", view.Page) else "Results")
		if view == nil then
			note("Pick what to show and press LOAD. 20 entries per page, newest first.")
			return
		end
		if #view.Entries == 0 then
			note("Nothing found.")
		end
		for _, entry in view.Entries do
			local who = if entry.By ~= "" then "Admin " .. entry.By else ""
			local target = if entry.TargetName ~= ""
				then string.format(
					"%s%s (%d)",
					if who ~= "" then " -> " else "",
					entry.TargetName,
					entry.TargetUserId
				)
				else ""
			note(
				string.format(
					"%s  ·  %s / %s  ·  %s\n%s%s%s%s",
					LocalTime.format(entry.At),
					entry.Type,
					entry.Action,
					string.upper(entry.Status),
					who,
					target,
					if who ~= "" or target ~= "" then "\n" else "",
					entry.Text
				)
			)
		end
		local pageRow = row()
		local previous = rowButton(pageRow, "< Newer", TAB_COLOR, 0.5)
		local following = rowButton(pageRow, "Older >", TAB_COLOR, 0.5)
		if view.Page <= 1 then
			PanelKit.setDisabled(previous, true)
		else
			previous.Activated:Connect(function()
				requestHistory(view.Page - 1)
			end)
		end
		if not view.HasMore then
			PanelKit.setDisabled(following, true)
		else
			following.Activated:Connect(function()
				requestHistory(view.Page + 1)
			end)
		end
	end

	local function announcePage(): ()
		note(
			string.format(
				"Shows a message on the screen of everyone in THIS server. Up to %d characters, one line, checked by Roblox's text filter. One announcement every few seconds.",
				AnnouncementConfig.MaxLength
			),
			44
		)
		heading("Server announcement")
		local messageRow = PanelKit.row(container, 88)
		local box = rowBox(messageRow, "Announcement", "Type announcement here...", 1, false)
		box.TextWrapped = true
		box.MultiLine = false
		box.TextYAlignment = Enum.TextYAlignment.Top
		local counter = note("")
		local function count(): ()
			local length = utf8.len(texts.Announcement or "") or 0
			counter.Text = string.format("%d / %d", length, AnnouncementConfig.MaxLength)
			counter.TextColor3 = if length > AnnouncementConfig.MaxLength
				then PanelKit.Colors.Danger
				else PanelKit.Colors.Muted
		end
		box:GetPropertyChangedSignal("Text"):Connect(count)
		count()
		local durationRow = row()
		rowLabel(durationRow, "Show for", 0.3)
		cycler(durationRow, "AnnounceIndex", #AnnouncementConfig.Durations, function(index)
			return string.format("%d sec", AnnouncementConfig.Durations[index])
		end, 0.7, render)
		local sendRow = row()
		rowButton(sendRow, "SEND ANNOUNCEMENT", GOOD_COLOR, 1).Activated:Connect(function()
			local message = texts.Announcement or ""
			if string.match(message, "%S") == nil then
				return
			end
			announceRemote:FireServer(message, AnnouncementConfig.Durations[picks.AnnounceIndex])
			texts.Announcement = ""
			box.Text = ""
		end)
	end

	local function moderationPage(current: State): ()
		note(
			"Bans apply to every server and to the player's alt accounts, and kick them right away. They only work in a published game. Every action is logged.",
			44
		)
		local others: { Player } = {}
		for _, player in Players:GetPlayers() do
			if player ~= localPlayer then
				table.insert(others, player)
			end
		end
		table.sort(others, function(a, b)
			return a.DisplayName < b.DisplayName
		end)

		heading("Player in this server")
		local pickRow = row()
		local index = 1
		for i, player in others do
			if player.UserId == modUserId then
				index = i
			end
		end
		modUserId = if others[index] then others[index].UserId else 0
		local pick = { Index = index }
		local previous = rowButton(pickRow, "<", TAB_COLOR, 0)
		previous.Size = UDim2.new(0, MIN_TOUCH_SIZE, 1, 0)
		local shown = rowLabel(
			pickRow,
			if others[index]
				then string.format("%s (@%s)", others[index].DisplayName, others[index].Name)
				else "No other players here",
			0.8
		)
		shown.Size = UDim2.new(1, -(2 * MIN_TOUCH_SIZE + 16), 1, 0)
		shown.TextXAlignment = Enum.TextXAlignment.Center
		local following = rowButton(pickRow, ">", TAB_COLOR, 0)
		following.Size = UDim2.new(0, MIN_TOUCH_SIZE, 1, 0)
		local function step(delta: number): ()
			if #others == 0 then
				return
			end
			pick.Index = (pick.Index - 1 + delta) % #others + 1
			modUserId = others[pick.Index].UserId
			render()
		end
		previous.Activated:Connect(function()
			step(-1)
		end)
		following.Activated:Connect(function()
			step(1)
		end)

		heading("...or a username (used when filled in)")
		local nameRow = row()
		rowBox(nameRow, "Username", "Roblox username", 1, false)

		heading("Ban")
		local durationRow = row()
		rowLabel(durationRow, "Length", 0.2)
		cycler(durationRow, "DurationIndex", #current.BanDurations, function(i)
			return current.BanDurations[i].Text
		end, 0.6, render)
		local reasonRow = row()
		rowLabel(reasonRow, "Reason", 0.2)
		cycler(reasonRow, "ReasonIndex", #current.BanReasons, function(i)
			return current.BanReasons[i].Text
		end, 0.6, render)
		local noteRow = row()
		rowBox(noteRow, "Note", "Private note (optional, admins only)", 1, false)

		local function targetPayload(action: string): { [string]: any }
			local payload: { [string]: any } = { Action = action }
			if texts.Username ~= "" then
				payload.Username = texts.Username
			elseif modUserId ~= 0 then
				payload.UserId = modUserId
			end
			return payload
		end
		local actionRow = row()
		confirmButton(rowButton(actionRow, "Ban / suspend", DANGER_COLOR, 0.5), function()
			local payload = targetPayload("Ban")
			local duration = current.BanDurations[picks.DurationIndex]
			local reason = current.BanReasons[picks.ReasonIndex]
			payload.Duration = if duration then duration.Key else nil
			payload.Reason = if reason then reason.Key else nil
			payload.Note = texts.Note
			moderateRemote:FireServer(payload)
		end)
		confirmButton(rowButton(actionRow, "Unban", GOOD_COLOR, 0.5), function()
			moderateRemote:FireServer(targetPayload("Unban"))
		end)
	end

	local lastTab: string? = nil

	local function canOpenNow(): boolean
		local current = state
		return current ~= nil and current.IsAdmin
	end

	-- Rebuilds the open page (only while the window is open). Keeps the scroll
	-- position when the same page is redrawn after a server update.
	function render(): ()
		local current = state
		local isAdmin = current ~= nil and current.IsAdmin
		isAdminNow = isAdmin
		open.Visible = isAdmin
		if not isAdmin then
			window:close()
			return
		end
		if not window:isOpen() then
			return
		end
		local scroll = if lastTab == activeTab then list.CanvasPosition else Vector2.zero
		window:clear()
		container = list
		window:selectTab(activeTab)
		local page = current :: State
		if activeTab == "Dashboard" then
			dashboardPage(page)
		elseif activeTab == "Players" then
			playersPage(page)
		elseif activeTab == "Bosses" then
			bossesPage(page)
		elseif activeTab == "Events" then
			eventsPage(page)
		elseif activeTab == "Drops" then
			dropsPage(page)
		elseif activeTab == "Announce" then
			announcePage()
		elseif activeTab == "Rewards" then
			rewardsPage()
		elseif activeTab == "History" then
			historyPage()
		else
			moderationPage(page)
		end
		lastTab = activeTab
		task.defer(function()
			list.CanvasPosition = scroll
		end)
	end

	openPanel = function()
		if canOpenNow() then
			window:open()
		end
	end
	window:setTabs(TABS, function(id: string)
		activeTab = id
		render()
	end)
	window:onOpen(function()
		task.defer(render)
	end)

	stateRemote.OnClientEvent:Connect(function(payload: unknown)
		local parsed = parseState(payload)
		if parsed then
			state = parsed
			local rates = parsed.DropRates
			if rates then
				local values = rates :: { [string]: number }
				for _, key in DROP_FIELDS do
					local text = string.format("%g", values[key])
					if texts[key] == nil or texts[key] == serverDropTexts[key] then
						texts[key] = text
					end
					serverDropTexts[key] = text
				end
			end
			render()
		end
	end)
	-- History pages the server sends back (Admin.History requests).
	historyResultRemote.OnClientEvent:Connect(function(payload: unknown)
		if typeof(payload) ~= "table" then
			return
		end
		local data = payload :: { [string]: unknown }
		local entries: { HistoryLine } = {}
		if typeof(data.Entries) == "table" then
			for _, raw in data.Entries :: { unknown } do
				if typeof(raw) == "table" then
					local entry = raw :: { [string]: unknown }
					table.insert(entries, {
						At = numberField(entry, "At"),
						Type = stringField(entry, "Type"),
						Action = stringField(entry, "Action"),
						Text = stringField(entry, "Text"),
						Status = stringField(entry, "Status"),
						By = stringField(entry, "By"),
						TargetName = stringField(entry, "TargetName"),
						TargetUserId = numberField(entry, "TargetUserId"),
					})
				end
			end
		end
		historyView = {
			Mode = stringField(data, "Mode"),
			Page = math.max(1, numberField(data, "Page")),
			HasMore = data.HasMore == true,
			Entries = entries,
		}
		if activeTab == "History" then
			render()
		end
	end)

	-- Player pickers and the dashboard follow who is in the server.
	Players.PlayerAdded:Connect(function()
		render()
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(render)
	end)

	local canOpen = canOpenNow
	open.Activated:Connect(function()
		if canOpen() then
			window:toggle()
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.KeyCode == TOGGLE_KEY and canOpen() then
			window:toggle()
		end
	end)

	render()
end

-- Opens the panel (e.g. from the Player Panel). Display only: the server
-- still checks admin rights on every action.
function AdminController.open(): ()
	if openPanel then
		openPanel()
	end
end

-- Whether the server said this player is an admin (display only).
function AdminController.isAdmin(): boolean
	return isAdminNow
end

return AdminController
