--!strict
--[[
	Paper Toss Showdown on the client (docs/PAPER_TOSS.md).

	  * Window (the booth at the Recreation Center, or 🏢 Social): pick a CPU
	    coworker (Intern Izzy, Manager Max, CEO Cora; beat each to unlock the
	    next), your best score and the rules.
	  * Game screen (PanelKit.gameScreen, the world dims): a scoreboard (you
	    vs the coworker), a little office in a ViewportFrame with the bin at
	    this round's distance plus breeze and distance chips, then the AIM
	    and POWER meters with their target zones (gold = swish, green = in).
	    Press STOP (or Space / R2 / X) to stop the aim marker, again to stop
	    the power; each stopped marker turns gold, green or red. Your paper
	    ball arcs to where it lands, a big banner shows the result, then the
	    coworker throws. The X asks before quitting.
	The server judges every throw and pays the rewards (PaperTossService).
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local PaperTossConfig =
	require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("PaperTossConfig"))
local PaperTossRules =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PaperTossRules"))

local AnnouncementController = require(script.Parent.AnnouncementController)
local PanelKit = require(script.Parent.Parent.Lib.PanelKit)
local ProgressController = require(script.Parent.ProgressController)
local Responsive = require(script.Parent.Parent.Lib.Responsive)
local UiTokens = require(script.Parent.Parent.Lib.UiTokens)

local PaperTossController = {}

local C = PanelKit.Colors
local ACCENT = Color3.fromRGB(110, 190, 255)
local FLIGHT_SECONDS = 0.9
local RESULT_TEXT = {
	Swish = "🎯 SWISH! +3",
	In = "✅ In! +2",
	Rim = "😬 Off the rim!",
	Miss = "❌ Missed",
}
local RESULT_COLOR = {
	Swish = UiTokens.Color.Gold,
	In = C.Good,
	Rim = C.Text,
	Miss = C.Text,
}
local THROW_ACTION = "PaperTossThrow"
-- The thrower stands here; bins stand down the room (-Z) by distance.
local THROW_FROM = Vector3.new(0, 2.2, 6)
local BIN_Z = { -2, -6, -10 }

type RoundView = { Number: number, Distance: number, Wind: number }
type ThrowView = { Aim: number, Power: number, Result: string, Points: number }

local localPlayer = Players.LocalPlayer
local openWindow: (() -> ())? = nil

local function remote(name: string): RemoteEvent
	local found =
		ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PaperToss"):WaitForChild(name)
	assert(found:IsA("RemoteEvent"), "PaperToss." .. name .. " must be a RemoteEvent")
	return found
end

local function number(value: unknown): number
	return if typeof(value) == "number" and value == value then value else 0
end

local function text(value: unknown): string
	return if typeof(value) == "string" then value else ""
end

local function parseRound(raw: unknown): RoundView?
	if typeof(raw) ~= "table" then
		return nil
	end
	local data = raw :: { [string]: unknown }
	return {
		Number = number(data.Number),
		Distance = math.clamp(number(data.Distance), 1, 3),
		Wind = number(data.Wind),
	}
end

local function parseThrow(raw: unknown): ThrowView?
	if typeof(raw) ~= "table" then
		return nil
	end
	local data = raw :: { [string]: unknown }
	return {
		Aim = number(data.Aim),
		Power = number(data.Power),
		Result = text(data.Result),
		Points = number(data.Points),
	}
end

local function windText(wind: number): string
	if math.abs(wind) < 0.05 then
		return "💨 No breeze"
	end
	return string.format(
		"💨 Breeze %s %d%%",
		if wind > 0 then "→" else "←",
		math.floor(math.abs(wind) * 100 + 0.5)
	)
end

function PaperTossController.open(): ()
	local opener = openWindow
	if opener then
		opener()
	end
end

-- Game screen ------------------------------------------------------------------------

local startGame: (opponent: number, rounds: number, round: RoundView?) -> () = function() end
local playRound: (payload: { [string]: unknown }) -> () = function() end
local closeGame: () -> () = function() end

type Meter = {
	Row: Frame,
	Label: TextLabel,
	Track: Frame,
	Outline: UIStroke,
	InZone: Frame,
	SwishZone: Frame,
	Marker: Frame,
}

local DISTANCE_TEXT = { "📏 Near bin", "📏 Middle bin", "📏 Far bin" }
local MARKER_IDLE = Color3.fromRGB(250, 250, 255)

local function buildGame(parent: Instance): ()
	local screen = PanelKit.gameScreen({
		Name = "PaperTossGame",
		Title = "🗑️ Paper Toss",
		Accent = ACCENT,
	}, parent)
	local body = screen.Body
	local roundChip = screen.chip("Round 1 / 5")

	-- Scoreboard: you on the left, the coworker on the right.
	local scoreRow = Instance.new("Frame")
	scoreRow.Name = "Scoreboard"
	scoreRow.LayoutOrder = 1
	scoreRow.BackgroundTransparency = 1
	scoreRow.Size = UDim2.new(1, 0, 0, 56)
	scoreRow.Parent = body
	local function scoreCard(side: number, accent: Color3): (TextLabel, TextLabel)
		local card = Instance.new("Frame")
		card.AnchorPoint = Vector2.new(side, 0)
		card.Position = UDim2.fromScale(side, 0)
		card.Size = UDim2.new(0.5, -30, 1, 0)
		card.BackgroundColor3 = C.Card
		card.Parent = scoreRow
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0, UiTokens.Radius.Card)
		round.Parent = card
		local outline = Instance.new("UIStroke")
		outline.Color = accent
		outline.Transparency = 0.5
		outline.Thickness = 1.5
		outline.Parent = card
		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Position = UDim2.fromOffset(if side == 0 then 14 else 76, 0)
		name.Size = UDim2.new(1, -90, 1, 0)
		name.Font = PanelKit.FONT_BOLD
		name.TextColor3 = C.Text
		name.TextXAlignment = if side == 0
			then Enum.TextXAlignment.Left
			else Enum.TextXAlignment.Right
		name.Parent = card
		Responsive.capText(name, 18)
		local score = Instance.new("TextLabel")
		score.BackgroundTransparency = 1
		score.AnchorPoint = Vector2.new(1 - side, 0)
		score.Position = UDim2.new(1 - side, if side == 0 then -10 else 10, 0, 0)
		score.Size = UDim2.new(0, 60, 1, 0)
		score.Font = UiTokens.Font.Title
		score.TextSize = 34
		score.TextColor3 = accent
		score.Text = "0"
		score.Parent = card
		return name, score
	end
	local youName, youScore = scoreCard(0, ACCENT)
	local cpuName, cpuScore = scoreCard(1, C.Heading)
	youName.Text = "🙂 You"
	local versus = Instance.new("TextLabel")
	versus.BackgroundTransparency = 1
	versus.AnchorPoint = Vector2.new(0.5, 0)
	versus.Position = UDim2.fromScale(0.5, 0)
	versus.Size = UDim2.new(0, 56, 1, 0)
	versus.Font = UiTokens.Font.Title
	versus.TextSize = 20
	versus.TextColor3 = C.Muted
	versus.Text = "VS"
	versus.Parent = scoreRow

	-- The office: takes the leftover height.
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Stage"
	viewport.LayoutOrder = 2
	viewport.Size = UDim2.new(1, 0, 0, 140)
	viewport.BackgroundColor3 = Color3.fromRGB(205, 220, 240)
	viewport.Ambient = Color3.fromRGB(200, 200, 210)
	viewport.LightColor = Color3.fromRGB(255, 250, 240)
	viewport.Parent = body
	PanelKit.fill(viewport)
	local vpCorner = Instance.new("UICorner")
	vpCorner.CornerRadius = UDim.new(0, UiTokens.Radius.Card)
	vpCorner.Parent = viewport
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 50
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 5, 11), Vector3.new(0, 0.5, -4))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local function block(
		size: Vector3,
		position: Vector3,
		color: Color3,
		shape: Enum.PartType?
	): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.Size = size
		p.Position = position
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		if shape then
			p.Shape = shape
		end
		p.Parent = world
		return p
	end
	block(Vector3.new(14, 0.4, 24), Vector3.new(0, -0.2, -2), Color3.fromRGB(150, 160, 185))
	block(Vector3.new(14, 8, 0.4), Vector3.new(0, 4, -14), Color3.fromRGB(235, 225, 210))
	local bin = block(
		Vector3.new(1.6, 1.8, 1.8),
		Vector3.new(0, 0.8, -6),
		Color3.fromRGB(70, 75, 90),
		Enum.PartType.Cylinder
	)
	bin.Orientation = Vector3.new(0, 0, 90)
	local binRim = block(
		Vector3.new(0.12, 2.05, 2.05),
		Vector3.new(0, 1.7, -6),
		Color3.fromRGB(200, 205, 215),
		Enum.PartType.Cylinder
	)
	binRim.Orientation = Vector3.new(0, 0, 90)
	local paper = block(
		Vector3.new(0.5, 0.5, 0.5),
		THROW_FROM,
		Color3.fromRGB(250, 250, 245),
		Enum.PartType.Ball
	)
	paper.Transparency = 1

	-- Chips over the stage: the breeze (top left) and the distance (top right).
	local function stageChip(side: number): TextLabel
		local chip = Instance.new("TextLabel")
		chip.AnchorPoint = Vector2.new(side, 0)
		chip.Position = UDim2.new(side, if side == 0 then 10 else -10, 0, 10)
		chip.AutomaticSize = Enum.AutomaticSize.X
		chip.Size = UDim2.fromOffset(0, 32)
		chip.BackgroundColor3 = C.Window
		chip.BackgroundTransparency = 0.15
		chip.Font = PanelKit.FONT_BOLD
		chip.TextSize = 16
		chip.TextColor3 = C.Text
		chip.ZIndex = 3
		chip.Parent = viewport
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0, 16)
		round.Parent = chip
		local inset = Instance.new("UIPadding")
		inset.PaddingLeft = UDim.new(0, 12)
		inset.PaddingRight = UDim.new(0, 12)
		inset.Parent = chip
		return chip
	end
	local windChip = stageChip(0)
	local distanceChip = stageChip(1)

	-- A big result banner in the middle of the stage ("SWISH! +3").
	local banner = Instance.new("TextLabel")
	banner.Name = "Result"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.42)
	banner.Size = UDim2.new(0.9, 0, 0, 56)
	banner.BackgroundTransparency = 1
	banner.Font = UiTokens.Font.Title
	banner.TextSize = 40
	banner.TextColor3 = C.Text
	banner.TextStrokeColor3 = C.Ink
	banner.TextStrokeTransparency = 0.2
	banner.Text = ""
	banner.ZIndex = 4
	banner.Parent = viewport

	-- Meters: AIM and POWER, each with its target zones.
	local meterCard = Instance.new("Frame")
	meterCard.Name = "Meters"
	meterCard.LayoutOrder = 3
	meterCard.Size = UDim2.new(1, 0, 0, 108)
	meterCard.BackgroundColor3 = C.Card
	meterCard.Parent = body
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, UiTokens.Radius.Card)
	cardCorner.Parent = meterCard
	local cardPad = Instance.new("UIPadding")
	cardPad.PaddingLeft = UDim.new(0, 14)
	cardPad.PaddingRight = UDim.new(0, 14)
	cardPad.PaddingTop = UDim.new(0, 12)
	cardPad.PaddingBottom = UDim.new(0, 12)
	cardPad.Parent = meterCard
	local cardList = Instance.new("UIListLayout")
	cardList.SortOrder = Enum.SortOrder.LayoutOrder
	cardList.Padding = UDim.new(0, 8)
	cardList.Parent = meterCard

	local function meter(caption: string, order: number): Meter
		local row = Instance.new("Frame")
		row.LayoutOrder = order
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 38)
		row.Parent = meterCard
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(0, 104, 1, 0)
		label.Font = PanelKit.FONT_BOLD
		label.TextSize = 16
		label.TextColor3 = C.Muted
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = caption
		label.Parent = row
		local track = Instance.new("Frame")
		track.AnchorPoint = Vector2.new(0, 0.5)
		track.Position = UDim2.new(0, 108, 0.5, 0)
		track.Size = UDim2.new(1, -108, 0, 22)
		track.BackgroundColor3 = C.Field
		track.Parent = row
		local trackCorner = Instance.new("UICorner")
		trackCorner.CornerRadius = UDim.new(0, 11)
		trackCorner.Parent = track
		local outline = Instance.new("UIStroke")
		outline.Color = ACCENT
		outline.Thickness = 2
		outline.Transparency = 1
		outline.Parent = track
		local function zone(width: number, color: Color3, transparency: number): Frame
			local z = Instance.new("Frame")
			z.AnchorPoint = Vector2.new(0.5, 0)
			z.Size = UDim2.fromScale(width, 1)
			z.BackgroundColor3 = color
			z.BackgroundTransparency = transparency
			z.BorderSizePixel = 0
			z.Parent = track
			local zc = Instance.new("UICorner")
			zc.CornerRadius = UDim.new(0, 8)
			zc.Parent = z
			return z
		end
		local inZone = zone(PaperTossConfig.InWithin * 2, C.Good, 0.35)
		local swishZone = zone(PaperTossConfig.SwishWithin * 2, UiTokens.Color.Gold, 0.05)
		local marker = Instance.new("Frame")
		marker.AnchorPoint = Vector2.new(0.5, 0.5)
		marker.Position = UDim2.fromScale(0.5, 0.5)
		marker.Size = UDim2.new(0, 6, 1, 16)
		marker.BackgroundColor3 = MARKER_IDLE
		marker.ZIndex = 3
		marker.Parent = track
		local markerCorner = Instance.new("UICorner")
		markerCorner.CornerRadius = UDim.new(0, 3)
		markerCorner.Parent = marker
		local markerStroke = Instance.new("UIStroke")
		markerStroke.Color = C.Ink
		markerStroke.Thickness = 1.5
		markerStroke.Parent = marker
		return {
			Row = row,
			Label = label,
			Track = track,
			Outline = outline,
			InZone = inZone,
			SwishZone = swishZone,
			Marker = marker,
		}
	end
	local aimMeter = meter("① AIM", 1)
	local powerMeter = meter("② POWER", 2)

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.LayoutOrder = 4
	hint.BackgroundTransparency = 1
	hint.Size = UDim2.new(1, 0, 0, 22)
	hint.Font = PanelKit.FONT
	hint.TextColor3 = C.Muted
	hint.Parent = body
	Responsive.capText(hint, 16)

	-- The big action button, and (in the same place) the quit confirmation.
	local actions = Instance.new("Frame")
	actions.Name = "Actions"
	actions.LayoutOrder = 5
	actions.BackgroundTransparency = 1
	actions.Size = UDim2.new(1, 0, 0, 58)
	actions.Parent = body
	local throwButton = PanelKit.button(actions, "", C.Good)
	throwButton.Name = "Throw"
	throwButton.Size = UDim2.fromScale(1, 1)
	PanelKit.setTextSize(throwButton, 22)

	local confirmRow = Instance.new("Frame")
	confirmRow.Name = "ConfirmQuit"
	confirmRow.BackgroundTransparency = 1
	confirmRow.Size = UDim2.fromScale(1, 1)
	confirmRow.Visible = false
	confirmRow.Parent = actions
	local confirmLayout = Instance.new("UIListLayout")
	confirmLayout.FillDirection = Enum.FillDirection.Horizontal
	confirmLayout.Padding = UDim.new(0, 8)
	confirmLayout.Parent = confirmRow
	local keepButton = PanelKit.button(confirmRow, "▶ Keep playing", C.Good)
	keepButton.Size = UDim2.new(0.5, -4, 1, 0)
	local quitButton = PanelKit.button(confirmRow, "🚪 Quit (no reward)", C.Danger)
	quitButton.Size = UDim2.new(0.5, -4, 1, 0)

	-- State.
	local phase = "Idle" -- "Aim" | "Power" | "Flying" | "Idle"
	local sweepStart = os.clock()
	local aim, power = 0.5, 0.5
	local idealAim, idealPower = 0.5, 0.5
	local current: RoundView? = nil
	local opponentIndex = 1
	local rounds = PaperTossConfig.Rounds
	local you, cpu = 0, 0
	local stepConnection: RBXScriptConnection? = nil
	local bannerToken = 0

	local function sweep(seconds: number): number
		local t = ((os.clock() - sweepStart) / seconds) % 2
		return if t <= 1 then t else 2 - t
	end

	-- Gold inside the swish zone, green inside the "in" zone, red outside.
	local function zoneColor(value: number, ideal: number): Color3
		local off = math.abs(value - ideal)
		return if off <= PaperTossConfig.SwishWithin
			then UiTokens.Color.Gold
			elseif off <= PaperTossConfig.InWithin then C.Good
			else C.Danger
	end

	local function setActive(active: Meter?): ()
		for _, m in { aimMeter, powerMeter } do
			local on = m == active
			m.Label.TextColor3 = if on then C.Text else C.Muted
			m.Outline.Transparency = if on then 0.1 else 1
		end
	end

	-- Keyboard players see the shortcut on the button.
	local function setCaption(caption: string, withKey: boolean): ()
		throwButton.Text = if withKey and UserInputService.KeyboardEnabled
			then caption .. "   [Space]"
			else caption
	end

	local function showBanner(message: string, color: Color3): ()
		bannerToken += 1
		local mine = bannerToken
		banner.Text = message
		banner.TextColor3 = color
		PanelKit.pop(banner)
		task.delay(1.4, function()
			if bannerToken == mine then
				banner.Text = ""
			end
		end)
	end

	local function setRound(round: RoundView?): ()
		current = round
		if round then
			bin.Position = Vector3.new(0, 0.8, BIN_Z[round.Distance] or -6)
			binRim.Position = Vector3.new(0, 1.7, BIN_Z[round.Distance] or -6)
			windChip.Text = windText(round.Wind)
			distanceChip.Text = DISTANCE_TEXT[round.Distance] or DISTANCE_TEXT[2]
			idealAim, idealPower =
				PaperTossRules.ideal({ Distance = round.Distance, Wind = round.Wind })
			for _, zone in { aimMeter.InZone, aimMeter.SwishZone } do
				zone.Position = UDim2.fromScale(idealAim, 0)
			end
			for _, zone in { powerMeter.InZone, powerMeter.SwishZone } do
				zone.Position = UDim2.fromScale(idealPower, 0)
			end
		end
	end

	local function setScore(): ()
		local opponent = PaperTossConfig.Opponents[opponentIndex]
		cpuName.Text = string.format("%s %s %s", opponent.Title, opponent.Name, opponent.Icon)
		if youScore.Text ~= tostring(you) then
			youScore.Text = tostring(you)
			PanelKit.pop(youScore)
		end
		if cpuScore.Text ~= tostring(cpu) then
			cpuScore.Text = tostring(cpu)
			PanelKit.pop(cpuScore)
		end
		roundChip.Text = string.format(
			"Round %d / %d",
			math.min(if current then current.Number else rounds, rounds),
			rounds
		)
	end

	local function beginAim(): ()
		phase = "Aim"
		sweepStart = os.clock()
		aimMeter.Marker.BackgroundColor3 = MARKER_IDLE
		powerMeter.Marker.BackgroundColor3 = MARKER_IDLE
		power = 0
		setActive(aimMeter)
		hint.Text = "Stop the marker in the gold zone for a SWISH (green = in)"
		setCaption("🎯 STOP AIM", true)
		PanelKit.setColor(throwButton, C.Good)
		PanelKit.setDisabled(throwButton, false)
	end

	-- One press stops the aim; the next stops the power and throws.
	local function press(): ()
		if phase == "Aim" then
			aimMeter.Marker.BackgroundColor3 = zoneColor(aim, idealAim)
			phase = "Power"
			sweepStart = os.clock()
			setActive(powerMeter)
			hint.Text = "Now the power: far bins need more"
			setCaption("💪 STOP POWER", true)
			PanelKit.setColor(throwButton, C.Primary)
		elseif phase == "Power" then
			powerMeter.Marker.BackgroundColor3 = zoneColor(power, idealPower)
			phase = "Flying"
			setActive(nil)
			setCaption("🧻 Throwing...", false)
			PanelKit.setDisabled(throwButton, true)
			hint.Text = ""
			remote("Throw"):FireServer(aim, power)
		end
	end

	-- Where a throw lands, from how far it was from the ideal one.
	local function landing(round: RoundView, throw: ThrowView): Vector3
		local bestAim, bestPower =
			PaperTossRules.ideal({ Distance = round.Distance, Wind = round.Wind })
		local binAt = Vector3.new(0, 1.6, BIN_Z[round.Distance] or -6)
		if throw.Result == "Swish" then
			return binAt + Vector3.new(0, -0.6, 0)
		elseif throw.Result == "In" then
			return binAt + Vector3.new((throw.Aim - bestAim) * 4, -0.4, 0)
		end
		local offset = Vector3.new((throw.Aim - bestAim) * 14, 0, -(throw.Power - bestPower) * 16)
		local spot = binAt + offset
		return Vector3.new(spot.X, 0.25, spot.Z)
	end

	local function fly(round: RoundView, throw: ThrowView, from: Vector3, done: () -> ()): ()
		local target = landing(round, throw)
		paper.Transparency = 0
		local started = os.clock()
		local flight: RBXScriptConnection? = nil
		flight = RunService.RenderStepped:Connect(function()
			local t = math.clamp((os.clock() - started) / FLIGHT_SECONDS, 0, 1)
			local position = from:Lerp(target, t)
				+ Vector3.new(
					round.Wind * math.sin(t * math.pi) * 0.8,
					math.sin(t * math.pi) * 3.5,
					0
				)
			paper.CFrame = CFrame.new(position) * CFrame.Angles(t * 8, t * 5, 0)
			if t >= 1 and flight then
				flight:Disconnect()
				done()
			end
		end)
	end

	local function step(): ()
		if phase == "Aim" then
			aim = sweep(PaperTossConfig.AimSweepSeconds)
		elseif phase == "Power" then
			power = sweep(PaperTossConfig.PowerSweepSeconds)
		end
		aimMeter.Marker.Position = UDim2.fromScale(aim, 0.5)
		powerMeter.Marker.Position = UDim2.fromScale(power, 0.5)
	end

	local function showConfirm(visible: boolean): ()
		confirmRow.Visible = visible
		throwButton.Visible = not visible
	end

	throwButton.Activated:Connect(press)
	screen.Close.Activated:Connect(function()
		showConfirm(not confirmRow.Visible)
	end)
	keepButton.Activated:Connect(function()
		showConfirm(false)
	end)
	quitButton.Activated:Connect(function()
		remote("Quit"):FireServer()
		closeGame()
	end)

	-- Space (keyboard) or R2 / X (gamepad) works like the big button while
	-- the game is open; Space doesn't jump meanwhile.
	local function onKey(
		_name: string,
		state: Enum.UserInputState,
		_input: InputObject
	): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin and not confirmRow.Visible then
			press()
		end
		return Enum.ContextActionResult.Sink
	end

	startGame = function(opponent: number, total: number, round: RoundView?)
		opponentIndex = math.clamp(opponent, 1, #PaperTossConfig.Opponents)
		rounds = total
		you, cpu = 0, 0
		aim, power = 0.5, 0
		paper.Transparency = 1
		banner.Text = ""
		showConfirm(false)
		screen.setOpen(true)
		setRound(round)
		setScore()
		beginAim()
		if stepConnection == nil then
			stepConnection = RunService.RenderStepped:Connect(step)
		end
		ContextActionService:BindActionAtPriority(
			THROW_ACTION,
			onKey,
			false,
			Enum.ContextActionPriority.High.Value,
			Enum.KeyCode.Space,
			Enum.KeyCode.ButtonR2,
			Enum.KeyCode.ButtonX
		)
	end

	playRound = function(payload: { [string]: unknown })
		local played = parseRound(payload.Played)
		local mine = parseThrow(payload.YouThrow)
		local theirs = parseThrow(payload.CpuThrow)
		if played == nil or mine == nil or theirs == nil then
			return
		end
		local playedRound: RoundView = {
			Number = if current then current.Number else 1,
			Distance = played.Distance,
			Wind = played.Wind,
		}
		local opponent = PaperTossConfig.Opponents[opponentIndex]
		fly(playedRound, mine, THROW_FROM, function()
			showBanner(RESULT_TEXT[mine.Result] or mine.Result, RESULT_COLOR[mine.Result] or C.Text)
			you = number(payload.You) - theirs.Points
			setScore()
			hint.Text = string.format("%s %s is throwing...", opponent.Icon, opponent.Title)
			task.delay(0.9, function()
				fly(playedRound, theirs, THROW_FROM + Vector3.new(2.5, 0, 0), function()
					showBanner(
						opponent.Icon .. " " .. (RESULT_TEXT[theirs.Result] or theirs.Result),
						RESULT_COLOR[theirs.Result] or C.Text
					)
					you, cpu = number(payload.You), number(payload.Cpu)
					local nextRound = parseRound(payload.Round)
					setRound(nextRound or current)
					setScore()
					task.delay(1.1, function()
						if not screen.isOpen() then
							return -- quit meanwhile
						end
						paper.Transparency = 1
						local outcome = text(payload.Outcome)
						if outcome ~= "" then
							closeGame()
							local parts: { string } =
								{ string.format("You %d – %d %s", you, cpu, opponent.Title) }
							if payload.Rewarded == true then
								table.insert(
									parts,
									string.format(
										"+%d coins · +%d XP",
										number(payload.Coins),
										number(payload.Xp)
									)
								)
								local supply = text(payload.Supply)
								if supply ~= "" then
									table.insert(parts, supply .. " (in your office storage)")
								end
							elseif outcome == "Won" then
								table.insert(
									parts,
									"No reward this time (today's wins are used up)."
								)
							end
							AnnouncementController.show({
								Title = if outcome == "Won"
									then "🏆 YOU WON THE TOSS-OFF!"
									elseif outcome == "Lost" then "🗑️ SO CLOSE!"
									else "🤝 A TIE!",
								Body = if outcome == "Won"
									then "Nothing but paper."
									else "Practice makes swish. Try again!",
								Detail = table.concat(parts, " · "),
								Accent = if outcome == "Won" then C.Good else ACCENT,
								Celebrate = outcome == "Won",
								Seconds = 6,
							})
						else
							beginAim()
						end
					end)
				end)
			end)
		end)
	end

	closeGame = function()
		screen.setOpen(false)
		phase = "Idle"
		if stepConnection then
			stepConnection:Disconnect()
			stepConnection = nil
		end
		ContextActionService:UnbindAction(THROW_ACTION)
	end
end

-- Window -----------------------------------------------------------------------------

local function buildWindow(parent: Instance): ()
	local window = PanelKit.window({
		Name = "PaperToss",
		Title = "🗑️ Paper Toss Showdown",
		Subtitle = "Office basketball against a coworker. Aim, power, swish!",
		Accent = ACCENT,
		DisplayOrder = 6,
	}, parent)
	local content = window.Content

	local function render(): ()
		if not window:isOpen() then
			return
		end
		window:clear()
		local snapshot = ProgressController.get()
		local cleared = if snapshot then snapshot.PaperToss.Cleared else 0
		local best = if snapshot then snapshot.PaperToss.Best else 0
		PanelKit.text(
			content,
			string.format(
				"Your best game: %d points (a perfect game is %d).",
				best,
				PaperTossConfig.Rounds * PaperTossConfig.Points.Swish
			),
			"Heading"
		)
		local grid = PanelKit.grid(content, 170, 214)
		for index, opponent in PaperTossConfig.Opponents do
			local locked = index > cleared + 1
			local card = PanelKit.itemCard(
				grid,
				opponent.Title .. " " .. opponent.Name,
				string.format(
					"💰 %d · ✨ %d XP (x%d first win today)%s",
					opponent.Coins,
					opponent.Xp,
					PaperTossConfig.FirstWinBonus,
					if index == #PaperTossConfig.Opponents then "\n🎁 + an office supply" else ""
				),
				opponent.Icon,
				ACCENT
			)
			if index <= cleared then
				PanelKit.setBadge(card, "✓ Beaten", C.Good)
			end
			card.Button.Text = if locked then "🔒 Beat the one before" else "🗑️ Play!"
			PanelKit.setColor(card.Button, if locked then C.Neutral else C.Good)
			PanelKit.setDisabled(card.Button, locked)
			card.Button.Activated:Connect(function()
				if locked then
					return
				end
				window:close()
				remote("Start"):FireServer(index)
			end)
		end
		local rules = PanelKit.section(content, "📜 How to play", true, true)
		for _, line in
			{
				string.format(
					"%d rounds. Each round you throw, then your coworker throws.",
					PaperTossConfig.Rounds
				),
				"Press STOP (or Space) while the aim marker is in the gold zone, then again for the power bar.",
				"Gold zone = swish, green = in. The zones move with the bin's distance and the breeze.",
				"🎯 Swish = 3 points, ✅ In = 2, off the rim or a miss = 0. Most points wins.",
				string.format(
					"Up to %d rewarded wins a day; the first win against each coworker pays %dx; your first CEO win each day also gives an office supply.",
					PaperTossConfig.DailyRewardedWins,
					PaperTossConfig.FirstWinBonus
				),
			}
		do
			PanelKit.text(rules.Body, "• " .. line, "Muted")
		end
	end
	window:onOpen(function()
		task.defer(render)
	end)
	ProgressController.Changed:Connect(function()
		if window:isOpen() then
			render()
		end
	end)
	openWindow = function()
		window:open()
		render()
	end
end

function PaperTossController.start(): ()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	buildWindow(playerGui)
	buildGame(playerGui)
	remote("State").OnClientEvent:Connect(function(payload: unknown)
		if typeof(payload) ~= "table" then
			return
		end
		local data = payload :: { [string]: unknown }
		if data.Kind == "Start" then
			startGame(
				number(data.Opponent),
				math.max(1, number(data.Rounds)),
				parseRound(data.Round)
			)
		elseif data.Kind == "Round" then
			playRound(data)
		elseif data.Kind == "Quit" then
			closeGame()
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name == "PaperTossPrompt" then
			PaperTossController.open()
		end
	end)
end

return PaperTossController
