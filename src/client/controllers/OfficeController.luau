--!strict
--[[
	Personal offices on the client (docs/OFFICES.md). Display and input only:
	every trip, placement, move, removal and privacy change is a request the
	server checks (OfficeService); the server's furniture and Profile.Sync
	are always the truth.

	  * Directory: who has an office in this server and its privacy
	    (Office.Directory), for the Player Panel's Social page.
	  * Office bar (bottom centre) while you stand in an office: whose it is,
	    "✏️ Edit" in your own, and "🚪 Lobby".
	  * Edit mode (your own office only): a furniture strip with category
	    tabs, a see-through preview that follows the pointer (mouse), the
	    last tap (touch) or the screen centre (gamepad), snapped to whole
	    studs and tinted green or red by the same rules the server uses
	    (Shared/FurnitureRules). Click / tap / X selects placed furniture to
	    move, turn or remove it. The hammer is put away while editing so a
	    click never swings it.

	Nothing runs per frame outside edit mode; the preview follows the
	pointer with one RenderStepped connection that exists only while a
	preview is showing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local FurnitureConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("FurnitureConfig"))
local FurnitureModel =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FurnitureModel"))
local FurnitureRules =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FurnitureRules"))
local OfficeConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("OfficeConfig"))

local GamepadNav = require(script.Parent.Parent.Lib.GamepadNav)
local PanelKit = require(script.Parent.Parent.Lib.PanelKit)
local ProgressController = require(script.Parent.ProgressController)
local Responsive = require(script.Parent.Parent.Lib.Responsive)
local UIController = require(script.Parent.UIController)

export type Office = {
	UserId: number,
	Name: string,
	Username: string,
	Privacy: string,
	Slot: number,
}

type Mode = "None" | "Placing" | "Moving"

local OfficeController = {}

local changedEvent = Instance.new("BindableEvent")
-- Fires when the directory or the room you stand in changes.
OfficeController.Changed = changedEvent.Event

-- Placed furniture carries its layout id (OfficeService.ITEM_ID_ATTRIBUTE).
local ITEM_ID_ATTRIBUTE = "OfficeItemId"
local LOCATION_CHECK_SECONDS = 0.5
local VALID_COLOR = Color3.fromRGB(90, 220, 120)
local INVALID_COLOR = Color3.fromRGB(235, 80, 80)
local SELECTED_COLOR = Color3.fromRGB(110, 170, 255)
local C = PanelKit.Colors

local localPlayer = Players.LocalPlayer
local offices: { Office } = {}
local slotCount = 0
local currentSlot: number? = nil

local function remote(name: string): RemoteEvent
	local found =
		ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Office"):WaitForChild(name)
	assert(found:IsA("RemoteEvent"), "Office." .. name .. " must be a RemoteEvent")
	return found
end

-- Directory ---------------------------------------------------------------------

local function parseDirectory(payload: unknown): ()
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	local list: { Office } = {}
	if typeof(data.Offices) == "table" then
		for _, raw in data.Offices :: { unknown } do
			if typeof(raw) == "table" then
				local entry = raw :: { [string]: unknown }
				local userId, name, username = entry.UserId, entry.Name, entry.Username
				local privacy, slot = entry.Privacy, entry.Slot
				if
					typeof(userId) == "number"
					and typeof(name) == "string"
					and typeof(username) == "string"
					and FurnitureRules.isPrivacy(privacy)
					and typeof(slot) == "number"
				then
					table.insert(list, {
						UserId = userId,
						Name = name,
						Username = username,
						Privacy = privacy :: string,
						Slot = slot,
					})
				end
			end
		end
	end
	offices = list
	slotCount = if typeof(data.SlotCount) == "number" then data.SlotCount else 0
	changedEvent:Fire()
end

function OfficeController.offices(): { Office }
	return offices
end

local function bySlot(slot: number?): Office?
	for _, office in offices do
		if office.Slot == slot then
			return office
		end
	end
	return nil
end

function OfficeController.mine(): Office?
	for _, office in offices do
		if office.UserId == localPlayer.UserId then
			return office
		end
	end
	return nil
end

-- The office you're standing in (its owner's entry), or nil.
function OfficeController.current(): Office?
	return if currentSlot then bySlot(currentSlot) else nil
