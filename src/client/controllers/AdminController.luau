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
	  Drop Rates  office boss buff drop chances and the Lucky window (all servers)
	  Moderation  ban, suspend or unban by player or username
	Store opening hours stay in the Store panel's Admin tab.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Attributes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attributes"))
local BossConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BossConfig"))
local CustomBossConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("CustomBossConfig"))
local DropRateConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("DropRateConfig"))
local DropRateRules =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DropRateRules"))

local PanelKit = require(script.Parent.Parent.Lib.PanelKit)

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
	{ Id = "Drops", Label = "Drop Rates" },
	{ Id = "Moderation", Label = "Moderation" },
}
-- Desktop shortcut for admins.
local TOGGLE_KEY = Enum.KeyCode.F2
-- Cards that start folded up (Tab/Title), so long pages stay readable.
local START_COLLAPSED = {
	["Players/Unlock bosses"] = true,
	["Moderation/...or a username (used when filled in)"] = true,
}

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

type State = {
	IsAdmin: boolean,
	CustomBosses: { CustomBoss },
	DropRates: DropRateRules.Settings?,
	DamageOverrides: { [string]: number },
	MaxSetLevel: number,
	MaxSetDamage: number,
	BanDurations: { Choice },
	BanReasons: { Choice },
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
	}
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
	}
	local picks: { [string]: number } = {
		UnlockIndex = 1,
		LookIndex = 1,
		RespawnIndex = 1,
		DurationIndex = 1,
		ReasonIndex = 1,
	}
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

	-- The HUD button (only for admins), in the same place as before.
	local open = PanelKit.button(window.Gui, "Admin", ADMIN_COLOR)
	open.Name = "OpenAdmin"
	open.AnchorPoint = Vector2.new(1, 1)
	open.Position = UDim2.new(1, -16, 1, -240)
	open.Size = UDim2.fromOffset(140, MIN_TOUCH_SIZE + 4)
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
		line.TextSize = PanelKit.TEXT_SIZE
		line.TextColor3 = TEXT_COLOR
		line.TextWrapped = true
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
		elseif activeTab == "Drops" then
			dropsPage(page)
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
