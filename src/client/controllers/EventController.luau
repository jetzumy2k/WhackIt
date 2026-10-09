--!strict
--[[
	Active events for players (docs/EVENTS.md). Events.State from the server
	lists what is running; this keeps it for the UI and shows a small
	"🎉 EVENTS" chip under the Menu button (only while something runs). The
	chip opens a short list with countdowns; the countdowns tick once a
	second only while the list is open. Start / end notices are shown by
	AnnouncementController. The Player Panel's Events tab and the Hammer
	Shop's sale prices read from here. Display only: the server decides every
	effect (XP, drops, prices, bosses).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local EventConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("EventConfig"))
local EventRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EventRules"))

local Responsive = require(script.Parent.Parent.Lib.Responsive)

local EventController = {}

local CHIP_COLOR = Color3.fromRGB(235, 120, 60)
local CARD_COLOR = Color3.fromRGB(26, 29, 41)
local TEXT_COLOR = Color3.fromRGB(240, 242, 248)
local MUTED_COLOR = Color3.fromRGB(170, 176, 198)
local HEADING_COLOR = Color3.fromRGB(255, 214, 120)
local ROW_HEIGHT = 62
local MAX_EVENTS_SHOWN = 12

local events: { EventRules.PublicEvent } = {}
local changedEvent = Instance.new("BindableEvent")

-- Fires whenever the server sends a new list.
EventController.Changed = changedEvent.Event

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

-- Events running right now (the server re-sends the list when one ends; this
-- also hides one whose end passed a moment before that message).
function EventController.active(): { EventRules.PublicEvent }
	local now = serverNow()
	local list: { EventRules.PublicEvent } = {}
	for _, event in events do
		if event.StartTime <= now and now < event.EndTime then
			table.insert(list, event)
		end
	end
	return list
end

-- Whole % off a hammer in the Hammer Shop right now (display only).
function EventController.discountPercent(hammerId: string): number
	return EventRules.publicDiscount(events, hammerId, serverNow())
end

function EventController.icon(eventType: string): string
	local info = EventConfig.TypeInfo[eventType]
	return if info then info.Icon else "🎉"
end

local function parseState(payload: unknown): { EventRules.PublicEvent }?
	if typeof(payload) ~= "table" then
		return nil
	end
	local raw = (payload :: { [string]: unknown }).Events
	if typeof(raw) ~= "table" then
		return nil
	end
	local list: { EventRules.PublicEvent } = {}
	for _, entry in raw :: { unknown } do
		local event = EventRules.parsePublic(entry)
		if event and #list < MAX_EVENTS_SHOWN then
			table.insert(list, event)
		end
	end
	return list
end

function EventController.start(): ()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Events"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Under the Menu button (PlayerPanelController, top-left).
	local menuTop = 16
	local chip = Instance.new("TextButton")
	chip.Name = "EventsChip"
	chip.Position = UDim2.fromOffset(16, menuTop + 56)
	chip.Size = UDim2.fromOffset(120, 36)
	chip.BackgroundColor3 = CHIP_COLOR
	chip.TextColor3 = TEXT_COLOR
	chip.Font = Enum.Font.FredokaOne
	chip.AutoButtonColor = true
	chip.Visible = false
	chip.Parent = gui
	Instance.new("UICorner").Parent = chip
	Responsive.capText(chip, 18)

	local list = Instance.new("ScrollingFrame")
	list.Name = "ActiveEvents"
	list.Position = UDim2.fromOffset(16, menuTop + 98)
	list.BackgroundColor3 = CARD_COLOR
	list.BackgroundTransparency = 0.08
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Visible = false
	list.Parent = gui
	Instance.new("UICorner").Parent = list
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = list
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list

	local countdowns: { [TextLabel]: number } = {}

	local function fitList(): ()
		local viewport = Responsive.viewport()
		local width = math.min(300, viewport.X - 32)
		local wanted = 40 + #EventController.active() * (ROW_HEIGHT + 6)
		-- Never more than half the screen: the rest scrolls.
		list.Size = UDim2.fromOffset(width, math.min(wanted, math.floor(viewport.Y * 0.5)))
	end

	local function line(
		parent: Instance,
		text: string,
		size: number,
		color: Color3,
		order: number
	): TextLabel
		local label = Instance.new("TextLabel")
		label.LayoutOrder = order
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, size + 4)
		label.Font = if order == 1 then Enum.Font.GothamBold else Enum.Font.GothamMedium
		label.TextColor3 = color
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.RichText = false
		label.Text = text
		label.Parent = parent
		Responsive.capText(label, size, 10)
		return label
	end

	local function render(): ()
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		table.clear(countdowns)
		local active = EventController.active()
		chip.Visible = #active > 0
		chip.Text = if #active == 1
			then "🎉 1 EVENT"
			else string.format("🎉 %d EVENTS", #active)
		if #active == 0 then
			list.Visible = false
			return
		end
		local title = line(list, "🎉 ACTIVE EVENTS", 16, HEADING_COLOR, 0)
		title.Font = Enum.Font.FredokaOne
		for index, event in active do
			local row = Instance.new("Frame")
			row.LayoutOrder = index
			row.BackgroundTransparency = 1
			row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
			row.Parent = list
			local rowLayout = Instance.new("UIListLayout")
			rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
			rowLayout.Parent = row
			line(row, EventController.icon(event.Type) .. " " .. event.Name, 16, TEXT_COLOR, 1)
			local ends = line(row, "", 14, HEADING_COLOR, 2)
			countdowns[ends] = event.EndTime
			line(row, event.Summary, 13, MUTED_COLOR, 3)
		end
		fitList()
	end

	local function tick(): ()
		local now = serverNow()
		for label, endTime in countdowns do
			label.Text = "Ends in: " .. EventRules.countdown(endTime - now)
		end
	end

	chip.Activated:Connect(function()
		list.Visible = not list.Visible
		if list.Visible then
			render()
			tick()
		end
	end)
	Responsive.onChanged(fitList)

	local stateRemote =
		ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Events"):WaitForChild("State")
	assert(stateRemote:IsA("RemoteEvent"), "Events.State must be a RemoteEvent")
	stateRemote.OnClientEvent:Connect(function(payload: unknown)
		local parsed = parseState(payload)
		if parsed then
			events = parsed
			render()
			changedEvent:Fire()
		end
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	render()

	-- Countdowns only while the list is open; otherwise just a cheap check
	-- that hides an event whose end passed before the server's update.
	while true do
		task.wait(1)
		if list.Visible then
			tick()
		end
		local shown = chip.Visible
		if shown ~= (#EventController.active() > 0) then
			render()
			changedEvent:Fire()
		end
	end
end

return EventController
