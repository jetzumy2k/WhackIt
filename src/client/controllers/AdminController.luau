--!strict
--[[
	Admin panel (docs/ADMIN.md). Shown only when the server's Admin.State says
	this player is an admin, but that is display only: the server re-checks
	admin rights, bounds and targets on every request (AdminService).

	Tabs:
	  Players     set level, set damage, unlock / lock bosses for anyone here
	  Bosses      create a custom boss where you stand; move or delete them
	  Moderation  ban, suspend or unban by player or username
	Store opening hours stay in the Store panel's Admin tab.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BossConfig"))
local CustomBossConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("CustomBossConfig"))

local AdminController = {}

local PANEL_COLOR = Color3.fromRGB(30, 30, 40)
local ROW_COLOR = Color3.fromRGB(48, 48, 62)
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

local TABS = {
	{ Id = "Players", Label = "Players" },
	{ Id = "Bosses", Label = "Bosses" },
	{ Id = "Moderation", Label = "Moderation" },
}

type CustomBoss = {
	Id: string,
	Name: string,
	LookId: string,
	MaxHealth: number,
	ScoreReward: number,
	CoinReward: number,
}

type Choice = { Key: string, Text: string }

type State = {
	IsAdmin: boolean,
	CustomBosses: { CustomBoss },
	DamageOverrides: { [string]: number },
	MaxSetLevel: number,
	MaxSetDamage: number,
	BanDurations: { Choice },
	BanReasons: { Choice },
}

local localPlayer = Players.LocalPlayer

local function corner(parent: Instance): ()
	Instance.new("UICorner").Parent = parent
end

local function label(name: string, parent: Instance): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.TextColor3 = TEXT_COLOR
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Parent = parent
	return text
end

local function button(name: string, parent: Instance): TextButton
	local clickable = Instance.new("TextButton")
	clickable.Name = name
	clickable.TextColor3 = TEXT_COLOR
	clickable.Font = Enum.Font.FredokaOne
	clickable.TextScaled = true
	clickable.AutoButtonColor = true
	clickable.Parent = parent
	corner(clickable)
	return clickable
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
	local stateRemote = remote("State")

	local state: State? = nil
	local activeTab = "Players"
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
		DurationIndex = 1,
		ReasonIndex = 1,
	}
	local targetUserId = localPlayer.UserId
	local modUserId = 0

	local gui = Instance.new("ScreenGui")
	gui.Name = "Admin"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5

	local open = button("OpenAdmin", gui)
	open.Text = "Admin"
	open.BackgroundColor3 = ADMIN_COLOR
	open.AnchorPoint = Vector2.new(1, 1)
	open.Position = UDim2.new(1, -16, 1, -240)
	open.Size = UDim2.fromOffset(140, MIN_TOUCH_SIZE + 4)
	open.Visible = false

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.65, 0.78)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.Visible = false
	panel.Parent = gui
	corner(panel)
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MinSize = Vector2.new(320, 320)
	sizeLimit.MaxSize = Vector2.new(640, 600)
	sizeLimit.Parent = panel

	local title = label("Title", panel)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -90, 0, 34)
	title.Text = "Admin"

	local close = button("Close", panel)
	close.Text = "X"
	close.BackgroundColor3 = MUTED_COLOR
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 8)
	close.Size = UDim2.fromOffset(MIN_TOUCH_SIZE, MIN_TOUCH_SIZE)

	local tabBar = Instance.new("Frame")
	tabBar.Name = "Tabs"
	tabBar.BackgroundTransparency = 1
	tabBar.Position = UDim2.fromOffset(10, 56)
	tabBar.Size = UDim2.new(1, -20, 0, MIN_TOUCH_SIZE)
	tabBar.Parent = panel
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabBar

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(10, 108)
	list.Size = UDim2.new(1, -20, 1, -118)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = 6
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local function note(text: string, height: number): TextLabel
		local line = label("Note", list)
		line.LayoutOrder = nextOrder()
		line.Size = UDim2.new(1, 0, 0, height)
		line.TextScaled = false
		line.TextSize = 16
		line.TextWrapped = true
		line.TextYAlignment = Enum.TextYAlignment.Top
		line.TextTransparency = 0.15
		line.Text = text
		return line
	end

	local function heading(text: string): ()
		local line = label("Heading", list)
		line.LayoutOrder = nextOrder()
		line.Size = UDim2.new(1, 0, 0, 26)
		line.TextColor3 = Color3.fromRGB(255, 220, 120)
		line.Text = text
	end

	local function row(): Frame
		local frame = Instance.new("Frame")
		frame.Name = "Row"
		frame.LayoutOrder = nextOrder()
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.new(1, 0, 0, MIN_TOUCH_SIZE)
		frame.Parent = list
		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.Padding = UDim.new(0, 6)
		rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		rowLayout.Parent = frame
		return frame
	end

	local function rowButton(parent: Frame, text: string, color: Color3, width: number): TextButton
		local clickable = button("Button", parent)
		clickable.LayoutOrder = #parent:GetChildren()
		clickable.Text = text
		clickable.BackgroundColor3 = color
		clickable.Size = UDim2.new(width, -6, 1, 0)
		return clickable
	end

	local function rowLabel(parent: Frame, text: string, width: number): TextLabel
		local line = label("Label", parent)
		line.LayoutOrder = #parent:GetChildren()
		line.Size = UDim2.new(width, -6, 0.8, 0)
		line.Text = text
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
		box.Size = UDim2.new(width, -6, 1, 0)
		box.BackgroundColor3 = ROW_COLOR
		box.TextColor3 = TEXT_COLOR
		box.PlaceholderText = placeholder
		box.Font = Enum.Font.FredokaOne
		box.TextSize = 18
		box.ClearTextOnFocus = false
		box.Text = texts[key] or ""
		box.Parent = parent
		corner(box)
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
				"Fictional everyday annoyances only: no real people or groups. The boss appears where you stand, in every server. Each player who deals 10%% of its HP gets a random %d-minute store boost.",
				CustomBossConfig.BuffDropSeconds // 60
			),
			60
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
				string.format("%s  (%d HP, %s)", boss.Name, boss.MaxHealth, bossName(boss.LookId)),
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

	local tabButtons: { [string]: TextButton } = {}

	function render(): ()
		for _, child in list:GetChildren() do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
		order = 0
		local current = state
		open.Visible = current ~= nil and current.IsAdmin
		if current == nil or not current.IsAdmin then
			panel.Visible = false
			return
		end
		for id, tab in tabButtons do
			tab.BackgroundColor3 = if id == activeTab then TAB_ACTIVE_COLOR else TAB_COLOR
		end
		if activeTab == "Players" then
			playersPage(current)
		elseif activeTab == "Bosses" then
			bossesPage(current)
		else
			moderationPage(current)
		end
	end

	for tabOrder, tab in TABS do
		local tabButton = button(tab.Id, tabBar)
		tabButton.LayoutOrder = tabOrder
		tabButton.Text = tab.Label
		tabButton.Size = UDim2.fromScale(0.3, 1)
		tabButton.Activated:Connect(function()
			activeTab = tab.Id
			render()
		end)
		tabButtons[tab.Id] = tabButton
	end

	stateRemote.OnClientEvent:Connect(function(payload: unknown)
		local parsed = parseState(payload)
		if parsed then
			state = parsed
			render()
		end
	end)
	-- Player pickers follow who is in the server.
	Players.PlayerAdded:Connect(function()
		if panel.Visible then
			render()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		if panel.Visible then
			task.defer(render)
		end
	end)

	open.Activated:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			render()
		end
	end)
	close.Activated:Connect(function()
		panel.Visible = false
	end)

	render()
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

return AdminController
