--!strict
--[[
	Team boss missions on the client (docs/MISSIONS.md). Display and
	requests only: the server forms teams, runs the waves, counts hits and
	pays rewards (MissionService).

	  * Teams (Mission.Teams): a card with JOIN for each new team (unless
	    "Hide challenge notices" is on, or you're busy), and the Team
	    Missions window (from 🏢 Social): your team (Start for the leader,
	    Leave), the missions to open a team for, the open teams to join, the
	    rewards and today's rewarded missions.
	  * A run (Mission.State, the InMission attribute): a bar at the top with
	    the mission, the wave, the bosses left, the time left and everyone's
	    hits, and Leave (two taps).
	  * Mission.Result: a card with the result and what it paid.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Attributes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attributes"))
local MissionConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("MissionConfig"))
local QuestRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("QuestRules"))

local AnnouncementController = require(script.Parent.AnnouncementController)
local PanelKit = require(script.Parent.Parent.Lib.PanelKit)
local ProgressController = require(script.Parent.ProgressController)
local Responsive = require(script.Parent.Parent.Lib.Responsive)
local SettingsController = require(script.Parent.SettingsController)

local MissionController = {}

export type Member = { UserId: number, Name: string, Hits: number }

export type Team = {
	Id: string,
	MissionId: string,
	LeaderUserId: number,
	LeaderName: string,
	Members: { Member },
	ExpiresAt: number,
}

export type RunView = {
	MissionId: string,
	Phase: string,
	Wave: number,
	Waves: number,
	BossesLeft: number,
	BossesTotal: number,
	EndsAt: number,
	Members: { Member },
}

local C = PanelKit.Colors
local ACCENT = Color3.fromRGB(120, 170, 250)
local CARD_COLOR = Color3.fromRGB(26, 29, 41)
local MAX_NAME = 40

local localPlayer = Players.LocalPlayer
local remotes: Folder? = nil
local teamList: { Team } = {}
local freeRooms = 0
local run: RunView? = nil
local seen: { [string]: boolean } = {}
local openPanel: (() -> ())? = nil
local changedEvent = Instance.new("BindableEvent")

-- Fires when the teams or the run change.
MissionController.Changed = changedEvent.Event

local function remote(name: string): RemoteEvent
	local folder = remotes :: Folder
	local event = folder:WaitForChild(name)
	assert(event:IsA("RemoteEvent"), "Mission." .. name .. " must be a RemoteEvent")
	return event
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function text(value: unknown, fallback: string): string
	if typeof(value) == "string" and #value <= 200 and utf8.len(value) ~= nil then
		return value
	end
	return fallback
end

local function number(value: unknown, fallback: number): number
	return if typeof(value) == "number" and value == value then value else fallback
end

local function parseMembers(raw: unknown): { Member }
	local members: { Member } = {}
	if typeof(raw) ~= "table" then
		return members
	end
	for _, entry in raw :: { unknown } do
		if typeof(entry) == "table" and #members < MissionConfig.TeamMax then
			local data = entry :: { [string]: unknown }
			local userId = number(data.UserId, 0)
			if userId ~= 0 then -- not "> 0": Studio test players have negative ids
				table.insert(members, {
					UserId = userId,
					Name = string.sub(text(data.Name, "Player"), 1, MAX_NAME),
					Hits = math.max(0, math.floor(number(data.Hits, 0))),
				})
			end
		end
	end
	return members
end

local function inMission(): boolean
	local id = localPlayer:GetAttribute(Attributes.InMission)
	return typeof(id) == "string" and id ~= ""
end

local function inPickleball(): boolean
	local id = localPlayer:GetAttribute(Attributes.RecMatch)
	return typeof(id) == "string" and id ~= ""
end

local function isMine(team: Team): boolean
	for _, member in team.Members do
		if member.UserId == localPlayer.UserId then
			return true
		end
	end
	return false
end

function MissionController.mine(): Team?
	for _, team in teamList do
		if isMine(team) then
			return team
		end
	end
	return nil
end

function MissionController.teams(): { Team }
	return teamList
end

function MissionController.open(): ()
	if openPanel then
		openPanel()
	end
end

function MissionController.openTeam(missionId: string): ()
	remote("Open"):FireServer(missionId)
end

function MissionController.join(teamId: string): ()
	remote("Join"):FireServer(teamId)
end

function MissionController.leave(): ()
	remote("Leave"):FireServer()
end

function MissionController.begin(): ()
	remote("Begin"):FireServer()
end

local function rewardText(): string
	local parts = {
		string.format("%d coins", MissionConfig.Reward.Coins),
		string.format("%d XP", MissionConfig.Reward.Xp),
	}
	if MissionConfig.Reward.Supply then
		table.insert(parts, "an office supply")
	end
	table.insert(
		parts,
		string.format(
			"a %d%% chance of a Common Egg",
			math.floor(MissionConfig.Reward.EggChance * 100)
		)
	)
	return table.concat(parts, " · ")
end

-- Cards -------------------------------------------------------------------------

local function announce(team: Team): ()
	if
		SettingsController.get("HideChallenges")
		or inMission()
		or inPickleball()
		or MissionController.mine()
	then
		return
	end
	local mission = MissionConfig.ById[team.MissionId]
	if mission == nil then
		return
	end
	AnnouncementController.show({
		Title = "🤝 TEAM MISSION",
		Body = string.format(
			"%s needs a team for %s %s!",
			team.LeaderName,
			mission.Icon,
			mission.Name
		),
		Detail = string.format("%d of %d players", #team.Members, MissionConfig.TeamMax),
		Accent = ACCENT,
		Seconds = 10,
		ActionLabel = "JOIN",
		OnAction = function()
			MissionController.join(team.Id)
		end,
	})
end

local function onTeams(payload: unknown): ()
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	local list: { Team } = {}
	if typeof(data.Teams) == "table" then
		for _, entry in data.Teams :: { unknown } do
			if typeof(entry) == "table" and #list < 50 then
				local raw = entry :: { [string]: unknown }
				local id = text(raw.Id, "")
				local missionId = text(raw.MissionId, "")
				if id ~= "" and MissionConfig.ById[missionId] then
					table.insert(list, {
						Id = id,
						MissionId = missionId,
						LeaderUserId = number(raw.LeaderUserId, 0),
						LeaderName = string.sub(text(raw.LeaderName, "Player"), 1, MAX_NAME),
						Members = parseMembers(raw.Members),
						ExpiresAt = number(raw.ExpiresAt, 0),
					})
				end
			end
		end
	end
	teamList = list
	freeRooms = math.max(0, math.floor(number(data.FreeRooms, 0)))
	local current: { [string]: boolean } = {}
	for _, team in list do
		current[team.Id] = true
		if not seen[team.Id] then
			seen[team.Id] = true
			if team.LeaderUserId ~= localPlayer.UserId then
				announce(team)
			end
		end
	end
	for id in seen do
		if not current[id] then
			seen[id] = nil
		end
	end
	changedEvent:Fire()
end

local function onState(payload: unknown): ()
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	local missionId = text(data.MissionId, "")
	if MissionConfig.ById[missionId] == nil then
		return
	end
	run = {
		MissionId = missionId,
		Phase = text(data.Phase, ""),
		Wave = number(data.Wave, 0),
		Waves = number(data.Waves, 0),
		BossesLeft = number(data.BossesLeft, 0),
		BossesTotal = number(data.BossesTotal, 0),
		EndsAt = number(data.EndsAt, 0),
		Members = parseMembers(data.Members),
	}
	changedEvent:Fire()
end

local function onResult(payload: unknown): ()
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	local mission = MissionConfig.ById[text(data.MissionId, "")]
	local cleared = data.Cleared == true
	local detail: string
	if data.Rewarded == true then
		local parts = {
			string.format("+%d coins", number(data.Coins, 0)),
			string.format("+%d XP", number(data.Xp, 0)),
		}
		local supply = text(data.Supply, "")
		if supply ~= "" then
			table.insert(parts, supply .. " (office storage)")
		end
		if data.Egg == true then
			table.insert(parts, "a Common Egg (in your Bag)")
		end
		detail = table.concat(parts, " · ")
	elseif not cleared then
		detail = "No mission reward this time; the bosses you beat still paid as usual."
	elseif data.Counted ~= true then
		detail = string.format(
			"You landed %d hits: not enough to count for the mission reward.",
			number(data.Hits, 0)
		)
	else
		detail = string.format(
			"You've had today's %d rewarded missions; this one was for fun.",
			MissionConfig.DailyRewarded
		)
	end
	AnnouncementController.show({
		Title = if cleared then "🎉 MISSION CLEARED!" else "⏰ MISSION OVER",
		Body = (if mission then mission.Icon .. " " .. mission.Name .. ": " else "")
			.. text(data.Reason, ""),
		Detail = detail,
		Accent = if cleared then C.Heading else ACCENT,
		Celebrate = cleared,
		Seconds = 10,
	})
end

-- The bar during a run ---------------------------------------------------------------

local function buildHud(): (ScreenGui, () -> ())
	local gui = Instance.new("ScreenGui")
	gui.Name = "MissionHud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 4
	gui.Enabled = false

	local bar = Instance.new("Frame")
	bar.Name = "MissionBar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.BackgroundColor3 = CARD_COLOR
	bar.BackgroundTransparency = 0.08
	bar.AutomaticSize = Enum.AutomaticSize.Y
	bar.Parent = gui
	Instance.new("UICorner").Parent = bar
	local stroke = Instance.new("UIStroke")
	stroke.Color = ACCENT
	stroke.Thickness = 2
	stroke.Parent = bar
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = bar
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = bar

	local function line(order: number, font: Enum.Font, size: number, color: Color3): TextLabel
		local label = Instance.new("TextLabel")
		label.LayoutOrder = order
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, size + 6)
		label.Font = font
		label.TextColor3 = color
		label.TextWrapped = true
		label.Parent = bar
		Responsive.capText(label, size, 11)
		return label
	end
	local titleLine = line(1, Enum.Font.FredokaOne, 22, C.Text)
	local waveLine = line(2, Enum.Font.GothamBold, 16, C.Heading)
	local hitsLine = line(3, Enum.Font.GothamMedium, 14, C.Muted)

	local leave = PanelKit.button(gui, "Leave mission", C.Neutral)
	leave.Name = "LeaveMission"
	leave.AnchorPoint = Vector2.new(1, 0)
	local confirmUntil = 0
	leave.Activated:Connect(function()
		if os.clock() < confirmUntil then
			MissionController.leave()
			confirmUntil = 0
			leave.Text = "Leave mission"
			return
		end
		confirmUntil = os.clock() + 3
		leave.Text = "Sure? Tap again"
		task.delay(3, function()
			if os.clock() >= confirmUntil then
				leave.Text = "Leave mission"
			end
		end)
	end)

	Responsive.onChanged(function()
		local phone = Responsive.formFactor() == "Phone"
		bar.Position = UDim2.new(0.5, 0, 0, if phone then 8 else 12)
		bar.Size = UDim2.fromScale(if phone then 0.55 else 0.4, 0)
		leave.Position = UDim2.new(1, -16, 0, if phone then 64 else 120)
		leave.Size = UDim2.fromOffset(150, 40)
	end)

	local function refresh(): ()
		local current = run
		if current == nil or not inMission() then
			gui.Enabled = false
			return
		end
		gui.Enabled = true
		local mission = MissionConfig.ById[current.MissionId]
		titleLine.Text = if mission then mission.Icon .. " " .. mission.Name else "Team mission"
		local left = math.max(0, current.EndsAt - serverNow())
		local clock = string.format("%d:%02d left", left // 60, math.floor(left % 60))
		if current.Phase == "Starting" then
			waveLine.Text = "Get ready! " .. clock
		elseif current.Phase == "Between" then
			waveLine.Text = string.format(
				"Wave %d of %d cleared! Next wave coming… %s",
				current.Wave,
				current.Waves,
				clock
			)
		elseif current.Phase == "Cleared" then
			waveLine.Text = "🎉 Mission cleared!"
		elseif current.Phase == "Failed" then
			waveLine.Text = "⏰ Time's up"
		else
			waveLine.Text = string.format(
				"Wave %d of %d · Bosses left: %d of %d · %s",
				current.Wave,
				current.Waves,
				current.BossesLeft,
				current.BossesTotal,
				clock
			)
		end
		local parts = {}
		for _, member in current.Members do
			table.insert(
				parts,
				string.format(
					"%s %d",
					if member.UserId == localPlayer.UserId then "You" else member.Name,
					member.Hits
				)
			)
		end
		hitsLine.Text = "Hits: " .. table.concat(parts, " · ")
	end
	return gui, refresh
end

-- The window ---------------------------------------------------------------------------

local function buildPanel(parent: Instance): ()
	local window = PanelKit.window({
		Name = "Missions",
		Title = "🤝 Team Missions",
		Subtitle = "Team up with 2-4 players and clear a chain of bosses before the clock runs out.",
		Accent = ACCENT,
		DisplayOrder = 5,
	}, parent)
	local content = window.Content
	local countdowns: { [TextLabel]: number } = {}

	local function render(): ()
		window:clear()
		table.clear(countdowns)
		local mine = MissionController.mine()

		if inMission() then
			PanelKit.notice(content, "Locked", "You're on a mission right now. Good luck!")
			return
		end

		if mine then
			local mission = MissionConfig.ById[mine.MissionId]
			local section = PanelKit.section(
				content,
				"Your team: " .. (if mission then mission.Icon .. " " .. mission.Name else "?"),
				false,
				true
			)
			local names = {}
			for _, member in mine.Members do
				table.insert(
					names,
					if member.UserId == localPlayer.UserId then "You" else member.Name
				)
			end
			PanelKit.text(
				section.Body,
				string.format(
					"%s (%d of %d)",
					table.concat(names, ", "),
					#mine.Members,
					MissionConfig.TeamMax
				)
			)
			local countdown = PanelKit.text(section.Body, "", "Muted")
			countdowns[countdown] = mine.ExpiresAt
			local row = PanelKit.row(section.Body)
			if mine.LeaderUserId == localPlayer.UserId then
				local begin = PanelKit.button(row, "Start mission", C.Good)
				begin.Size = UDim2.new(0.5, -4, 1, 0)
				PanelKit.setDisabled(begin, #mine.Members < MissionConfig.TeamMin or freeRooms == 0)
				begin.Activated:Connect(MissionController.begin)
			else
				local waiting = PanelKit.text(row, "Waiting for the leader to start…", "Muted")
				waiting.Size = UDim2.new(0.5, -4, 1, 0)
			end
			local leave = PanelKit.button(row, "Leave team", C.Danger)
			leave.Size = UDim2.new(0.5, -4, 1, 0)
			leave.Activated:Connect(MissionController.leave)
			if #mine.Members < MissionConfig.TeamMin then
				PanelKit.text(
					section.Body,
					string.format(
						"Needs at least %d players. Others see your team and can join.",
						MissionConfig.TeamMin
					),
					"Muted"
				)
			end
		else
			local start = PanelKit.section(content, "Start a team", false, true)
			for _, mission in MissionConfig.List do
				PanelKit.text(
					start.Body,
					string.format("%s %s", mission.Icon, mission.Name),
					"Heading"
				)
				PanelKit.text(
					start.Body,
					string.format(
						"%s %d waves · %d minutes.",
						mission.Text,
						#mission.Waves,
						mission.TimeLimit // 60
					),
					"Muted"
				)
				local row = PanelKit.row(start.Body)
				local open = PanelKit.button(row, "Open a team", ACCENT)
				open.Size = UDim2.new(0.5, -4, 1, 0)
				PanelKit.setDisabled(open, inPickleball())
				open.Activated:Connect(function()
					MissionController.openTeam(mission.Id)
				end)
			end
		end

		local open = PanelKit.section(
			content,
			string.format("Open teams · %d room(s) free", freeRooms),
			false,
			true
		)
		local others = 0
		for _, team in teamList do
			if not isMine(team) then
				others += 1
				local mission = MissionConfig.ById[team.MissionId]
				local row = PanelKit.row(open.Body, 56)
				local label = PanelKit.text(
					row,
					string.format(
						"%s · %s\n%d of %d players",
						team.LeaderName,
						if mission then mission.Icon .. " " .. mission.Name else "?",
						#team.Members,
						MissionConfig.TeamMax
					)
				)
				label.Size = UDim2.new(1, -160, 1, 0)
				local join = PanelKit.button(row, "Join", ACCENT)
				join.Size = UDim2.fromOffset(150, 46)
				PanelKit.setDisabled(
					join,
					mine ~= nil or inPickleball() or #team.Members >= MissionConfig.TeamMax
				)
				join.Activated:Connect(function()
					MissionController.join(team.Id)
				end)
			end
		end
		if others == 0 then
			PanelKit.notice(open.Body, "Empty", "No open teams right now. Start one above!")
		end

		local rewards = PanelKit.section(content, "Rewards", false, true)
		PanelKit.text(rewards.Body, "Clear the mission: " .. rewardText())
		local snapshot = ProgressController.get()
		local today = QuestRules.dayKey(os.time())
		local used = if snapshot and snapshot.Missions.DayKey == today
			then snapshot.Missions.DayRewarded
			else 0
		PanelKit.text(
			rewards.Body,
			string.format(
				"Rewarded today: %d / %d. Every boss you beat on a mission also pays as usual. To count, land at least %d hits and a quarter of your team's average: hits count, not damage, so every level helps equally.",
				used,
				MissionConfig.DailyRewarded,
				MissionConfig.MinHits
			),
			"Muted"
		)
	end

	window:onOpen(function()
		task.defer(render)
	end)
	openPanel = function()
		if window:isOpen() then
			render()
		else
			window:open()
		end
	end
	MissionController.Changed:Connect(function()
		if window:isOpen() then
			render()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if window:isOpen() then
				local now = serverNow()
				for label, expiresAt in countdowns do
					label.Text = string.format(
						"Closes in %d s if it doesn't start",
						math.max(0, math.ceil(expiresAt - now))
					)
				end
			end
		end
	end)
end

function MissionController.start(): ()
	remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Mission") :: Folder
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	buildPanel(playerGui)
	local hud, refreshHud = buildHud()
	hud.Parent = playerGui

	remote("Teams").OnClientEvent:Connect(onTeams)
	remote("State").OnClientEvent:Connect(function(payload: unknown)
		onState(payload)
		refreshHud()
	end)
	remote("Result").OnClientEvent:Connect(onResult)
	-- The Mission Board on the Rooftop Lounge (Lib/RooftopBuilder).
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name == "MissionBoardPrompt" then
			MissionController.open()
		end
	end)
	localPlayer:GetAttributeChangedSignal(Attributes.InMission):Connect(function()
		if not inMission() then
			run = nil
		end
		refreshHud()
		changedEvent:Fire()
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if run and inMission() then
				refreshHud()
			end
		end
	end)
end

return MissionController