end

function OfficeController.isInOwnOffice(): boolean
	local mine = OfficeController.mine()
	return mine ~= nil and currentSlot == mine.Slot
end

-- Requests (the server decides) -----------------------------------------------------

-- Your own office when `userId` is nil.
function OfficeController.goTo(userId: number?): ()
	remote("Go"):FireServer(userId)
end

function OfficeController.returnToLobby(): ()
	remote("Return"):FireServer()
end

function OfficeController.setPrivacy(mode: string): ()
	remote("SetPrivacy"):FireServer(mode)
end

-- Edit mode -----------------------------------------------------------------------

local editing = false
local mode: Mode = "None"
local itemKey: string? = nil -- what the preview shows
local movingId: number? = nil
local selectedId: number? = nil
local rotation = 0
local spot: Vector2? = nil -- room-local whole studs
local valid = false
local reason: string? = nil
local ghost: Model? = nil
local ghostHighlight: Highlight? = nil
local selectedHighlight: Highlight? = nil
local lastTap: Vector2? = nil
local followConnection: RBXScriptConnection? = nil
local category = FurnitureConfig.Categories[1].Id

-- UI built in start(); refresh functions set there.
-- refreshEditor: panel, cards (in place) and actions; refreshActions: only
-- the hint and buttons (cheap, runs as the preview moves); rebuildCards:
-- when the category changes.
local refreshEditor: () -> () = function() end
local refreshActions: () -> () = function() end
local rebuildCards: () -> () = function() end
local refreshBar: () -> () = function() end
local furnitureWatch: RBXScriptConnection? = nil

local function roomModel(slot: number): Model?
	local wing = Workspace:FindFirstChild("OfficeWing")
	if wing == nil then
		return nil
	end
	for _, child in wing:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("OfficeSlot") == slot then
			return child
		end
	end
	return nil
end

local function myLayout(): (FurnitureRules.Layout, FurnitureRules.Owned, number)
	local snapshot = ProgressController.get()
	if snapshot == nil then
		return {}, {}, 1
	end
	return snapshot.OfficeLayout, snapshot.Furniture, snapshot.Level
end

local function floorOrigin(): CFrame?
	local mine = OfficeController.mine()
	return if mine then CFrame.new(FurnitureRules.slotOrigin(mine.Slot)) else nil
end

-- The screen point the preview follows: mouse, last tap, or screen centre.
local function pointer(): Vector2?
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return lastTap
	end
	if GamepadNav.usingGamepad() then
		local camera = Workspace.CurrentCamera
		return if camera then camera.ViewportSize / 2 else nil
	end
	return UserInputService:GetMouseLocation()
end

-- What the pointer hits in your own room (ignoring the preview).
local function pointAt(screen: Vector2): RaycastResult?
	local camera = Workspace.CurrentCamera
	local mine = OfficeController.mine()
	local room = if mine then roomModel(mine.Slot) else nil
	if camera == nil or room == nil then
		return nil
	end
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { room }
	return Workspace:Raycast(ray.Origin, ray.Direction * 200, params)
end

local function clearGhost(): ()
	if ghost then
		ghost:Destroy()
	end
	ghost, ghostHighlight = nil, nil
end

local function buildGhost(key: string): ()
	clearGhost()
	local item = FurnitureConfig.ByKey[key]
	if item == nil then
		return
	end
	local model = FurnitureModel.build(item)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CastShadow = false
			part.Transparency = math.max(0.45, part.Transparency)
		end
	end
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 0.55
	highlight.OutlineTransparency = 0.1
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = model
	model.Parent = Workspace.CurrentCamera -- local only
	ghost, ghostHighlight = model, highlight
end

local function updateValidity(): ()
	local key = itemKey
	local at = spot
	if key == nil or at == nil then
		valid, reason = false, "Point at (or tap) the floor of your office."
	else
		local layout, owned, level = myLayout()
		local ok, why =
			FurnitureRules.check(layout, owned, key, at.X, at.Y, rotation, movingId, level)
		valid, reason = ok, why
	end
	local highlight = ghostHighlight
	if highlight then
		local color = if valid then VALID_COLOR else INVALID_COLOR
		highlight.FillColor = color
		highlight.OutlineColor = color
	end
	refreshActions()
