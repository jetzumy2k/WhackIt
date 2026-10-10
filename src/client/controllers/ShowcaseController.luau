--!strict
--[[
	The Office Showcase on the client (docs/SHOWCASE.md, Phase 6a).

	  * Gallery window: ⭐ Featured, 🆕 Newest and ❤️ Top this week as cards
	    (avatar, name, furniture, likes, visits, Visit), 🌟 My showcase
	    (share, update, preview, take back, the rules) and, for admins,
	    🛡️ Review (offices hidden by reports).
	  * Showcase bar (bottom centre) while you stand in a read-only copy:
	    whose office it is, ❤️ Like, 🚩 Report and 🚪 Lobby; admins also get
	    Approve, Remove and Feature.
	The server decides everything (ShowcaseService); this only asks and shows.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShowcaseConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ShowcaseConfig"))

local AdminController = require(script.Parent.AdminController)
local HudFormat = require(script.Parent.Parent.Lib.HudFormat)
local PanelKit = require(script.Parent.Parent.Lib.PanelKit)
local Responsive = require(script.Parent.Parent.Lib.Responsive)

local ShowcaseController = {}

local C = PanelKit.Colors
local ACCENT = Color3.fromRGB(240, 190, 70)
local LIKE_COLOR = Color3.fromRGB(225, 90, 120)
local CARD_WIDTH = 170
local CARD_HEIGHT = 214
-- Seconds a gallery page is shown before it's asked for again.
local LIST_REFRESH = 30

export type Entry = {
	UserId: number,
	Name: string,
	Items: number,
	Likes: number,
	Visits: number,
	Reports: number,
	Liked: boolean,
}

type List = { Entries: { Entry }, Available: boolean, Global: boolean, At: number }

type Mine = {
	Available: boolean,
	Global: boolean,
	Reached: boolean,
	Published: boolean,
	Moderation: string,
	Likes: number,
	Visits: number,
	CanPublish: boolean,
	Reason: string,
}

type Room = {
	OwnerId: number,
	Name: string,
	Likes: number,
	Visits: number,
	Liked: boolean,
	Own: boolean,
	Moderation: string?,
}

local localPlayer = Players.LocalPlayer
local mine: Mine? = nil
local room: Room? = nil
local lists: { [string]: List } = {}
local asked: { [string]: number } = {}

local openGallery: ((tab: string?) -> ())? = nil
local refreshGallery: () -> () = function() end
local refreshBar: () -> () = function() end

local function remote(name: string): RemoteEvent
	local found =
		ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Showcase"):WaitForChild(name)
	assert(found:IsA("RemoteEvent"), "Showcase." .. name .. " must be a RemoteEvent")
	return found
end

local function number(value: unknown): number
	return if typeof(value) == "number" and value == value then value else 0
end

local function text(value: unknown): string
	return if typeof(value) == "string" then value else ""
end

-- Payloads ------------------------------------------------------------------------------

local function parseEntries(raw: unknown): { Entry }
	local entries: { Entry } = {}
	if typeof(raw) ~= "table" then
		return entries
	end
	for _, value in raw :: { unknown } do
		if typeof(value) == "table" then
			local data = value :: { [string]: unknown }
			if typeof(data.UserId) == "number" then
				table.insert(entries, {
					UserId = data.UserId :: number,
					Name = text(data.Name),
					Items = number(data.Items),
					Likes = number(data.Likes),
					Visits = number(data.Visits),
					Reports = number(data.Reports),
					Liked = data.Liked == true,
				})
			end
		end
	end
	return entries
end

local function onList(payload: unknown): ()
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	if typeof(data.Tab) ~= "string" then
		return
	end
	lists[data.Tab :: string] = {
		Entries = parseEntries(data.Entries),
		Available = data.Available == true,
		Global = data.Global == true,
		At = os.clock(),
	}
	refreshGallery()
end

local function onState(payload: unknown): ()
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	if data.Kind == "Mine" then
		mine = {
			Available = data.Available == true,
			Global = data.Global == true,
			Reached = data.Reached == true,
			Published = data.Published == true,
			Moderation = text(data.Moderation),
			Likes = number(data.Likes),
			Visits = number(data.Visits),
			CanPublish = data.CanPublish == true,
			Reason = text(data.Reason),
		}
		refreshGallery()
	elseif data.Kind == "Room" then
		if typeof(data.OwnerId) == "number" then
			room = {
				OwnerId = data.OwnerId :: number,
				Name = text(data.Name),
				Likes = number(data.Likes),
				Visits = number(data.Visits),
				Liked = data.Liked == true,
				Own = data.Own == true,
				Moderation = if typeof(data.Moderation) == "string"
					then data.Moderation :: string
					else nil,
			}
		else
			room = nil
		end
		refreshBar()
	end
end

local function ask(tab: string, force: boolean?): ()
	local last = asked[tab]
	if not force and last and os.clock() - last < LIST_REFRESH then
		return
	end
	asked[tab] = os.clock()
	remote("List"):FireServer(tab)
end

-- Public --------------------------------------------------------------------------------

-- Opens the gallery (on `tab`, e.g. "Mine"), from the Social page.
function ShowcaseController.open(tab: string?): ()
	local opener = openGallery
	if opener then
		opener(tab)
	end
end

function ShowcaseController.visit(userId: number): ()
	remote("Visit"):FireServer(userId)
end

-- Your showcase's status for the Social page, e.g. "Shared · ❤️ 3 · 👀 20".
function ShowcaseController.status(): string
	local current = mine
	if current == nil or not current.Available then
		return "Share your office with players in every server."
	end
	if current.Moderation == "Removed" then
		return "A moderator took your showcase down."
	end
	if not current.Published then
		return "Your office isn't shared yet."
	end
	if current.Moderation == "Review" then
		return "Shared · waiting for a moderator before others can see it."
	end
	return string.format(
		"Shared · ❤️ %s · 👀 %s",
		HudFormat.thousands(current.Likes),
		HudFormat.thousands(current.Visits)
	)
end

-- Gallery -------------------------------------------------------------------------------

local function buildGallery(parent: Instance): ()
	local window = PanelKit.window({
		Name = "Showcase",
		Title = "🌟 Office Showcase",
		Subtitle = "Visit offices from every server, like the ones you love, share your own.",
		Accent = ACCENT,
		DisplayOrder = 6,
	}, parent)
	local content = window.Content
	local activeTab = "Featured"
	local tabs: { PanelKit.Tab } = {}
	for _, tab in ShowcaseConfig.Tabs do
		table.insert(tabs, { Id = tab.Id, Label = tab.Label })
	end
	table.insert(tabs, { Id = "Mine", Label = "🏢 My showcase" })
	table.insert(tabs, { Id = "Review", Label = "🛡️ Review" })

	local function setTabVisible(id: string, visible: boolean): ()
		local tab = window.Frame:FindFirstChild(id, true)
		if tab and tab:IsA("GuiObject") then
			tab.Visible = visible
		end
	end

	local function card(grid: Instance, entry: Entry, review: boolean): ()
		local detail = string.format(
			"🪑 %d items · ❤️ %s · 👀 %s",
			entry.Items,
			HudFormat.thousands(entry.Likes),
			HudFormat.thousands(entry.Visits)
		)
		if review then
			detail ..= string.format("\n🚩 %d report(s)", entry.Reports)
		end
		local item = PanelKit.itemCard(grid, entry.Name .. "'s Office", detail, nil, ACCENT)
		local avatar = Instance.new("ImageLabel")
		avatar.Name = "Avatar"
		avatar.AnchorPoint = Vector2.new(0.5, 0.5)
		avatar.Position = UDim2.fromScale(0.5, 0.5)
		avatar.Size = UDim2.fromScale(1, 1)
		avatar.BackgroundTransparency = 1
		avatar.ScaleType = Enum.ScaleType.Fit
		avatar.Image = string.format(
			"rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150",
			math.abs(entry.UserId)
		)
		avatar.Parent = item.Picture
		if entry.UserId == localPlayer.UserId then
			PanelKit.setBadge(item, "You", C.Primary)
		elseif entry.Liked then
			PanelKit.setBadge(item, "❤️ Liked", LIKE_COLOR)
		end
		item.Button.Text = if review then "🛡️ Visit to review" else "Visit"
		item.Button.Activated:Connect(function()
			window:close()
			ShowcaseController.visit(entry.UserId)
		end)
	end

	local function rulesSection(): ()
		local rules = PanelKit.section(content, "📜 How the Showcase works", true, true)
		for _, line in
			{
				string.format(
					"Share your office from Level %d with at least %d pieces of furniture. Others see a copy of it as it was when you shared it, with your display name. Nobody can change anything in it.",
					ShowcaseConfig.MinLevel,
					ShowcaseConfig.MinItems
				),
				string.format(
					"Update it any time (every %d minutes at most). Your likes and visits stay.",
					ShowcaseConfig.PublishCooldown // 60
				),
				"Every player can like an office once, while visiting it. ❤️ Top this week counts likes from Monday 00:00 UTC.",
				"🚩 Report hides an office for you at once. Offices reported by several players are hidden until a moderator looks at them.",
				"⭐ Featured offices are picked by the moderators.",
			}
		do
			PanelKit.text(rules.Body, "• " .. line, "Muted")
		end
	end

	local function minePage(): ()
		local current = mine
		local section = PanelKit.section(content, "🏢 My showcase", false, true)
		if current == nil then
			PanelKit.notice(section.Body, "Loading", "Checking your showcase...")
			return
		end
		if not current.Available then
			PanelKit.notice(section.Body, "Error", "The Showcase isn't available right now.")
			return
		end
		if not current.Global then
			PanelKit.text(
				section.Body,
				"🧪 Studio test: offices are shared with this server only.",
				"Muted"
			)
		end
		PanelKit.text(section.Body, ShowcaseController.status())
		if current.Reason ~= "" and not current.CanPublish then
			PanelKit.text(section.Body, current.Reason, "Muted")
		end
		local row = PanelKit.row(section.Body)
		local share = PanelKit.button(
			row,
			if current.Published then "🔄 Update with my office now" else "🌟 Share my office",
			C.Good
		)
		share.Size = UDim2.new(0.5, -4, 1, 0)
		PanelKit.setDisabled(share, not current.CanPublish)
		share.Activated:Connect(function()
			remote("Publish"):FireServer()
		end)
		if current.Published then
			local preview = PanelKit.button(row, "👀 See it", C.Primary)
			preview.Size = UDim2.new(0.5, -4, 1, 0)
			preview.Activated:Connect(function()
				window:close()
				ShowcaseController.visit(localPlayer.UserId)
			end)
			local takeBack = PanelKit.row(section.Body)
			local remove =
				PanelKit.button(takeBack, "Take my office out of the Showcase", C.Neutral)
			remove.Size = UDim2.fromScale(1, 1)
			remove.Activated:Connect(function()
				remote("Unpublish"):FireServer()
			end)
		end
		rulesSection()
	end

	local function listPage(tab: string): ()
		local list = lists[tab]
		if list == nil then
			PanelKit.notice(content, "Loading", "Loading offices...")
			return
		end
		if not list.Available then
			PanelKit.notice(content, "Error", "The Showcase isn't available right now.")
			return
		end
		if not list.Global then
			PanelKit.text(content, "🧪 Studio test: offices shared in this server only.", "Muted")
		end
		local header = PanelKit.row(content)
		local refresh = PanelKit.button(header, "🔄 Refresh", C.Neutral)
		refresh.Size = UDim2.new(0, 120, 1, 0)
		refresh.Activated:Connect(function()
			ask(tab, true)
		end)
		if #list.Entries == 0 then
			PanelKit.notice(
				content,
				"Empty",
				if tab == "Featured"
					then "No featured offices yet. Look at 🆕 Newest!"
					elseif tab == "Review" then "Nothing to review."
					else "No offices here yet. Share yours from 🏢 My showcase!"
			)
			return
		end
		local grid = PanelKit.grid(content, CARD_WIDTH, CARD_HEIGHT)
		for _, entry in list.Entries do
			card(grid, entry, tab == "Review")
		end
	end

	local function render(): ()
		local admin = AdminController.isAdmin()
		setTabVisible("Review", admin)
		if activeTab == "Review" and not admin then
			activeTab = "Featured"
		end
		window:selectTab(activeTab)
		if not window:isOpen() then
			return
		end
		window:clear()
		if activeTab == "Mine" then
			ask("Mine")
			minePage()
		else
			ask(activeTab)
			listPage(activeTab)
		end
	end
	refreshGallery = render

	window:setTabs(tabs, function(id: string)
		activeTab = id
		render()
	end)
	window:onOpen(function()
		task.defer(render)
	end)
	openGallery = function(tab: string?)
		if tab then
			activeTab = tab
		end
		window:open()
		render()
	end
	render()
end

-- Report picker -----------------------------------------------------------------------------

local function buildReport(parent: Instance): (ownerId: number, name: string) -> ()
	local window = PanelKit.window({
		Name = "ShowcaseReport",
		Title = "🚩 Report this office",
		Subtitle = "What's wrong with it? You won't see it again either way.",
		Accent = C.Danger,
		DisplayOrder = 7,
	}, parent)
	return function(ownerId: number, name: string)
		window:clear()
		PanelKit.text(window.Content, name .. "'s Office", "Heading")
		for _, reason in ShowcaseConfig.ReportReasons do
			local row = PanelKit.row(window.Content)
			local button = PanelKit.button(row, reason.Label, C.Danger)
			button.Size = UDim2.fromScale(1, 1)
			button.Activated:Connect(function()
				window:close()
				remote("Report"):FireServer(ownerId, reason.Id)
			end)
		end
		local row = PanelKit.row(window.Content)
		local cancel = PanelKit.button(row, "Cancel", C.Neutral)
		cancel.Size = UDim2.fromScale(1, 1)
		cancel.Activated:Connect(function()
			window:close()
		end)
		window:open()
	end
end

-- Showcase bar ------------------------------------------------------------------------------

local function barFrame(gui: ScreenGui, name: string, offset: number): Frame
	local bar = Instance.new("Frame")
	bar.Name = name
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -offset)
	bar.Size = UDim2.fromOffset(560, 56)
	bar.BackgroundColor3 = C.Window
	bar.BackgroundTransparency = 0.1
	bar.Visible = false
	bar.Parent = gui
	Instance.new("UICorner").Parent = bar
	local stroke = Instance.new("UIStroke")
	stroke.Color = ACCENT
	stroke.Transparency = 0.4
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
	layout.Padding = UDim.new(0, 8)
	layout.Parent = bar
	return bar
end

local function buildBar(gui: ScreenGui, report: (ownerId: number, name: string) -> ()): ()
	local bar = barFrame(gui, "ShowcaseBar", 70)
	local title = Instance.new("TextLabel")
	title.LayoutOrder = 1
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -330, 1, 0)
	title.Font = PanelKit.FONT_BOLD
	title.TextColor3 = C.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Parent = bar
	PanelKit.setTextSize(title, PanelKit.TEXT_SIZE)

	local like = PanelKit.button(bar, "❤️ Like", LIKE_COLOR)
	like.LayoutOrder = 2
	like.Size = UDim2.new(0, 110, 1, 0)
	like.Activated:Connect(function()
		local current = room
		if current then
			remote("Like"):FireServer(current.OwnerId)
		end
	end)
	local flag = PanelKit.button(bar, "🚩 Report", C.Neutral)
	flag.LayoutOrder = 3
	flag.Size = UDim2.new(0, 100, 1, 0)
	flag.Activated:Connect(function()
		local current = room
		if current then
			report(current.OwnerId, current.Name)
		end
	end)
	local lobby = PanelKit.button(bar, "🚪 Lobby", C.Neutral)
	lobby.LayoutOrder = 4
	lobby.Size = UDim2.new(0, 100, 1, 0)
	lobby.Activated:Connect(function()
		remote("Leave"):FireServer()
	end)

	-- Admins: moderation right where they look at the office.
	local admin = barFrame(gui, "ShowcaseModeration", 132)
	local status = Instance.new("TextLabel")
	status.LayoutOrder = 0
	status.BackgroundTransparency = 1
	status.Size = UDim2.new(0, 110, 1, 0)
	status.Font = PanelKit.FONT_BOLD
	status.TextColor3 = C.Heading
	status.Parent = admin
	PanelKit.setTextSize(status, PanelKit.SMALL_SIZE)
	for order, action in
		{
			{ Id = "Approve", Label = "✅ Approve", Color = C.Good },
			{ Id = "Remove", Label = "🗑️ Remove", Color = C.Danger },
			{ Id = "Feature", Label = "⭐ Feature", Color = ACCENT },
			{ Id = "Unfeature", Label = "Unfeature", Color = C.Neutral },
		}
	do
		local button = PanelKit.button(admin, action.Label, action.Color)
		button.LayoutOrder = order
		button.Size = UDim2.new(0, 100, 1, 0)
		button.Activated:Connect(function()
			local current = room
			if current then
				remote("Moderate"):FireServer(action.Id, current.OwnerId)
			end
		end)
	end

	Responsive.onChanged(function()
		local phone = Responsive.formFactor() == "Phone"
		bar.Size = if phone then UDim2.new(0.9, 0, 0, 50) else UDim2.fromOffset(560, 56)
		admin.Size = if phone then UDim2.new(0.9, 0, 0, 50) else UDim2.fromOffset(560, 56)
	end)

	refreshBar = function()
		local current = room
		bar.Visible = current ~= nil
		admin.Visible = current ~= nil and AdminController.isAdmin()
		if current == nil then
			return
		end
		title.Text = if current.Own
			then "🌟 Your showcase"
			else string.format(
				"🌟 %s's office · ❤️ %s",
				current.Name,
				HudFormat.thousands(current.Likes)
			)
		like.Visible = not current.Own
		flag.Visible = not current.Own
		like.Text = if current.Liked then "❤️ Liked" else "❤️ Like"
		PanelKit.setDisabled(like, current.Liked)
		status.Text = if current.Moderation then "Status: " .. current.Moderation else ""
	end
end

function ShowcaseController.start(): ()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	buildGallery(playerGui)
	local report = buildReport(playerGui)
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShowcaseHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 3
	gui.Parent = playerGui
	buildBar(gui, report)

	remote("List").OnClientEvent:Connect(onList)
	remote("State").OnClientEvent:Connect(onState)
end

return ShowcaseController
