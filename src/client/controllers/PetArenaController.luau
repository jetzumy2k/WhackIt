--!strict
--[[
	The Pet Arena on the client (docs/PET_ARENA.md).

	  * Window (🏢 Social → Pet Arena, or the Arena sign at the Recreation
	    Center): pick one of your pets (its battle stats shown), then fight
	    the 🏆 Trainers ladder or 🤝 Challenge a player in the server.
	  * Battle screen (PanelKit.gameScreen; the world dims and the arena
	    window closes): the two pets face each other on a little stage (a
	    ViewportFrame with Lib/PetVisual pets), fighter cards with Pep bars
	    (green, gold when low, red when nearly dizzy) and a ⚡ CHARGED badge,
	    a log of the last round, the round and (player battles) the turn
	    timer in the header, and three moves with a one-line hint each:
	    💥 Boop, ⚡ Charge, 🛡️ Guard (keys 1 / 2 / 3). The X asks before
	    giving up. Boops lunge and the target wobbles, a guard puts up a
	    bubble, a charged pet glows, the loser gets dizzy stars.
	  * Incoming challenges and results as notification cards.
	The server runs every battle (PetArenaService); this only asks and shows.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local PetArenaConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("PetArenaConfig"))
local PetArenaRules =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PetArenaRules"))
local PetConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("PetConfig"))

local AnnouncementController = require(script.Parent.AnnouncementController)
local PanelKit = require(script.Parent.Parent.Lib.PanelKit)
local PetVisual = require(script.Parent.Parent.Lib.PetVisual)
local ProgressController = require(script.Parent.ProgressController)
local Responsive = require(script.Parent.Parent.Lib.Responsive)
local UiTokens = require(script.Parent.Parent.Lib.UiTokens)

local PetArenaController = {}

local C = PanelKit.Colors
local ACCENT = Color3.fromRGB(255, 150, 90)
local CARD_WIDTH = 170
local CARD_HEIGHT = 222
local LUNGE_SECONDS = 0.45

type FighterView = {
	Name: string,
	Species: string,
	Rarity: string,
	Pep: number,
	MaxPep: number,
	Power: number,
	Speed: number,
	Crit: number,
	Charged: boolean,
}

type EventView = { Side: string, Move: string, Damage: number, Lucky: boolean, Guarded: boolean }

type BattleView = {
	Kind: string,
	BattleId: string,
	You: string,
	Vs: string,
	Round: number,
	A: FighterView,
	B: FighterView,
	Events: { EventView },
	Waiting: boolean,
	TurnLeft: number,
}

local localPlayer = Players.LocalPlayer
local selectedPetId: string? = nil
local openWindow: ((tab: string?) -> ())? = nil
local showBattle: (view: BattleView) -> () = function() end
local endBattle: () -> () = function() end
local closeArenaWindow: () -> () = function() end

local function remote(name: string): RemoteEvent
	local found =
		ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PetArena"):WaitForChild(name)
	assert(found:IsA("RemoteEvent"), "PetArena." .. name .. " must be a RemoteEvent")
	return found
end

local function number(value: unknown): number
	return if typeof(value) == "number" and value == value then value else 0
end

local function text(value: unknown): string
	return if typeof(value) == "string" then value else ""
end

local function emojiOf(species: string): string
	local info = PetConfig.ById[species]
	return if info then info.Emoji else "🐾"
end

local function nameOf(species: string): string
	local info = PetConfig.ById[species]
	return if info then info.Name else species
end

-- Your pets, best first, and the one picked for battle (default: equipped, else the best).
local function myPets(): { any }
	local snapshot = ProgressController.get()
	local pets = if snapshot then table.clone(snapshot.Pets) else {}
	table.sort(pets, function(a: any, b: any)
		local ra = (PetConfig.RarityInfo[a.Rarity] or { Order = 0 }).Order
		local rb = (PetConfig.RarityInfo[b.Rarity] or { Order = 0 }).Order
		if ra ~= rb then
			return ra > rb
		end
		return a.Id < b.Id
	end)
	return pets
end

local function pickedPet(): any?
	local pets = myPets()
	for _, pet in pets do
		if pet.Id == selectedPetId then
			return pet
		end
	end
	local snapshot = ProgressController.get()
	for _, pet in pets do
		if snapshot and pet.Id == snapshot.EquippedPetId then
			return pet
		end
	end
	return pets[1]
