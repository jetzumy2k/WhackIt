--!strict
--[[
	Quests on the client (docs/QUESTS.md). Display and requests only: the
	server counts progress and pays rewards (QuestService).

	  * A "📋 Quests" button in the HUD column with a badge counting quests
	    ready to claim.
	  * The Quests window: 📅 Daily (3 quests, one reroll a day, the bonus
	    for claiming all three, time to the reset), 🗓️ Weekly (3 quests, each
	    with an office supply, time to Monday) and 🎓 Getting started (the
	    tutorial chain, one step at a time).
	  * Quests.Rewarded: a card with what a claim paid.
	  * The Event of the Day (docs/DAILY_EVENTS.md) on the 🌟 Today tab:
	    today's event, how points are earned, the points and the three tiers,
	    the time left. A card on join says what today's event is, and
	    DailyEvent.Rewarded shows each tier the server paid.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local QuestConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("QuestConfig"))
local QuestRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("QuestRules"))
local DailyEventConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("DailyEventConfig"))
local DailyEventRules =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DailyEventRules"))

local AnnouncementController = require(script.Parent.AnnouncementController)
local PanelKit = require(script.Parent.Parent.Lib.PanelKit)
local ProgressController = require(script.Parent.ProgressController)
local Responsive = require(script.Parent.Parent.Lib.Responsive)
local UiTokens = require(script.Parent.Parent.Lib.UiTokens)

local QuestController = {}

local C = PanelKit.Colors
local ACCENT = Color3.fromRGB(240, 170, 80)
local BADGE_COLOR = Color3.fromRGB(230, 70, 70)
local MAX_TEXT = 120

local localPlayer = Players.LocalPlayer
local remotes: Folder? = nil
local openPanel: ((tab: string?) -> ())? = nil

local function remote(name: string): RemoteEvent
	local folder = remotes :: Folder
	local event = folder:WaitForChild(name)
	assert(event:IsA("RemoteEvent"), "Quests." .. name .. " must be a RemoteEvent")
	return event
end

local function number(value: unknown, fallback: number): number
	return if typeof(value) == "number" and value == value then value else fallback
end

local function text(value: unknown, fallback: string): string
	if typeof(value) == "string" and #value <= MAX_TEXT and utf8.len(value) ~= nil then
		return value
	end
	return fallback
end