end

local function follow(): ()
	local screen = pointer()
	local origin = floorOrigin()
	local model = ghost
	if screen == nil or origin == nil or model == nil then
		return
	end
	local hit = pointAt(screen)
	if hit == nil then
		return
	end
	local roomLocal = origin:PointToObjectSpace(hit.Position)
	local newSpot = Vector2.new(math.round(roomLocal.X), math.round(roomLocal.Z))
	if spot ~= newSpot then
		spot = newSpot
		model:PivotTo(FurnitureModel.placement(origin, newSpot.X, newSpot.Y, rotation))
		updateValidity()
	end
end

local function setFollowing(on: boolean): ()
	if on and followConnection == nil then
		followConnection = RunService.RenderStepped:Connect(follow)
	elseif not on and followConnection then
		followConnection:Disconnect()
		followConnection = nil
	end
end

local function selectItem(id: number?): ()
	selectedId = id
	if selectedHighlight then
		selectedHighlight:Destroy()
		selectedHighlight = nil
	end
	local mine = OfficeController.mine()
	local room = if mine then roomModel(mine.Slot) else nil
	local furniture = if room then room:FindFirstChild("Furniture") else nil
	if id and furniture then
		for _, model in furniture:GetChildren() do
			if model:GetAttribute(ITEM_ID_ATTRIBUTE) == id then
				local highlight = Instance.new("Highlight")
				highlight.FillColor = SELECTED_COLOR
				highlight.OutlineColor = SELECTED_COLOR
				highlight.FillTransparency = 0.7
				highlight.Parent = model
				selectedHighlight = highlight
			end
		end
	end
	refreshActions()
end

local function stopPreview(): ()
	mode, itemKey, movingId, spot = "None", nil, nil, nil
	setFollowing(false)
	clearGhost()
	refreshEditor()
end

-- The server redraws the room after every change: keep the selection
-- highlight on the new copy of the selected furniture.
local function watchFurniture(on: boolean): ()
	if furnitureWatch then
		furnitureWatch:Disconnect()
		furnitureWatch = nil
	end
	local mine = OfficeController.mine()
	local room = if on and mine then roomModel(mine.Slot) else nil
	local furniture = if room then room:FindFirstChild("Furniture") else nil
	if furniture then
		furnitureWatch = furniture.ChildAdded:Connect(function()
			if selectedId then
				task.defer(selectItem, selectedId)
			end
		end)
	end
end

local function startPlacing(key: string): ()
	selectItem(nil)
	mode, itemKey, movingId, spot = "Placing", key, nil, nil
	buildGhost(key)
	setFollowing(true)
	updateValidity()
	refreshEditor()
end

local function startMoving(): ()
	local layout = myLayout()
	local entry = if selectedId then FurnitureRules.find(layout, selectedId) else nil
	if entry == nil then
		return
	end
	selectItem(nil)
	mode, itemKey, movingId, rotation, spot = "Moving", entry.Item, entry.Id, entry.R, nil
	buildGhost(entry.Item)
	setFollowing(true)
	updateValidity()
	refreshEditor()
end

local function rotate(): ()
	if mode ~= "None" then
		rotation = (rotation + 90) % 360
		spot = nil -- re-place the preview at the new angle on the next frame
		return
	end
	-- Turning placed furniture is a move to the same spot.
	local layout = myLayout()
	local entry = if selectedId then FurnitureRules.find(layout, selectedId) else nil
	if entry then
		remote("Move"):FireServer(entry.Id, entry.X, entry.Z, (entry.R + 90) % 360)
	end
end

local function confirm(): ()
	local at = spot
	if mode == "None" or at == nil then
		return
	end
	if not valid then
		UIController.showToast(reason or "You can't put that there.")
		return
	end
	if mode == "Placing" and itemKey then
		remote("Place"):FireServer(itemKey, at.X, at.Y, rotation)
		-- Stay in placing mode so several can be set down in a row.
	elseif mode == "Moving" and movingId then
		remote("Move"):FireServer(movingId, at.X, at.Y, rotation)
		stopPreview()
	end
end

local function removeSelected(): ()
	if selectedId then
		remote("RemoveItem"):FireServer(selectedId)
		selectItem(nil)
	end