end

local function statsLine(species: string, rarity: string, buffs: { any }): string
	local stats = PetArenaRules.statsFor(species, rarity, buffs)
	return string.format(
		"💚 %d Pep · 💥 %d · 💨 %d · 🍀 %d%%",
		stats.MaxPep,
		math.floor(stats.Power + 0.5),
		stats.Speed,
		math.floor(stats.Crit * 100 + 0.5)
	)
end

-- Payloads ----------------------------------------------------------------------------

local function parseFighter(raw: unknown): FighterView
	local empty: { [string]: unknown } = {}
	local data = if typeof(raw) == "table" then raw :: { [string]: unknown } else empty
	return {
		Name = text(data.Name),
		Species = text(data.Species),
		Rarity = text(data.Rarity),
		Pep = number(data.Pep),
		MaxPep = math.max(1, number(data.MaxPep)),
		Power = number(data.Power),
		Speed = number(data.Speed),
		Crit = number(data.Crit),
		Charged = data.Charged == true,
	}
end

local function parseView(payload: { [string]: unknown }): BattleView
	local events: { EventView } = {}
	if typeof(payload.Events) == "table" then
		for _, raw in payload.Events :: { unknown } do
			if typeof(raw) == "table" then
				local data = raw :: { [string]: unknown }
				table.insert(events, {
					Side = text(data.Side),
					Move = text(data.Move),
					Damage = number(data.Damage),
					Lucky = data.Lucky == true,
					Guarded = data.Guarded == true,
				})
			end
		end
	end
	return {
		Kind = text(payload.Kind),
		BattleId = text(payload.BattleId),
		You = if payload.You == "B" then "B" else "A",
		Vs = text(payload.Vs),
		Round = number(payload.Round),
		A = parseFighter(payload.A),
		B = parseFighter(payload.B),
		Events = events,
		Waiting = payload.Waiting == true,
		TurnLeft = number(payload.TurnLeft),
	}
end

local function onState(payload: unknown): ()
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	if data.Kind == "Challenge" then
		local fromId = number(data.FromUserId)
		AnnouncementController.show({
			Title = "🐾 PET BATTLE CHALLENGE",
			Body = string.format(
				"%s challenges you with a %s %s!",
				text(data.FromName),
				text(data.Rarity),
				nameOf(text(data.Species))
			),
			Detail = "Your picked pet battles for you (Pet Arena → pick one).",
			Accent = ACCENT,
			Seconds = math.max(5, number(data.Seconds) - 2),
			ActionLabel = "ACCEPT",
			OnAction = function()
				local pet = pickedPet()
				if pet == nil then
					return
				end
				remote("Answer"):FireServer(fromId, true, pet.Id)
			end,
		})
		return
	end
	showBattle(parseView(data))
end

local function onResult(payload: unknown): ()
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	local outcome = text(data.Outcome)
	local parts: { string } = {}
	if data.Rewarded == true then
		table.insert(parts, string.format("+%d coins", number(data.Coins)))
		table.insert(parts, string.format("+%d XP", number(data.Xp)))
		local supply = text(data.Supply)
		if supply ~= "" then
			table.insert(parts, supply .. " (in your office storage)")
		end
	else
		table.insert(parts, "No reward this time (today's battle rewards are used up).")
	end
	task.delay(1.2, function()
		endBattle()
		AnnouncementController.show({
			Title = if outcome == "Won"
				then "🏆 YOUR PET WON!"
				elseif outcome == "Lost" then "💫 YOUR PET GOT DIZZY"
				else "🤝 IT'S A DRAW",
			Body = if outcome == "Won"
				then "What a battle! Your pet booped its way to victory."
				elseif outcome == "Lost" then "Good try! Charge and Guard can turn a battle around."
				else "Both pets are out of Pep. Nobody wins this one.",
			Detail = table.concat(parts, " · "),
			Accent = if outcome == "Won" then C.Good else ACCENT,
			Celebrate = outcome == "Won",
			Seconds = 6,
		})
	end)
end

-- Public --------------------------------------------------------------------------------

function PetArenaController.open(tab: string?): ()
	local opener = openWindow
	if opener then
		opener(tab)
	end
end

-- Window ----------------------------------------------------------------------------

