--!strict
--[[
	Boss office doors (2026-10-08, docs/GAMEPLAY_RULES.md "Office doors").

	Every office gets a sliding door in its doorway, built on THIS client, so
	each player sees the doors their own progress opens: a Level 10 player
	and a Level 50 player in the same server see different doors. A closed
	door is a pair of solid panels that stop this player's character (the
	client moves its own character, so local parts block it); a small sign
	beside it says why ("🔒 Requires Level 10", "🔒 Beat Deadline Boss x1")
	or "✓ AVAILABLE" / "✓ BEATEN x3".

	Whether a door is open comes from the one unlock rule the game already
	has (Shared/ProgressionRules) applied by the server to this player's saved
	progress and sent in Profile.Sync (ProgressController). It updates when
	that changes (a defeat, a level-up, an admin unlock), not on a timer.
	Doors aren't tied to the character, so respawning changes nothing.

	A door never closes on someone inside: if a door should close (e.g. an
	admin lowered the level) while the player is in that office or its
	doorway, it waits until they have left.

	Security is NOT the door: a deleted or walked-around door gives nothing,
	because the server refuses hits on a locked boss (CombatService).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ArenaConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ArenaConfig"))

local OfficeDoors = require(script.Parent.Parent.Lib.OfficeDoors)
local ProgressController = require(script.Parent.ProgressController)

local OfficeDoorController = {}

local PANEL_THICKNESS = 0.6
local PANEL_COLOR = Color3.fromRGB(205, 210, 220)
local SIGN_SIZE = Vector3.new(4.2, 1.4, 0.2)
local LOCKED_COLOR = Color3.fromRGB(255, 140, 120)
local OPEN_COLOR = Color3.fromRGB(140, 230, 150)
local SLIDE = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PENDING_CHECK_SECONDS = 1

type Door = {
	Office: ArenaConfig.Office,
	Panels: { BasePart },
	ClosedAt: { CFrame },
	OpenAt: { CFrame },
	Label: TextLabel,
	Open: boolean,
	PendingClose: boolean,
}

local doors: { Door } = {}

local function newPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function buildDoor(office: ArenaConfig.Office, parent: Instance): Door
	local model = Instance.new("Model")
	model.Name = office.BossId .. "_Door"
	local width, height = ArenaConfig.DoorWidth, ArenaConfig.DoorHeight
	local doorZ = office.Center.Z + ArenaConfig.OfficeSize.Z / 2
	local panels: { BasePart } = {}
	local closedAt: { CFrame } = {}
	local openAt: { CFrame } = {}
	for _, side in { -1, 1 } do
		local closed =
			CFrame.new(office.Center.X + side * width / 4, office.Center.Y + height / 2, doorZ)
		-- Open: slid sideways into the wall beside the doorway.
		local open = closed + Vector3.new(side * (width / 2 - 0.3), 0, 0)
		local panel = newPart(
			model,
			"Panel",
			Vector3.new(width / 2, height, PANEL_THICKNESS),
			closed,
			PANEL_COLOR
		)
		panel.CanCollide = true
		-- Pets and hits never notice doors (pets are drawn locally too).
		panel.CanQuery = false
		panel.CanTouch = false
		local stripe = newPart(
			model,
			"Handle",
			Vector3.new(0.25, 1.6, PANEL_THICKNESS + 0.2),
			closed * CFrame.new(-side * (width / 4 - 0.6), 0, 0),
			Color3.fromRGB(110, 115, 130)
		)
		stripe.CanCollide = false
		stripe.CanQuery = false
		stripe.CanTouch = false
		-- Welded to the anchored panel, so it slides with it.
		stripe.Anchored = false
		stripe.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = panel
		weld.Part1 = stripe
		weld.Parent = panel
		table.insert(panels, panel)
		table.insert(closedAt, closed)
		table.insert(openAt, open)
	end

	-- A small sign on the corridor side, beside the doorway.
	local sign = newPart(
		model,
		"Status",
		SIGN_SIZE,
		CFrame.new(office.Center.X + width / 2 + 2.6, office.Center.Y + 7, doorZ + 0.65),
		Color3.fromRGB(35, 38, 52)
	)
	sign.CanCollide = false
	sign.CanQuery = false
	sign.CanTouch = false
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- +Z: the corridor
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.3
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = LOCKED_COLOR
	label.RichText = false
	label.Text = "🔒 LOCKED"
	label.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.05, 0)
	padding.PaddingRight = UDim.new(0.05, 0)
	padding.PaddingTop = UDim.new(0.1, 0)
	padding.PaddingBottom = UDim.new(0.1, 0)
	padding.Parent = label

	model.Parent = parent
	return {
		Office = office,
		Panels = panels,
		ClosedAt = closedAt,
		OpenAt = openAt,
		Label = label,
		Open = false,
		PendingClose = false,
	}
end

local function localRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function move(door: Door, open: boolean, animate: boolean): ()
	door.Open = open
	door.PendingClose = false
	for index, panel in door.Panels do
		-- Open doors stop blocking at once; closing doors block at once.
		panel.CanCollide = not open
		local target = if open then door.OpenAt[index] else door.ClosedAt[index]
		if animate then
			TweenService:Create(panel, SLIDE, { CFrame = target }):Play()
		else
			panel.CFrame = target
		end
	end
end

-- Applies this player's current unlocks to every door.
local function refresh(animate: boolean): ()
	local snapshot = ProgressController.get()
	local root = localRoot()
	for _, door in doors do
		local bossId = door.Office.BossId
		local status = if snapshot then ProgressController.unlockStatus(bossId) else nil
		local defeats = if snapshot then snapshot.BossDefeats[bossId] or 0 else 0
		local state = OfficeDoors.state(status, defeats)
		door.Label.Text = state.Text
		door.Label.TextColor3 = if state.Open then OPEN_COLOR else LOCKED_COLOR
		if state.Open and not door.Open then
			move(door, true, animate)
		elseif not state.Open and door.Open then
			if root and OfficeDoors.isInside(door.Office, root.Position) then
				door.PendingClose = true -- never shut someone in
			else
				move(door, false, animate)
			end
		elseif state.Open then
			door.PendingClose = false
		end
	end
end

function OfficeDoorController.start(): ()
	local folder = Instance.new("Folder")
	folder.Name = "ClientDoors"
	folder.Parent = Workspace
	for _, office in ArenaConfig.Offices do
		table.insert(doors, buildDoor(office, folder))
	end

	-- Closed until progress loads; then snap to the right state, and
	-- animate every change after that.
	local loaded = ProgressController.get() ~= nil
	refresh(false)
	ProgressController.Changed:Connect(function()
		refresh(loaded)
		loaded = true
	end)

	-- Doors waiting to close until the player has left the office.
	while true do
		task.wait(PENDING_CHECK_SECONDS)
		local root = localRoot()
		for _, door in doors do
			if
				door.PendingClose
				and (root == nil or not OfficeDoors.isInside(door.Office, root.Position))
			then
				move(door, false, true)
			end
		end
	end
end

return OfficeDoorController