end

-- Click / tap / X with no preview: pick the furniture under the pointer.
local function pickAt(screen: Vector2): ()
	local hit = pointAt(screen)
	local instance: Instance? = if hit then hit.Instance else nil
	while instance and instance:GetAttribute(ITEM_ID_ATTRIBUTE) == nil do
		instance = instance.Parent
	end
	local id = if instance then instance:GetAttribute(ITEM_ID_ATTRIBUTE) else nil
	selectItem(if typeof(id) == "number" then id else nil)
end

local function putHammerAway(): ()
	local character = localPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		humanoid:UnequipTools()
	end
end

local function takeHammerOut(): ()
	local character = localPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	local tool = if backpack then backpack:FindFirstChildOfClass("Tool") else nil
	if humanoid and tool then
		humanoid:EquipTool(tool)
	end
end

function OfficeController.isEditing(): boolean
	return editing
end

function OfficeController.setEditing(on: boolean): ()
	if on and not OfficeController.isInOwnOffice() then
		return
	end
	if editing == on then
		return
	end
	editing = on
	stopPreview()
	selectItem(nil)
	watchFurniture(on)
	if on then
		putHammerAway()
		rebuildCards()
	else
		takeHammerOut()
	end
	refreshBar()
	refreshEditor()
end

-- UI -------------------------------------------------------------------------------

local function buildBar(gui: ScreenGui): ()
	local bar = Instance.new("Frame")
	bar.Name = "OfficeBar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -70)
	bar.Size = UDim2.fromOffset(460, 56)
	bar.BackgroundColor3 = C.Window
	bar.BackgroundTransparency = 0.1
	bar.Visible = false
	bar.Parent = gui
	Instance.new("UICorner").Parent = bar
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(460, 56)
	limit.Parent = bar
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 5)
	padding.PaddingBottom = UDim.new(0, 5)
	padding.Parent = bar
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = bar

	local title = Instance.new("TextLabel")
	title.LayoutOrder = 1
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -216, 1, 0)
	title.Font = PanelKit.FONT_BOLD
	title.TextColor3 = C.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = bar
	PanelKit.setTextSize(title, PanelKit.TEXT_SIZE)

	local edit = PanelKit.button(bar, "✏️ Edit", C.Good)
	edit.LayoutOrder = 2
	edit.Size = UDim2.new(0, 100, 1, 0)
	edit.Activated:Connect(function()
		OfficeController.setEditing(true)
	end)
	local lobby = PanelKit.button(bar, "🚪 Lobby", C.Neutral)
	lobby.LayoutOrder = 3
	lobby.Size = UDim2.new(0, 100, 1, 0)
	lobby.Activated:Connect(function()
		OfficeController.setEditing(false)
		OfficeController.returnToLobby()
	end)

	Responsive.onChanged(function()
		bar.Size = if Responsive.formFactor() == "Phone"
			then UDim2.new(0.6, 0, 0, 50)
			else UDim2.fromOffset(460, 56)
	end)

	refreshBar = function()
		local office = OfficeController.current()
		bar.Visible = office ~= nil and not editing
		if office == nil then
			return
		end
		local own = office.UserId == localPlayer.UserId
		title.Text = if own then "🏢 Your office" else "🏢 " .. office.Name .. "'s office"
		edit.Visible = own
		title.Size = UDim2.new(1, if own then -216 else -108, 1, 0)
	end
end