local function buildWindow(parent: Instance): ()
	local window = PanelKit.window({
		Name = "PetArena",
		Title = "🐾 Pet Arena",
		Subtitle = "Cartoon pet battles: Boop, Charge, Guard. The loser just gets dizzy.",
		Accent = ACCENT,
		DisplayOrder = 6,
	}, parent)
	local content = window.Content
	local activeTab = "Trainers"

	local function petPicker(): ()
		local section = PanelKit.section(content, "🐾 Your fighter", false, true)
		local pets = myPets()
		if #pets == 0 then
			PanelKit.notice(
				section.Body,
				"Empty",
				"Hatch a pet first (Pet Incubation Center or the Store's eggs)."
			)
			return
		end
		local picked = pickedPet()
		if picked then
			PanelKit.text(
				section.Body,
				string.format(
					"%s %s (%s): %s",
					emojiOf(picked.Species),
					nameOf(picked.Species),
					picked.Rarity,
					statsLine(picked.Species, picked.Rarity, picked.Buffs)
				)
			)
		end
		local grid = PanelKit.grid(section.Body, 120, 44)
		for index, pet in pets do
			if index > 24 then
				break
			end
			local chosen = picked ~= nil and pet.Id == picked.Id
			local button = PanelKit.button(
				grid,
				emojiOf(pet.Species) .. " " .. nameOf(pet.Species),
				if chosen then ACCENT else C.Neutral
			)
			button.Activated:Connect(function()
				selectedPetId = pet.Id
				PetArenaController.open(activeTab)
			end)
		end
	end

	local function trainersPage(): ()
		petPicker()
		local snapshot = ProgressController.get()
		local cleared = if snapshot then snapshot.PetArena.Cleared else 0
		local grid = PanelKit.grid(content, CARD_WIDTH, CARD_HEIGHT)
		for index, trainer in PetArenaConfig.Trainers do
			local locked = index > cleared + 1
			local card = PanelKit.itemCard(
				grid,
				trainer.Title .. " " .. trainer.Name,
				string.format(
					"%s %s %s\n💰 %d · ✨ %d XP (x%d first win today)",
					emojiOf(trainer.Species),
					trainer.Rarity,
					nameOf(trainer.Species),
					trainer.Coins,
					trainer.Xp,
					PetArenaConfig.FirstWinBonus
				),
				emojiOf(trainer.Species),
				ACCENT
			)
			if index <= cleared then
				PanelKit.setBadge(card, "✓ Beaten", C.Good)
			elseif index == #PetArenaConfig.Trainers then
				PanelKit.setBadge(card, "🎁 Supply", ACCENT)
			end
			card.Button.Text = if locked then "🔒 Beat the one before" else "⚔️ Battle!"
			PanelKit.setColor(card.Button, if locked then C.Neutral else C.Good)
			PanelKit.setDisabled(card.Button, locked)
			card.Button.Activated:Connect(function()
				local pet = pickedPet()
				if pet == nil or locked then
					return
				end
				window:close()
				remote("Start"):FireServer(index, pet.Id)
			end)
		end
	end

	local function challengePage(): ()
		petPicker()
		local list = PanelKit.section(content, "🤝 Players here", false, true)
		local others = 0
		for _, player in Players:GetPlayers() do
			if player ~= localPlayer then
				others += 1
				local row = PanelKit.row(list.Body)
				local label = PanelKit.text(row, player.DisplayName)
				label.Size = UDim2.new(1, -140, 1, 0)
				local challenge = PanelKit.button(row, "🐾 Challenge", ACCENT)
				challenge.Size = UDim2.fromOffset(130, PanelKit.ROW_HEIGHT)
				challenge.Activated:Connect(function()
					local pet = pickedPet()
					if pet == nil then
						return
					end
					remote("Challenge"):FireServer(player.UserId, pet.Id)
				end)
			end
		end
		if others == 0 then
			PanelKit.notice(list.Body, "Empty", "Nobody else is here right now. Try the Trainers!")
		end
	end

	local function rulesPage(): ()
		local rules = PanelKit.section(content, "📜 How battles work", false, true)
		for _, line in
			{
				"Each round both pets pick a move at the same time. The faster pet acts first.",
				"💥 Boop: takes Pep from the other pet. 🍀 Lucky boops do 1.5x.",
				string.format(
					"⚡ Charge: your next Boop does %dx.",
					PetArenaConfig.ChargeMultiplier
				),
				string.format(
					"🛡️ Guard: a boop on you this round only does %d%%.",
					PetArenaConfig.GuardTaken * 100
				),
				"A pet with no Pep left is dizzy and loses (nobody gets hurt!).",
				string.format(
					"After %d rounds the pet with more Pep left wins.",
					PetArenaConfig.MaxRounds
				),
				"Your pet's stats come from its rarity and buffs: Damage → 💥 power, XP → 💚 Pep, Crit Damage → 🍀 luck, flyers are quickest.",
				string.format(
					"Rewards: up to %d trainer wins a day (the first win against each trainer pays %dx); beating the Director the first time each day also gives an office supply. Player battles reward %d a day (twice per opponent).",
					PetArenaConfig.DailyRewardedWins,
					PetArenaConfig.FirstWinBonus,
					PetArenaConfig.DailyPlayerBattles
				),
			}
		do
			PanelKit.text(rules.Body, "• " .. line, "Muted")
		end
	end

	local function render(): ()
		window:selectTab(activeTab)
		if not window:isOpen() then
			return
		end
		window:clear()
		if activeTab == "Challenge" then
			challengePage()
		elseif activeTab == "Rules" then
			rulesPage()
		else
			trainersPage()
		end
	end
	window:setTabs({
		{ Id = "Trainers", Label = "🏆 Trainers" },
		{ Id = "Challenge", Label = "🤝 Challenge" },
		{ Id = "Rules", Label = "📜 How it works" },
	}, function(id: string)
		activeTab = id
		render()
	end)
	window:onOpen(function()
		task.defer(render)
	end)
	ProgressController.Changed:Connect(function()
		if window:isOpen() then
			render()
		end
	end)
	closeArenaWindow = function()
		window:close()
	end
	openWindow = function(tab: string?)
		if tab then
			activeTab = tab
		end
		window:open()
		render()
	end
