--!strict
--[[
	Weekly office design contests on the client (docs/CONTESTS.md, Phase 6b).

	  * The 🏆 Contest tab of the Showcase window (ShowcaseController calls
	    page()): this week's theme and its furniture, the phase and how long
	    it lasts, entering, voting, last week's winners and the rules.
	  * The star bar above the Showcase bar while you stand in an entry
	    dealt to you: ⭐ 1-5 and ⏭️ Next entry (ShowcaseController calls
	    setRoom()).
	  * The results card (Contest.Result).
	The server decides everything (ContestService); this only asks and shows.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ContestConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ContestConfig"))
local ContestRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ContestRules"))
local FurnitureConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("FurnitureConfig"))
local FurnitureRules =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FurnitureRules"))

local AdminController = require(script.Parent.AdminController)
local AnnouncementController = require(script.Parent.AnnouncementController)
local PanelKit = require(script.Parent.Parent.Lib.PanelKit)
local ProgressController = require(script.Parent.ProgressController)
local Responsive = require(script.Parent.Parent.Lib.Responsive)

local ContestController = {}

local C = PanelKit.Colors
local ACCENT = Color3.fromRGB(240, 160, 60)
local STAR_COLOR = Color3.fromRGB(240, 190, 70)
-- Seconds the contest state is shown before it's asked for again.
local INFO_REFRESH = 20
local MEDALS = { "🥇", "🥈", "🥉" }

type Winner = { UserId: number, Name: string, Score: number }

type State = {
	Available: boolean,
	Global: boolean,
	Week: number,
	Phase: string,
	Remaining: number, -- seconds left in the phase when it arrived
	ReceivedAt: number, -- os.clock()
	Test: boolean, -- the Studio test clock is moved
	Entered: boolean,
	EntryModeration: string,
	EntryItems: number,
	EntryFit: number,
	CanEnter: boolean,
	EnterReason: string,
	CanVote: boolean,
	VoteReason: string,
	VotesLeft: number,
	Winners: { Winner },
}

export type Room = {
	OwnerId: number,
	Name: string,
	CanRate: boolean,
	RateAfter: number,
	Voted: boolean,
	Voting: boolean,
	VotesLeft: number,
}

local state: State? = nil
local askedAt = -math.huge
local listeners: { () -> () } = {}
local setRoomImpl: (room: Room?) -> () = function() end

local function remote(name: string): RemoteEvent
	local found =
		ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Contest"):WaitForChild(name)
	assert(found:IsA("RemoteEvent"), "Contest." .. name .. " must be a RemoteEvent")
	return found
end

local function number(value: unknown): number
	return if typeof(value) == "number" and value == value then value else 0
end

local function text(value: unknown): string
	return if typeof(value) == "string" then value else ""
end

local function duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 86400 then
		return string.format("%d d %d h", seconds // 86400, (seconds % 86400) // 3600)
	end
	return string.format("%d h %d min", seconds // 3600, (seconds % 3600) // 60)
end

local function changed(): ()
	for _, listener in listeners do
		task.spawn(listener)
	end
end

local function parseWinners(raw: unknown): { Winner }
	local winners: { Winner } = {}
	if typeof(raw) ~= "table" then
		return winners
	end
	for _, value in raw :: { unknown } do
		if typeof(value) == "table" then
			local data = value :: { [string]: unknown }
			if typeof(data.UserId) == "number" then
				table.insert(winners, {
					UserId = data.UserId :: number,
					Name = text(data.Name),
					Score = number(data.Score),
				})
			end
		end
	end
	return winners
end

local function onState(payload: unknown): ()
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	state = {
		Available = data.Available == true,
		Global = data.Global == true,
		Week = number(data.Week),
		Phase = text(data.Phase),
		Remaining = number(data.Remaining),
		ReceivedAt = os.clock(),
		Test = data.Test == true,
		Entered = data.Entered == true,
		EntryModeration = text(data.EntryModeration),
		EntryItems = number(data.EntryItems),
		EntryFit = number(data.EntryFit),
		CanEnter = data.CanEnter == true,
		EnterReason = text(data.EnterReason),
		CanVote = data.CanVote == true,
		VoteReason = text(data.VoteReason),
		VotesLeft = number(data.VotesLeft),
		Winners = parseWinners(data.Winners),
	}
	changed()
end

local function onResult(payload: unknown): ()
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	local rank = if typeof(data.Rank) == "number" then data.Rank :: number else nil
	local parts =
		{ string.format("%d coins", number(data.Coins)), string.format("%d XP", number(data.Xp)) }
	local item = text(data.Item)
	if item ~= "" then
		table.insert(parts, item .. " (in your office storage)")
	end
	AnnouncementController.show({
		Title = if rank and rank <= 3 then "🏆 YOU PLACED!" else "🏆 CONTEST RESULTS",
		Body = if rank
			then string.format("You came #%d in the %s contest!", rank, text(data.Theme))
			else string.format("Thanks for entering the %s contest!", text(data.Theme)),
		Detail = table.concat(parts, " · "),
		Accent = ACCENT,
		Celebrate = rank ~= nil,
		Seconds = 8,
	})
end

-- Public --------------------------------------------------------------------------------

-- Asks the server for the contest state (at most every INFO_REFRESH seconds unless forced).
function ContestController.request(force: boolean?): ()
	if not force and os.clock() - askedAt < INFO_REFRESH then
		return
	end
	askedAt = os.clock()
	remote("Info"):FireServer()
end

function ContestController.onChanged(callback: () -> ()): ()
	table.insert(listeners, callback)
end

-- The contest copy the player stands in (nil = none), from ShowcaseController.
function ContestController.setRoom(room: Room?): ()
	setRoomImpl(room)
end

-- One line for the Social page.
function ContestController.headline(): string
	local now = os.time()
	local theme = ContestRules.themeFor(ContestRules.weekId(now))
	return string.format(
		"This week: %s %s · %s",
		theme.Icon,
		theme.Name,
		if ContestRules.phase(now) == "Entry" then "entries open" else "voting now"
	)
end

-- The 🏆 Contest tab. `visit(userId, variant)` opens an entry; `close` closes the window.
function ContestController.page(
	content: Instance,
	visit: (userId: number, variant: string) -> (),
	close: () -> ()
): ()
	ContestController.request(false)
	local current = state
	-- The server's calendar once known (it may be a Studio test clock).
	local week = if current then current.Week else ContestRules.weekId(os.time())
	local phase = if current then current.Phase else ContestRules.phase(os.time())
	local remaining = if current
		then current.Remaining - (os.clock() - current.ReceivedAt)
		else ContestRules.phaseEnds(os.time()) - os.time()
	local theme = ContestRules.themeFor(week)

	local header = PanelKit.section(
		content,
		string.format("%s This week: %s", theme.Icon, theme.Name),
		false,
		true
	)
	PanelKit.text(header.Body, theme.Text)
	PanelKit.text(
		header.Body,
		if phase == "Entry"
			then string.format(
				"📝 Entries are open: %s left. Voting is on Saturday and Sunday (UTC).",
				duration(remaining)
			)
			else string.format(
				"⭐ Voting is open: %s left. Results on Monday.",
				duration(remaining)
			),
		"Heading"
	)
	local names: { string } = {}
	local layout: FurnitureRules.Layout = {}
	local snapshot = ProgressController.get()
	if snapshot then
		layout = snapshot.OfficeLayout
	end
	local used: { [string]: boolean } = {}
	for _, entry in layout do
		used[entry.Item] = true
	end
	for _, key in theme.Items do
		local item = FurnitureConfig.ByKey[key]
		if item then
			table.insert(names, (if used[key] then "✅ " else "• ") .. item.Name)
		end
	end
	local _fit, count = ContestRules.themeFit(layout, theme)
	PanelKit.text(
		header.Body,
		string.format(
			"Theme furniture (your office has %d; %d different ones give the full ⭐ +%.1f bonus):",
			count,
			ContestConfig.FitTarget,
			ContestConfig.ThemeBonus
		),
		"Muted"
	)
	PanelKit.text(header.Body, table.concat(names, "   "), "Muted")

	if current == nil then
		PanelKit.notice(content, "Loading", "Loading the contest...")
		return
	end
	if not current.Available then
		PanelKit.notice(content, "Error", "The contest isn't available right now.")
		return
	end
	if not current.Global then
		PanelKit.text(content, "🧪 Studio test: entries and votes stay in this server.", "Muted")
	end
	if RunService:IsStudio() and AdminController.isAdmin() then
		local test = PanelKit.section(content, "🧪 Studio test (admins)", false, true)
		PanelKit.text(
			test.Body,
			if current.Test
				then "The contest clock in this test server is moved forward."
				else "Move this test server's contest clock to the next phase (entries → voting → results).",
			"Muted"
		)
		local testRow = PanelKit.row(test.Body)
		local skip = PanelKit.button(testRow, "⏩ Next phase", C.Neutral)
		skip.Size = UDim2.new(0.5, -4, 1, 0)
		skip.Activated:Connect(function()
			askedAt = os.clock()
			remote("Info"):FireServer("TestNext")
		end)
	end

	local mine = PanelKit.section(content, "🏢 My entry", false, true)
	if current.Entered then
		local status = if current.EntryModeration == "Removed"
			then "A moderator removed your entry."
			elseif current.EntryModeration == "Review" then "Your entry is waiting for a moderator."
			else string.format(
				"✅ You're in with %d pieces of furniture (theme bonus ⭐ +%.2f).",
				current.EntryItems,
				current.EntryFit * ContestConfig.ThemeBonus
			)
		PanelKit.text(mine.Body, status)
	else
		PanelKit.text(
			mine.Body,
			"Enter with your office as it is now. You can update it until Friday.",
			"Muted"
		)
	end
	if not current.CanEnter and current.EnterReason ~= "" then
		PanelKit.text(mine.Body, current.EnterReason, "Muted")
	end
	local row = PanelKit.row(mine.Body)
	local enter = PanelKit.button(
		row,
		if current.Entered then "🔄 Update my entry" else "🏆 Enter with my office",
		C.Good
	)
	enter.Size = UDim2.new(0.5, -4, 1, 0)
	PanelKit.setDisabled(enter, not current.CanEnter)
	enter.Activated:Connect(function()
		remote("Enter"):FireServer()
	end)
	if current.Entered then
		local see = PanelKit.button(row, "👀 See my entry", C.Primary)
		see.Size = UDim2.new(0.5, -4, 1, 0)
		see.Activated:Connect(function()
			close()
			visit(Players.LocalPlayer.UserId, "Contest")
		end)
	end

	local voting = PanelKit.section(content, "⭐ Vote", false, true)
	PanelKit.text(
		voting.Body,
		string.format(
			"You get a random entry: look around, then give it 1-5 stars. %d entries a day (skipping uses one too).",
			ContestConfig.DailyVotes
		),
		"Muted"
	)
	if current.CanVote then
		PanelKit.text(voting.Body, string.format("%d left today.", current.VotesLeft))
	elseif current.VoteReason ~= "" then
		PanelKit.text(voting.Body, current.VoteReason, "Muted")
	end
	local voteRow = PanelKit.row(voting.Body)
	local vote = PanelKit.button(voteRow, "⭐ Vote now", STAR_COLOR)
	vote.Size = UDim2.new(0.5, -4, 1, 0)
	PanelKit.setDisabled(vote, not current.CanVote)
	vote.Activated:Connect(function()
		close()
		remote("Ballot"):FireServer()
	end)

	local winners = PanelKit.section(content, "🏆 Last week's winners", false, true)
	if #current.Winners == 0 then
		PanelKit.text(winners.Body, "No results yet.", "Muted")
	end
	for index, winner in current.Winners do
		local line = PanelKit.row(winners.Body)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, -128, 1, 0)
		label.Font = PanelKit.FONT
		label.TextColor3 = C.Text
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text =
			string.format("%s %s  ·  %.2f ⭐", MEDALS[index] or "", winner.Name, winner.Score)
		label.Parent = line
		PanelKit.setTextSize(label, PanelKit.TEXT_SIZE)
		local open = PanelKit.button(line, "Visit", C.Primary)
		open.Size = UDim2.new(0, 120, 1, 0)
		open.Activated:Connect(function()
			close()
			visit(winner.UserId, "Winner")
		end)
	end

	local rules = PanelKit.section(content, "📜 How the contest works", true, false)
	for _, line in
		{
			"Monday-Friday (UTC): enter with your office (Level 5, at least 5 pieces of furniture). Update it as often as you like (every 5 minutes at most).",
			"Saturday-Sunday: vote. You only rate entries the game gives you at random, never your own, each once.",
			string.format(
				"Score: a fair average of the stars (every entry starts as if it had %d votes of %d stars, so a few friends can't decide it) plus up to ⭐ +%.1f for using the theme furniture. Entries need %d votes to be ranked.",
				ContestConfig.PriorVotes,
				ContestConfig.PriorStars,
				ContestConfig.ThemeBonus,
				ContestConfig.MinVotesToRank
			),
			"Prizes on Monday: #1 Design Star Trophy, #2-3 Top Design Plaque, #4-10 Design Ribbon, plus coins and XP. Everyone else who entered gets coins and XP too.",
			"🚩 Report works like in the Showcase; reported entries wait for a moderator and don't count meanwhile.",
		}
	do
		PanelKit.text(rules.Body, "• " .. line, "Muted")
	end
end

-- Star bar -------------------------------------------------------------------------------

local function buildStarBar(gui: ScreenGui): ()
	local bar = Instance.new("Frame")
	bar.Name = "ContestStars"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -132)
	bar.Size = UDim2.fromOffset(560, 56)
	bar.BackgroundColor3 = C.Window
	bar.BackgroundTransparency = 0.1
	bar.Visible = false
	bar.Parent = gui
	Instance.new("UICorner").Parent = bar
	local stroke = Instance.new("UIStroke")
	stroke.Color = STAR_COLOR
	stroke.Transparency = 0.3
	stroke.Parent = bar
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 5)
	padding.PaddingBottom = UDim.new(0, 5)
	padding.Parent = bar
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = bar

	local label = Instance.new("TextLabel")
	label.LayoutOrder = 0
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0, 150, 1, 0)
	label.Font = PanelKit.FONT_BOLD
	label.TextColor3 = C.Heading
	label.TextWrapped = true
	label.Parent = bar
	PanelKit.setTextSize(label, PanelKit.SMALL_SIZE)

	local stars: { TextButton } = {}
	for value = ContestConfig.MinStars, ContestConfig.MaxStars do
		local button = PanelKit.button(bar, "⭐" .. value, STAR_COLOR)
		button.Name = "Star" .. value
		button.LayoutOrder = value
		button.Size = UDim2.new(0, 52, 1, 0)
		button.Activated:Connect(function()
			remote("Vote"):FireServer(value)
		end)
		table.insert(stars, button)
	end
	local nextEntry = PanelKit.button(bar, "⏭️ Next", C.Primary)
	nextEntry.LayoutOrder = 10
	nextEntry.Size = UDim2.new(0, 90, 1, 0)
	nextEntry.Activated:Connect(function()
		remote("Ballot"):FireServer()
	end)

	-- Phones: narrower (clear of the thumbstick and jump button), no label,
	-- icon-only Next.
	Responsive.onChanged(function()
		local phone = Responsive.formFactor() == "Phone"
		bar.Size = if phone then UDim2.new(0.6, 0, 0, 46) else UDim2.fromOffset(560, 56)
		bar.Position = UDim2.new(0.5, 0, 1, if phone then -120 else -132)
		label.Visible = not phone
		for _, button in stars do
			button.Size = UDim2.new(0, if phone then 44 else 52, 1, 0)
		end
		nextEntry.Text = if phone then "⏭️" else "⏭️ Next"
		nextEntry.Size = UDim2.new(0, if phone then 46 else 90, 1, 0)
	end)

	local token = 0
	setRoomImpl = function(room: Room?)
		token += 1
		local mine = token
		bar.Visible = room ~= nil and room.Voting
		if room == nil then
			return
		end
		for _, button in stars do
			button.Visible = room.CanRate
			PanelKit.setDisabled(button, room.RateAfter > 0)
		end
		nextEntry.Visible = room.VotesLeft > 0
		label.Text = if room.CanRate
			then (if room.RateAfter > 0 then "Look around first..." else "Rate this office:")
			elseif room.Voted then "✅ Voted"
			else string.format("%d vote(s) left today", room.VotesLeft)
		if room.CanRate and room.RateAfter > 0 then
			task.delay(room.RateAfter + 0.1, function()
				if token ~= mine then
					return
				end
				for _, button in stars do
					PanelKit.setDisabled(button, false)
				end
				label.Text = "Rate this office:"
			end)
		end
	end
end

function ContestController.start(): ()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "ContestHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 3
	gui.Parent = playerGui
	buildStarBar(gui)

	remote("State").OnClientEvent:Connect(onState)
	remote("Result").OnClientEvent:Connect(onResult)
end

return ContestController