local function duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 86400 then
		return string.format("%d d %d h", seconds // 86400, (seconds % 86400) // 3600)
	end
	return string.format("%d h %d min", seconds // 3600, (seconds % 3600) // 60)
end

local function rewardText(quest: QuestConfig.Quest): string
	return string.format("%d coins · %d XP", quest.Coins, quest.Xp)
		.. if quest.Kind == "Weekly" then " · an office supply" else ""
end

-- Opens the Quests window, on `tab` if given ("Today", "Daily", "Weekly", "Tutorial").
function QuestController.open(tab: string?): ()
	if openPanel then
		openPanel(tab)
	end
end

-- Quests ready to claim (for the badge).
function QuestController.claimable(): number
	local snapshot = ProgressController.get()
	return if snapshot then QuestRules.claimableCount(snapshot.Quests) else 0
end

local function tierText(tier: DailyEventConfig.Tier): string
	return string.format("%d coins · %d XP", tier.Coins, tier.Xp)
		.. if tier.Supply then " · an office supply" else ""
end

local function onEventRewarded(payload: unknown): ()
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	local dailyEvent = DailyEventConfig.ById[text(data.EventId, "")]
	local parts = {
		string.format("+%d coins", number(data.Coins, 0)),
		string.format("+%d XP", number(data.Xp, 0)),
	}
	local supply = text(data.Supply, "")
	if supply ~= "" then
		table.insert(parts, supply .. " (in your office storage)")
	end
	AnnouncementController.show({
		Title = string.format(
			"%s TIER %d OF %d!",
			if dailyEvent then dailyEvent.Icon else "🌟",
			number(data.Tier, 1),
			number(data.Tiers, #DailyEventConfig.Tiers)
		),
		Body = if dailyEvent then dailyEvent.Name else "Event of the Day",
		Detail = table.concat(parts, " · "),
		Accent = ACCENT,
		Celebrate = true,
		Seconds = 6,
	})
end

-- Once per join: what today's event is.
local function announceToday(): ()
	local dailyEvent = DailyEventRules.eventFor(os.time())
	AnnouncementController.show({
		Title = dailyEvent.Icon .. " TODAY: " .. string.upper(dailyEvent.Name),
		Body = dailyEvent.Text,
		Detail = "Points: " .. dailyEvent.PointsText,
		Accent = ACCENT,
		Seconds = 8,
		ActionLabel = "SEE GOALS",
		OnAction = function()
			QuestController.open("Today")
		end,
	})
end

local function onRewarded(payload: unknown): ()
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	local parts = {
		string.format("+%d coins", number(data.Coins, 0)),
		string.format("+%d XP", number(data.Xp, 0)),
	}
	local supply = text(data.Supply, "")
	if supply ~= "" then
		table.insert(parts, supply .. " (in your office storage)")
	end
	AnnouncementController.show({
		Title = "📋 QUEST COMPLETE!",
		Body = text(data.Title, "Quest"),
		Detail = table.concat(parts, " · "),
		Accent = ACCENT,
		Celebrate = true,
		Seconds = 6,
	})
end

-- Window -----------------------------------------------------------------------

local function buildPanel(parent: Instance): ()
	local window = PanelKit.window({
		Name = "Quests",
		Title = "📋 Quests",
		Subtitle = "Little jobs around the office. Finish them, then claim the reward.",
		Accent = ACCENT,
		DisplayOrder = 5,
	}, parent)
	local content = window.Content
	local activeTab = "Today"

	-- One quest: what to do, a progress bar, the reward and its button.
	local function questRow(
		parentFrame: Instance,
		quest: QuestConfig.Quest,
		progress: number,
		claimed: boolean,
		onClaim: () -> (),
		onReroll: (() -> ())?
	): ()
		local section = PanelKit.section(parentFrame, quest.Text, false, true)
		local bar = PanelKit.progressBar(section.Body, if claimed then C.Good else ACCENT)
		local done = progress >= quest.Target
		bar.set(
			math.clamp(progress / quest.Target, 0, 1),
			if claimed
				then "✅ Claimed"
				else string.format("%d / %d", math.min(progress, quest.Target), quest.Target)
		)
		PanelKit.text(section.Body, rewardText(quest), "Muted")
		if claimed then
			return
		end
		local row = PanelKit.row(section.Body)
		local claim = PanelKit.button(
			row,
			if done then "Claim!" else "Not done yet",
			if done then C.Good else C.Neutral
		)
		claim.Size = UDim2.new(0.5, -4, 1, 0)
		PanelKit.setDisabled(claim, not done)
		claim.Activated:Connect(onClaim)
		if onReroll and not done then
			local reroll = PanelKit.button(row, "🎲 Swap quest", C.Primary)
			reroll.Size = UDim2.new(0.5, -4, 1, 0)
			reroll.Activated:Connect(onReroll)
		end
	end

	local function dailyPage(state: QuestRules.State): ()
		local now = os.time()
		PanelKit.text(
			content,
			string.format(
				"New quests in %s (00:00 UTC). Finished quests you don't claim are paid at the reset.",
				duration(QuestRules.nextDailyReset(now) - now)
			),
			"Muted"
		)
		local rerollsLeft = QuestConfig.DailyRerolls - state.Rerolls
		for index, slot in state.Daily do
			local quest = QuestRules.questOf(slot)
			if quest then
				questRow(
					content,
					quest,
					slot.Progress,
					slot.Claimed,
					function()
						remote("Claim"):FireServer("Daily", index)
					end,
					if rerollsLeft > 0
						then function()
							remote("Reroll"):FireServer(index)
						end
						else nil
				)
			end
		end
		local bonus = QuestConfig.DailyBonus
		local section = PanelKit.section(content, "🎁 All three done", false, true)
		PanelKit.text(
			section.Body,
			string.format(
				"Claim all of today's quests for a bonus: %d coins · %d XP.",
				bonus.Coins,
				bonus.Xp
			),
			"Muted"
		)
		if state.DailyBonus then
			PanelKit.text(section.Body, "✅ Claimed today.")
		else
			local row = PanelKit.row(section.Body)
			local claim = PanelKit.button(row, "Claim bonus", C.Good)
			claim.Size = UDim2.new(0.5, -4, 1, 0)
			PanelKit.setDisabled(claim, not QuestRules.canClaimBonus(state))
			claim.Activated:Connect(function()
				remote("Claim"):FireServer("Bonus")
			end)
		end
		PanelKit.text(
			content,
			if rerollsLeft > 0
				then "🎲 You can swap one unfinished quest a day for another."
				else "🎲 Today's swap is used.",
			"Muted"
		)
	end

	local function weeklyPage(state: QuestRules.State): ()
		local now = os.time()
		PanelKit.text(
			content,
			string.format(
				"New quests in %s (Monday 00:00 UTC). Each one also gives an office supply.",
				duration(QuestRules.nextWeeklyReset(now) - now)
			),
			"Muted"
		)
		for index, slot in state.Weekly do
			local quest = QuestRules.questOf(slot)
			if quest then
				questRow(content, quest, slot.Progress, slot.Claimed, function()
					remote("Claim"):FireServer("Weekly", index)
				end, nil)
			end
		end
	end

	local function tutorialPage(state: QuestRules.State): ()
		local total = #QuestConfig.Tutorial
		local quest = QuestRules.tutorialQuest(state)
		if quest == nil then
			PanelKit.notice(
				content,
				"Empty",
				"You've finished Getting started. Daily and weekly quests keep coming!"
			)
			return
		end
		PanelKit.text(content, string.format("Step %d of %d", state.TutorialStep, total), "Heading")
		questRow(content, quest, state.TutorialProgress, false, function()
			remote("Claim"):FireServer("Tutorial")
		end, nil)
		local nextQuest = QuestConfig.Tutorial[state.TutorialStep + 1]
		if nextQuest then
			PanelKit.text(content, "Next: " .. nextQuest.Text, "Muted")
		end
	end

	local function todayPage(saved: DailyEventRules.State): ()
		local now = os.time()
		local dailyEvent = DailyEventRules.eventFor(now)
		-- Points saved for an earlier day count as 0 today.
		local today = saved.DayKey == DailyEventRules.dayKey(now)
		local points = if today then DailyEventRules.shownPoints(saved) else 0
		local paid = if today then saved.Tiers else 0
		local header =
			PanelKit.section(content, dailyEvent.Icon .. " " .. dailyEvent.Name, false, true)
		PanelKit.text(header.Body, dailyEvent.Text)
		PanelKit.text(header.Body, "Points: " .. dailyEvent.PointsText, "Muted")
		PanelKit.text(
			header.Body,
			string.format(
				"Ends in %s (00:00 UTC). Tomorrow brings a different event; missing a day costs nothing.",
				duration(DailyEventRules.endsAt(now) - now)
			),
			"Muted"
		)
		local tiers = DailyEventConfig.Tiers
		local goal =
			PanelKit.section(content, string.format("Your points: %d", points), false, true)
		local nextTier = tiers[paid + 1]
		local bar = PanelKit.progressBar(goal.Body, if nextTier then ACCENT else C.Good)
		bar.set(
			if nextTier then math.clamp(points / nextTier.Points, 0, 1) else 1,
			if nextTier
				then string.format("%d / %d to tier %d", points, nextTier.Points, paid + 1)
				else "✅ All tiers reached!"
		)
		for index, tier in tiers do
			PanelKit.text(
				goal.Body,
				string.format(
					"%s Tier %d · %d points: %s",
					if index <= paid then "✅" else "⬜",
					index,
					tier.Points,
					tierText(tier)
				),
				if index <= paid then nil else "Muted"
			)
		end
		PanelKit.text(goal.Body, "Tiers are paid as soon as you reach them.", "Muted")
	end

	local function render(): ()
		window:clear()
		window:selectTab(activeTab)
		local snapshot = ProgressController.get()
		if snapshot == nil then
			PanelKit.text(content, "Loading your quests...", "Muted")
			return
		end
		local state = snapshot.Quests
		if activeTab == "Today" then
			todayPage(snapshot.DailyEvent)
		elseif activeTab == "Weekly" then
			weeklyPage(state)
		elseif activeTab == "Tutorial" then
			tutorialPage(state)
		else
			dailyPage(state)
		end
	end

	window:setTabs({
		{ Id = "Today", Label = "🌟 Today" },
		{ Id = "Daily", Label = "📅 Daily" },
		{ Id = "Weekly", Label = "🗓️ Weekly" },
		{ Id = "Tutorial", Label = "🎓 Getting started" },
	}, function(id: string)
		activeTab = id
		render()
	end)
	window:onOpen(function()
		task.defer(render)
	end)
	openPanel = function(tab: string?)
		if tab then
			activeTab = tab
		end
		if window:isOpen() then
			render()
		else
			window:open()
		end
	end
	ProgressController.Changed:Connect(function()
		if window:isOpen() then
			render()
		end
	end)
end

-- HUD button with a badge ------------------------------------------------------------

local function buildButton(): ()
	local button = Responsive.dockButton("OpenQuests", "📋", "Quests", ACCENT, 6)
	button.Activated:Connect(function()
		QuestController.open()
	end)
	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromScale(1, 0)
	badge.Size = UDim2.fromOffset(22, 22)
	badge.BackgroundColor3 = BADGE_COLOR
	badge.TextColor3 = Color3.new(1, 1, 1)
	badge.Font = PanelKit.FONT_BOLD
	badge.TextSize = 14
	badge.ZIndex = button.ZIndex + 2
	badge.Visible = false
	badge.Parent = button
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = badge
	-- Quests already announced as ready (owner feedback 2026-10-10: the badge
	-- alone was easy to miss). Nil until the first snapshot, so quests that
	-- were ready when you joined get one reminder instead of a card each.
	local announced: { [string]: boolean }? = nil
	local function announceReady(): ()
		local snapshot = ProgressController.get()
		if snapshot == nil then
			return
		end
		local ready = QuestRules.claimableList(snapshot.Quests)
		local known = announced
		if known == nil then
			local first: { [string]: boolean } = {}
			announced = first
			for _, entry in ready do
				first[entry.Key] = true
			end
			if #ready > 0 then
				AnnouncementController.show({
					Title = "📋 QUESTS TO CLAIM",
					Body = string.format("%d finished quest(s) are waiting for you.", #ready),
					Accent = ACCENT,
					Seconds = 7,
					ActionLabel = "CLAIM",
					OnAction = function()
						QuestController.open(
							if ready[1].Kind == "Bonus" then "Daily" else ready[1].Kind
						)
					end,
				})
			end
			return
		end
		for _, entry in ready do
			if not known[entry.Key] then
				known[entry.Key] = true
				AnnouncementController.show({
					Title = "📋 QUEST DONE!",
					Body = entry.Text,
					Detail = "Your reward is ready in Quests.",
					Accent = ACCENT,
					Seconds = 7,
					ActionLabel = "CLAIM",
					OnAction = function()
						QuestController.open(if entry.Kind == "Bonus" then "Daily" else entry.Kind)
					end,
				})
			end
		end
	end
	local pulse: Tween? = nil
	local lastCount = 0
	local function refresh(): ()
		local count = QuestController.claimable()
		badge.Visible = count > 0
		badge.Text = if count > 9 then "9+" else tostring(count)
		if count > lastCount and not UiTokens.reducedMotion() then
			-- A short pop so the badge catches the eye.
			if pulse then
				pulse:Cancel()
			end
			badge.Size = UDim2.fromOffset(34, 34)
			local tween = TweenService:Create(
				badge,
				TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Size = UDim2.fromOffset(22, 22) }
			)
			pulse = tween
			tween:Play()
		end
		lastCount = count
		announceReady()
	end
	ProgressController.Changed:Connect(refresh)
	refresh()
end

function QuestController.start(): ()
	remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Quests") :: Folder
	buildPanel(localPlayer:WaitForChild("PlayerGui"))
	buildButton()
	remote("Rewarded").OnClientEvent:Connect(onRewarded)
	local eventRewarded = ReplicatedStorage:WaitForChild("Remotes")
		:WaitForChild("DailyEvent")
		:WaitForChild("Rewarded")
	assert(eventRewarded:IsA("RemoteEvent"), "DailyEvent.Rewarded must be a RemoteEvent")
	eventRewarded.OnClientEvent:Connect(onEventRewarded)
	task.delay(6, announceToday)
	-- The Event Board on the Rooftop Lounge (Lib/RooftopBuilder).
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name == "EventBoardPrompt" then
			QuestController.open("Today")
		end
	end)
end

return QuestController