end

-- Battle screen -----------------------------------------------------------------------

type Actor = {
	Rig: PetVisual.Rig,
	Home: CFrame, -- where it stands, facing the other pet
	Facing: number, -- +1 or -1 along X
	LungeAt: number,
	HitAt: number,
	Dizzy: boolean,
	Bubble: Part,
	Aura: Part,
}

local MOVE_HINT = {
	Boop = "Take Pep",
	Charge = "Next boop x" .. PetArenaConfig.ChargeMultiplier,
	Guard = string.format("Take only %d%%", math.floor(PetArenaConfig.GuardTaken * 100 + 0.5)),
}
local MOVE_COLOR = {
	Boop = C.Danger,
	Charge = UiTokens.Color.Gold,
	Guard = C.Primary,
}
local MOVE_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three }
local MOVE_ACTION = "PetBattleMove"

type Card = { Name: TextLabel, Bar: PanelKit.ProgressBar, Fill: Frame, Badge: TextLabel }

-- Green while healthy, gold when low, red when nearly dizzy.
local function pepColor(fraction: number): Color3
	return if fraction > 0.5
		then C.Good
		elseif fraction > 0.25 then UiTokens.Color.Gold
		else C.Danger
end

local function buildBattle(parent: Instance): ()
	local screen = PanelKit.gameScreen({
		Name = "PetBattle",
		Title = "🐾 Pet Battle",
		Accent = ACCENT,
	}, parent)
	local body = screen.Body
	local roundChip = screen.chip("Round 1")
	local timerChip = screen.chip("⏱ 15s", C.Field)
	timerChip.Visible = false

	-- The stage: takes the leftover height.
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Stage"
	viewport.LayoutOrder = 1
	viewport.Size = UDim2.new(1, 0, 0, 140)
	viewport.BackgroundColor3 = Color3.fromRGB(150, 205, 255)
	viewport.Ambient = Color3.fromRGB(200, 200, 210)
	viewport.LightColor = Color3.fromRGB(255, 250, 240)
	viewport.Parent = body
	PanelKit.fill(viewport)
	local vpCorner = Instance.new("UICorner")
	vpCorner.CornerRadius = UDim.new(0, UiTokens.Radius.Card)
	vpCorner.Parent = viewport
	local sky = Instance.new("UIGradient")
	sky.Rotation = 90
	sky.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 225, 255))
	sky.Parent = viewport
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 4.5, 15), Vector3.new(0, 1.2, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local floor = Instance.new("Part")
	floor.Anchored = true
	floor.Size = Vector3.new(16, 0.4, 7)
	floor.Position = Vector3.new(0, -0.2, 0)
	floor.Color = Color3.fromRGB(120, 200, 120)
	floor.Material = Enum.Material.SmoothPlastic
	floor.Parent = world
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.05, 6, 6)
	ring.CFrame = CFrame.new(0, 0.02, 0) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = Color3.fromRGB(255, 255, 255)
	ring.Transparency = 0.5
	ring.Parent = world

	-- Fighter cards: name, a Pep bar coloured by how much is left, a ⚡ badge.
	local fighters = Instance.new("Frame")
	fighters.Name = "Fighters"
	fighters.LayoutOrder = 2
	fighters.BackgroundTransparency = 1
	fighters.Size = UDim2.new(1, 0, 0, 74)
	fighters.Parent = body
	local function fighterCard(side: number): Card
		local card = Instance.new("Frame")
		card.AnchorPoint = Vector2.new(side, 0)
		card.Position = UDim2.fromScale(side, 0)
		card.Size = UDim2.new(0.5, -6, 1, 0)
		card.BackgroundColor3 = C.Card
		card.Parent = fighters
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0, UiTokens.Radius.Card)
		round.Parent = card
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 12)
		pad.PaddingRight = UDim.new(0, 12)
		pad.PaddingTop = UDim.new(0, 10)
		pad.PaddingBottom = UDim.new(0, 10)
		pad.Parent = card
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 6)
		layout.Parent = card
		local name = Instance.new("TextLabel")
		name.LayoutOrder = 1
		name.BackgroundTransparency = 1
		name.Size = UDim2.new(1, 0, 0, 22)
		name.Font = PanelKit.FONT_BOLD
		name.TextColor3 = C.Text
		name.TextXAlignment = if side == 0
			then Enum.TextXAlignment.Left
			else Enum.TextXAlignment.Right
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Parent = card
		PanelKit.setTextSize(name, 17)
		local bar = PanelKit.progressBar(card, C.Good)
		bar.Frame.LayoutOrder = 2
		local badge = Instance.new("TextLabel")
		badge.Name = "Charged"
		badge.AnchorPoint = Vector2.new(1 - side, 0)
		badge.Position = UDim2.fromScale(1 - side, 0)
		badge.Size = UDim2.fromOffset(92, 22)
		badge.BackgroundColor3 = UiTokens.Color.Gold
		badge.Font = PanelKit.FONT_BOLD
		badge.TextSize = 13
		badge.TextColor3 = C.Ink
		badge.Text = "⚡ CHARGED"
		badge.Visible = false
		badge.ZIndex = 2
		badge.Parent = name
		local badgeCorner = Instance.new("UICorner")
		badgeCorner.CornerRadius = UDim.new(0, 11)
		badgeCorner.Parent = badge
		return {
			Name = name,
			Bar = bar,
			Fill = bar.Frame:FindFirstChild("Fill") :: Frame,
			Badge = badge,
		}
	end
	local cardA = fighterCard(0)
	local cardB = fighterCard(1)

	-- What just happened, one line per move.
	local log = Instance.new("TextLabel")
	log.Name = "Log"
	log.LayoutOrder = 3
	log.Size = UDim2.new(1, 0, 0, 50)
	log.BackgroundColor3 = C.Card
	log.BackgroundTransparency = 0.4
	log.Font = PanelKit.FONT_BOLD
	log.TextColor3 = C.Text
	log.TextWrapped = true
	log.Parent = body
	Responsive.capText(log, 17)
	local logCorner = Instance.new("UICorner")
	logCorner.CornerRadius = UDim.new(0, UiTokens.Radius.Tile)
	logCorner.Parent = log
	local logPad = Instance.new("UIPadding")
	logPad.PaddingLeft = UDim.new(0, 10)
	logPad.PaddingRight = UDim.new(0, 10)
	logPad.Parent = log

	-- Moves (with a one-line hint each), and in the same place the forfeit
	-- confirmation.
	local actions = Instance.new("Frame")
	actions.Name = "Actions"
	actions.LayoutOrder = 4
	actions.BackgroundTransparency = 1
	actions.Size = UDim2.new(1, 0, 0, 68)
	actions.Parent = body
	local moves = Instance.new("Frame")
	moves.Name = "Moves"
	moves.BackgroundTransparency = 1
	moves.Size = UDim2.fromScale(1, 1)
	moves.Parent = actions
	local movesLayout = Instance.new("UIListLayout")
	movesLayout.FillDirection = Enum.FillDirection.Horizontal
	movesLayout.SortOrder = Enum.SortOrder.LayoutOrder
	movesLayout.Padding = UDim.new(0, 8)
	movesLayout.Parent = moves

	local moveButtons: { [string]: TextButton } = {}
	local picked: string? = nil
	local pickMove: (move: string) -> () = function() end
	local keyboard = UserInputService.KeyboardEnabled
	for index, move in PetArenaConfig.Moves do
		local button = PanelKit.button(
			moves,
			PetArenaConfig.MoveText[move] or move,
			MOVE_COLOR[move] or C.Neutral
		)
		button.Name = move
		button.LayoutOrder = index
		button.Size = UDim2.new(1 / #PetArenaConfig.Moves, -8, 1, 0)
		button.TextYAlignment = Enum.TextYAlignment.Top
		PanelKit.setTextSize(button, 20)
		local inset = Instance.new("UIPadding")
		inset.PaddingTop = UDim.new(0, 10)
		inset.PaddingBottom = UDim.new(0, 26)
		inset.Parent = button
		local hint = Instance.new("TextLabel")
		hint.Name = "Hint"
		hint.AnchorPoint = Vector2.new(0.5, 0)
		hint.Position = UDim2.new(0.5, 0, 1, 2)
		hint.Size = UDim2.new(1, -8, 0, 18)
		hint.BackgroundTransparency = 1
		hint.Font = PanelKit.FONT
		hint.TextColor3 = UiTokens.textOn(MOVE_COLOR[move] or C.Neutral)
		hint.TextTransparency = 0.2
		hint.Text = (MOVE_HINT[move] or "")
			.. (if keyboard then string.format("  [%d]", index) else "")
		hint.Parent = button
		Responsive.capText(hint, 14)
		button.Activated:Connect(function()
			pickMove(move)
		end)
		moveButtons[move] = button
	end

	local confirmRow = Instance.new("Frame")
	confirmRow.Name = "ConfirmForfeit"
	confirmRow.BackgroundTransparency = 1
	confirmRow.Size = UDim2.fromScale(1, 1)
	confirmRow.Visible = false
	confirmRow.Parent = actions
	local confirmLayout = Instance.new("UIListLayout")
	confirmLayout.FillDirection = Enum.FillDirection.Horizontal
	confirmLayout.Padding = UDim.new(0, 8)
	confirmLayout.Parent = confirmRow
	local keepButton = PanelKit.button(confirmRow, "▶ Keep battling", C.Good)
	keepButton.Size = UDim2.new(0.5, -4, 1, 0)
	local forfeitButton =
		PanelKit.button(confirmRow, "🏳️ Give up (counts as a loss)", C.Danger)
	forfeitButton.Size = UDim2.new(0.5, -4, 1, 0)

	local function showConfirm(visible: boolean): ()
		confirmRow.Visible = visible
		moves.Visible = not visible
	end
	screen.Close.Activated:Connect(function()
		showConfirm(not confirmRow.Visible)
	end)
	keepButton.Activated:Connect(function()
		showConfirm(false)
	end)
	forfeitButton.Activated:Connect(function()
		showConfirm(false)
		remote("Forfeit"):FireServer()
	end)

	local actors: { [string]: Actor } = {}
	local current: BattleView? = nil
	local stepConnection: RBXScriptConnection? = nil
	local turnDeadline = 0

	-- While waiting for the other side, the picked move stays lit and the
	-- others grey out.
	local function setWaiting(waiting: boolean): ()
		for move, button in moveButtons do
			if waiting and move == picked then
				button.Active = false
				button.Text = "✓ " .. (PetArenaConfig.MoveText[move] or move)
			else
				button.Text = PetArenaConfig.MoveText[move] or move
				PanelKit.setDisabled(button, waiting)
			end
		end
	end

	pickMove = function(move: string)
		local button: TextButton? = moveButtons[move]
		if current == nil or button == nil or not button.Active or confirmRow.Visible then
			return
		end
		picked = move
		remote("Move"):FireServer(move)
		setWaiting(true)
		log.Text = "⏳ Your pet is ready..."
	end

	local function onKey(
		_name: string,
		state: Enum.UserInputState,
		input: InputObject
	): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			for index, key in MOVE_KEYS do
				local move = PetArenaConfig.Moves[index]
				if input.KeyCode == key and move then
					pickMove(move)
				end
			end
		end
		return Enum.ContextActionResult.Sink
	end

	local function clearStage(): ()
		for _, actor in actors do
			actor.Rig.Model:Destroy()
			actor.Bubble:Destroy()
			actor.Aura:Destroy()
		end
		table.clear(actors)
	end

	local function spawnActor(side: string, fighter: FighterView): ()
		local rig = PetVisual.build(fighter.Species, { Glitter = false })
		rig.Model.Parent = world
		local facing = if side == "A" then 1 else -1
		local x = -3.4 * facing
		local home = CFrame.lookAt(Vector3.new(x, 0, 0), Vector3.new(x + facing, 0, 0))
		if rig.Flies then
			home = home + Vector3.new(0, 1.6, 0)
		end
		local bubble = Instance.new("Part")
		bubble.Anchored = true
		bubble.Shape = Enum.PartType.Ball
		bubble.Size = Vector3.one * (2.8 * rig.Scale)
		bubble.Color = Color3.fromRGB(120, 190, 255)
		bubble.Material = Enum.Material.ForceField
		bubble.Transparency = 1
		bubble.Parent = world
		local aura = Instance.new("Part")
		aura.Anchored = true
		aura.Shape = Enum.PartType.Ball
		aura.Size = Vector3.one * 0.6
		aura.Color = Color3.fromRGB(255, 220, 90)
		aura.Material = Enum.Material.Neon
		aura.Transparency = 1
		aura.Parent = world
		actors[side] = {
			Rig = rig,
			Home = home,
			Facing = facing,
			LungeAt = -100,
			HitAt = -100,
			Dizzy = false,
			Bubble = bubble,
			Aura = aura,
		}
	end

	local function step(): ()
		local now = os.clock()
		local view = current
		for side, actor in actors do
			local offset = Vector3.zero
			local lunge = (now - actor.LungeAt) / LUNGE_SECONDS
			if lunge >= 0 and lunge <= 1 then
				offset += Vector3.new(
					math.sin(lunge * math.pi) * 2.2 * actor.Facing,
					math.sin(lunge * math.pi) * 0.5,
					0
				)
			end
			local hit = (now - actor.HitAt) / LUNGE_SECONDS
			local wobble = 0
			if hit >= 0 and hit <= 1 then
				offset += Vector3.new(-math.sin(hit * math.pi) * 0.6 * actor.Facing, 0, 0)
				wobble = math.sin(hit * math.pi * 4) * 0.3
			end
			local spin = if actor.Dizzy then now * 4 else 0
			local pivot = actor.Home * CFrame.new(0, 0, 0) + offset
			pivot = pivot * CFrame.Angles(0, spin, wobble)
			local pose = PetVisual.restPose(now)
			if lunge >= 0 and lunge <= 1 then
				pose.Stride = 1.5
				pose.Phase = now * 12
			end
			local parts, frames = PetVisual.pose(actor.Rig, pivot, pose)
			for index, part in parts do
				part.CFrame = frames[index]
			end
			local fighter = if view then (if side == "A" then view.A else view.B) else nil
			actor.Aura.Transparency = if fighter and fighter.Charged
				then 0.2 + math.sin(now * 8) * 0.15
				else 1
			actor.Aura.CFrame =
				CFrame.new(pivot.Position + Vector3.new(0, 2.6 * actor.Rig.Scale, 0))
			actor.Bubble.CFrame =
				CFrame.new(pivot.Position + Vector3.new(0, 1 * actor.Rig.Scale, 0))
		end
		-- Player battles: seconds left to pick a move.
		if timerChip.Visible then
			local left = math.max(0, math.ceil(turnDeadline - now))
			timerChip.Text = string.format("⏱ %ds", left)
			timerChip.BackgroundColor3 = if left <= 5 then C.Danger else C.Field
		end
	end

	local function describe(event: EventView, view: BattleView): string
		local who = if event.Side == view.You then "Your pet" else "The other pet"
		if event.Move == "Boop" then
			return string.format(
				"💥 %s boops for %d%s%s",
				who,
				event.Damage,
				if event.Lucky then " 🍀 lucky!" else "",
				if event.Guarded then " (guarded)" else ""
			)
		elseif event.Move == "Charge" then
			return "⚡ " .. who .. " charges up"
		end
		return "🛡️ " .. who .. " guards"
	end

	local function refresh(view: BattleView): ()
		cardA.Name.Text = string.format(
			"%s %s · %s",
			emojiOf(view.A.Species),
			nameOf(view.A.Species),
			view.A.Name
		)
		cardB.Name.Text = string.format(
			"%s · %s %s",
			view.B.Name,
			nameOf(view.B.Species),
			emojiOf(view.B.Species)
		)
		local function show(card: Card, fighter: FighterView): ()
			local fraction = fighter.Pep / fighter.MaxPep
			card.Bar.set(fraction, string.format("%d / %d Pep", fighter.Pep, fighter.MaxPep))
			card.Fill.BackgroundColor3 = pepColor(fraction)
			card.Badge.Visible = fighter.Charged
		end
		show(cardA, view.A)
		show(cardB, view.B)
		roundChip.Text = string.format("Round %d / %d", view.Round + 1, PetArenaConfig.MaxRounds)
		if view.TurnLeft > 0 then
			turnDeadline = os.clock() + view.TurnLeft
		end
		timerChip.Visible = view.Vs ~= "Cpu" and view.TurnLeft > 0
		if not view.Waiting then
			picked = nil
		end
		setWaiting(view.Waiting)
	end

	showBattle = function(view: BattleView)
		local same = current ~= nil and (current :: BattleView).BattleId == view.BattleId
		if view.Kind == "Battle" or not same then
			closeArenaWindow()
			clearStage()
			spawnActor("A", view.A)
			spawnActor("B", view.B)
			showConfirm(false)
			log.Text = string.format(
				"Pick a move! (%s)",
				if view.Vs == "Cpu" then "vs trainer" else "vs player"
			)
		end
		current = view
		screen.setOpen(true)
		if stepConnection == nil then
			stepConnection = RunService.RenderStepped:Connect(step)
			ContextActionService:BindActionAtPriority(
				MOVE_ACTION,
				onKey,
				false,
				Enum.ContextActionPriority.High.Value,
				table.unpack(MOVE_KEYS)
			)
		end
		if view.Kind == "Round" then
			-- Play the round's events one after another.
			local lines: { string } = {}
			for index, event in view.Events do
				table.insert(lines, describe(event, view))
				task.delay((index - 1) * LUNGE_SECONDS, function()
					local actor = actors[event.Side]
					local target = actors[if event.Side == "A" then "B" else "A"]
					if event.Move == "Boop" and actor and target then
						actor.LungeAt = os.clock()
						task.delay(LUNGE_SECONDS * 0.5, function()
							target.HitAt = os.clock()
						end)
					elseif event.Move == "Guard" and actor then
						actor.Bubble.Transparency = 0.55
						task.delay(LUNGE_SECONDS * 1.6, function()
							actor.Bubble.Transparency = 1
						end)
					end
				end)
			end
			for side, actor in actors do
				local fighter = if side == "A" then view.A else view.B
				actor.Dizzy = fighter.Pep <= 0
			end
			log.Text = table.concat(lines, "   ·   ")
		elseif view.Kind == "Waiting" then
			log.Text = if view.Waiting
				then "⏳ Waiting for the other trainer..."
				else "Pick a move!"
		end
		refresh(view)
	end

	endBattle = function()
		screen.setOpen(false)
		current = nil
		picked = nil
		if stepConnection then
			stepConnection:Disconnect()
			stepConnection = nil
			ContextActionService:UnbindAction(MOVE_ACTION)
		end
		clearStage()
	end
end

function PetArenaController.start(): ()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	buildWindow(playerGui)
	buildBattle(playerGui)
	remote("State").OnClientEvent:Connect(onState)
	remote("Result").OnClientEvent:Connect(onResult)
	-- The Arena sign at the Recreation Center (Lib/CourtBuilder).
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name == "PetArenaPrompt" then
			PetArenaController.open(nil)
		end
	end)
end

return PetArenaController