local function buildEditor(gui: ScreenGui): ()
	local panel = Instance.new("Frame")
	panel.Name = "OfficeEditor"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -8)
	panel.Size = UDim2.new(0.96, 0, 0, 214)
	panel.BackgroundColor3 = C.Window
	panel.BackgroundTransparency = 0.05
	panel.Visible = false
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = panel
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(940, 214)
	limit.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = panel
	local stack = Instance.new("UIListLayout")
	stack.SortOrder = Enum.SortOrder.LayoutOrder
	stack.Padding = UDim.new(0, 6)
	stack.Parent = panel

	local function strip(order: number, height: number, scrolls: boolean): GuiObject
		local frame: GuiObject
		if scrolls then
			local scroller = Instance.new("ScrollingFrame")
			scroller.ScrollingDirection = Enum.ScrollingDirection.X
			scroller.AutomaticCanvasSize = Enum.AutomaticSize.X
			scroller.CanvasSize = UDim2.new()
			scroller.ScrollBarThickness = 4
			scroller.BorderSizePixel = 0
			frame = scroller
		else
			frame = Instance.new("Frame")
		end
		frame.LayoutOrder = order
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.new(1, 0, 0, height)
		frame.Parent = panel
		local row = Instance.new("UIListLayout")
		row.FillDirection = Enum.FillDirection.Horizontal
		row.VerticalAlignment = Enum.VerticalAlignment.Center
		row.SortOrder = Enum.SortOrder.LayoutOrder
		row.Padding = UDim.new(0, 6)
		row.Parent = frame
		return frame
	end

	local tabs = strip(1, 40, true)
	local cards = strip(2, 70, true)
	local actions = strip(3, 46, false)

	local tabButtons: { [string]: TextButton } = {}
	for index, info in FurnitureConfig.Categories do
		local button = PanelKit.button(tabs, info.Label, C.Neutral)
		button.LayoutOrder = index
		button.Size = UDim2.new(0, math.max(110, 12 + #info.Label * 8), 1, 0)
		button.Activated:Connect(function()
			category = info.Id
			rebuildCards()
			refreshEditor()
		end)
		tabButtons[info.Id] = button
	end
	local done = PanelKit.button(tabs, "✓ Done", C.Good)
	done.Name = "Close"
	done.LayoutOrder = 100
	done.Size = UDim2.new(0, 96, 1, 0)
	done.Activated:Connect(function()
		OfficeController.setEditing(false)
	end)

	local hint = Instance.new("TextLabel")
	hint.LayoutOrder = 1
	hint.BackgroundTransparency = 1
	hint.Size = UDim2.new(1, -440, 1, 0)
	hint.Font = PanelKit.FONT
	hint.TextColor3 = C.Muted
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextWrapped = true
	hint.Parent = actions
	PanelKit.setTextSize(hint, PanelKit.SMALL_SIZE)
	local function action(order: number, text: string, color: Color3, run: () -> ()): TextButton
		local button = PanelKit.button(actions, text, color)
		button.LayoutOrder = order
		button.Size = UDim2.new(0, 104, 1, 0)
		button.Activated:Connect(run)
		return button
	end
	local rotateButton = action(2, "⟳ Turn", C.Primary, rotate)
	local placeButton = action(3, "✓ Place", C.Good, confirm)
	local moveButton = action(4, "✥ Move", C.Primary, startMoving)
	local removeButton = action(5, "🗑 Remove", C.Danger, removeSelected)
	local cancelButton = action(6, "✕ Cancel", C.Neutral, function()
		stopPreview()
		selectItem(nil)
	end)
	cancelButton.Name = "Cancel"

	-- B: drop the preview or selection first, then leave edit mode.
	GamepadNav.watch(panel, function()
		if mode ~= "None" or selectedId then
			stopPreview()
			selectItem(nil)
		else
			OfficeController.setEditing(false)
		end
	end)

	-- Cards of the current category: key -> button (rebuilt per category,
	-- updated in place otherwise so a gamepad selection stays put).
	local cardButtons: { [string]: TextButton } = {}
	local emptyCard: TextButton? = nil

	rebuildCards = function()
		for _, button in cardButtons do
			button:Destroy()
		end
		table.clear(cardButtons)
		if emptyCard then
			emptyCard:Destroy()
			emptyCard = nil
		end
		for index, item in FurnitureConfig.List do
			if item.Category == category then
				local card = PanelKit.button(cards, item.Name, C.Card)
				card.LayoutOrder = index
				card.Size = UDim2.new(0, 140, 1, -6)
				PanelKit.setTextSize(card, PanelKit.SMALL_SIZE)
				card.Activated:Connect(function()
					startPlacing(item.Key)
				end)
				cardButtons[item.Key] = card
			end
		end
		if next(cardButtons) == nil then
			local empty = PanelKit.button(cards, "Nothing here yet.", C.Card)
			empty.Size = UDim2.new(0, 320, 1, -6)
			PanelKit.setDisabled(empty, true)
			emptyCard = empty
		end
		for id, button in tabButtons do
			PanelKit.setColor(button, if id == category then C.Primary else C.Neutral)
		end
	end

	refreshActions = function()
		local layout = myLayout()
		local previewing = mode ~= "None"
		rotateButton.Visible = previewing or selectedId ~= nil
		placeButton.Visible = previewing
		placeButton.Text = if mode == "Moving" then "✓ Move here" else "✓ Place"
		PanelKit.setDisabled(placeButton, not valid)
		moveButton.Visible = not previewing and selectedId ~= nil
		removeButton.Visible = not previewing and selectedId ~= nil
		cancelButton.Visible = previewing or selectedId ~= nil
		hint.Text = if previewing
			then (if valid then "Looks good! Click or tap ✓ to set it down." else reason or "")
			elseif selectedId then "Selected. Move, turn or remove it."
			else string.format(
				"Pick furniture below, or click / tap something to change it.  %d / %d items",
				#layout,
				OfficeConfig.MaxItems
			)
	end

	refreshEditor = function()
		panel.Visible = editing
		if not editing then
			return
		end
		local layout, owned, level = myLayout()
		for key, card in cardButtons do
			local item = FurnitureConfig.ByKey[key]
			local left = FurnitureRules.available(layout, owned, key, nil, level)
			local status = if item.Tier == "Special"
				then string.format("%d left", left)
				elseif left <= 0 then string.format("🔒 Lv %d", item.MinLevel or 1)
				else "Free"
			card.Text = item.Name .. "\n" .. status
			PanelKit.setColor(
				card,
				if itemKey == key and mode == "Placing" then C.Primary else C.Card
			)
			PanelKit.setDisabled(card, left <= 0)
		end
		refreshActions()
	end
end

-- Start ------------------------------------------------------------------------------

function OfficeController.start(): ()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Office"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 3
	buildBar(gui)
	buildEditor(gui)
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	remote("Directory").OnClientEvent:Connect(function(payload: unknown)
		parseDirectory(payload)
		refreshBar()
	end)
	ProgressController.Changed:Connect(function()
		if editing then
			if mode ~= "None" then
				updateValidity()
			end
			refreshEditor()
		end
	end)

	-- Pointer input while editing (GUI clicks are ignored: `processed`).
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not editing then
			return
		end
		if input.UserInputType == Enum.UserInputType.Touch and not processed then
			local tap = Vector2.new(input.Position.X, input.Position.Y)
			lastTap = tap
			if mode == "None" then
				pickAt(tap)
			end
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 and not processed then
			if mode == "None" then
				pickAt(UserInputService:GetMouseLocation())
			else
				confirm()
			end
		elseif input.KeyCode == Enum.KeyCode.ButtonX then
			local camera = Workspace.CurrentCamera
			if mode ~= "None" then
				confirm()
			elseif camera then
				pickAt(camera.ViewportSize / 2)
			end
		elseif
			input.KeyCode == Enum.KeyCode.ButtonL1
			or input.KeyCode == Enum.KeyCode.ButtonR1
			or (input.KeyCode == Enum.KeyCode.R and not processed)
		then
			rotate()
		elseif
			(input.KeyCode == Enum.KeyCode.Delete or input.KeyCode == Enum.KeyCode.Backspace)
			and not processed
		then
			removeSelected()
		end
	end)

	-- Never swing while editing: a hammer taken out (e.g. key 1) goes away.
	local function watchCharacter(character: Model): ()
		character.ChildAdded:Connect(function(child: Instance)
			if editing and child:IsA("Tool") then
				task.defer(putHammerAway)
			end
		end)
	end
	if localPlayer.Character then
		watchCharacter(localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(function(character: Model)
		OfficeController.setEditing(false)
		watchCharacter(character)
	end)

	-- Where you are: a cheap check twice a second.
	while true do
		task.wait(LOCATION_CHECK_SECONDS)
		local character = localPlayer.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local slot = if root and root:IsA("BasePart")
			then FurnitureRules.slotAt(root.Position, slotCount)
			else nil
		if slot ~= currentSlot then
			currentSlot = slot
			if editing and not OfficeController.isInOwnOffice() then
				OfficeController.setEditing(false)
			end
			refreshBar()
			changedEvent:Fire()
		end
	end
end

return OfficeController
