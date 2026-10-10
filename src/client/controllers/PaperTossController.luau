--!strict
--[[
	Paper Toss Showdown on the client (docs/PAPER_TOSS.md).

	  * Window (the booth at the Recreation Center, or 🏢 Social): pick a CPU
	    coworker (Intern Izzy, Manager Max, CEO Cora; beat each to unlock the
	    next), your best score and the rules.
	  * Game screen: a little office in a ViewportFrame with the bin at this
	    round's distance and a desk-fan breeze arrow. Tap THROW to stop the
	    sweeping aim marker, tap again to stop the power bar; your paper ball
	    arcs to where it lands (swish, in, off the rim or a miss), then the
	    coworker throws. Scores and the round on top.
	The server judges every throw and pays the rewards (PaperTossService).
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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

local function buildGame(parent: Instance): ()
	local gui = Instance.new("ScreenGui")
	gui.Name = "PaperTossGame"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.Enabled = false
	gui.Parent = parent

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.7, 0.82)
	panel.BackgroundColor3 = C.Window
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UiTokens.Radius.Window)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = ACCENT
	stroke.Thickness = 2
	stroke.Parent = panel
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(820, 620)
	limit.Parent = panel
	Responsive.onChanged(function()
		panel.Size = if Responsive.formFactor() == "Phone"
			then UDim2.fromScale(0.96, 0.92)
			else UDim2.fromScale(0.7, 0.82)
	end)

	local scoreboard = Instance.new("TextLabel")
	scoreboard.BackgroundTransparency = 1
	scoreboard.Position = UDim2.fromScale(0.02, 0.01)
	scoreboard.Size = UDim2.fromScale(0.96, 0.08)
	scoreboard.Font = Enum.Font.FredokaOne
	scoreboard.TextColor3 = C.Text
	scoreboard.Parent = panel
	Responsive.capText(scoreboard, 24)

	-- The office.
	local viewport = Instance.new("ViewportFrame")
	viewport.Position = UDim2.fromScale(0.02, 0.1)
	viewport.Size = UDim2.fromScale(0.96, 0.5)
	viewport.BackgroundColor3 = Color3.fromRGB(205, 220, 240)
	viewport.Ambient = Color3.fromRGB(200, 200, 210)
	viewport.LightColor = Color3.fromRGB(255, 250, 240)
	viewport.Parent = panel
	local vpCorner = Instance.new("UICorner")
	vpCorner.CornerRadius = UDim.new(0, 12)
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

	local windLabel = Instance.new("TextLabel")
	windLabel.BackgroundTransparency = 0.3
	windLabel.BackgroundColor3 = C.Window
	windLabel.Position = UDim2.fromScale(0.03, 0.12)
	windLabel.Size = UDim2.fromScale(0.3, 0.06)
	windLabel.Font = PanelKit.FONT_BOLD
	windLabel.TextColor3 = C.Text
	windLabel.Parent = panel
	Responsive.capText(windLabel, 16)
	Instance.new("UICorner").Parent = windLabel

	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromScale(0.02, 0.61)
	status.Size = UDim2.fromScale(0.96, 0.07)
	status.Font = PanelKit.FONT_BOLD
	status.TextColor3 = C.Heading
	status.Parent = panel
	Responsive.capText(status, 20)

	-- Meters.
	local function meter(y: number, label: string): (Frame, Frame)
		local track = Instance.new("Frame")
		track.Position = UDim2.fromScale(0.08, y)
		track.Size = UDim2.fromScale(0.84, 0.05)
		track.BackgroundColor3 = C.Field
		track.Parent = panel
		Instance.new("UICorner").Parent = track
		local caption = Instance.new("TextLabel")
		caption.BackgroundTransparency = 1
		caption.Position = UDim2.fromOffset(-48, 0)
		caption.Size = UDim2.new(0, 44, 1, 0)
		caption.Font = PanelKit.FONT_BOLD
		caption.Text = label
		caption.TextColor3 = C.Muted
		caption.TextScaled = true
		caption.Parent = track
		local marker = Instance.new("Frame")
		marker.AnchorPoint = Vector2.new(0.5, 0.5)
		marker.Position = UDim2.fromScale(0.5, 0.5)
		marker.Size = UDim2.new(0, 8, 1.6, 0)
		marker.BackgroundColor3 = Color3.fromRGB(255, 220, 90)
		marker.Parent = track
		Instance.new("UICorner").Parent = marker
		return track, marker
	end
	local _, aimMarker = meter(0.7, "AIM")
	local _, powerMarker = meter(0.78, "POWER")

	local actions = Instance.new("Frame")
	actions.BackgroundTransparency = 1
	actions.Position = UDim2.fromScale(0.08, 0.86)
	actions.Size = UDim2.fromScale(0.84, 0.11)
	actions.Parent = panel
	local actionsLayout = Instance.new("UIListLayout")
	actionsLayout.FillDirection = Enum.FillDirection.Horizontal
	actionsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	actionsLayout.Padding = UDim.new(0, 8)
	actionsLayout.Parent = actions
	local throwButton = PanelKit.button(actions, "🧻 THROW", C.Good)
	throwButton.Size = UDim2.fromScale(0.7, 1)
	local quitButton = PanelKit.button(actions, "🚪 Quit", C.Neutral)
	quitButton.Size = UDim2.fromScale(0.26, 1)

	-- State.
	local phase = "Idle" -- "Aim" | "Power" | "Flying" | "Idle"
	local sweepStart = os.clock()
	local aim, power = 0.5, 0.5
	local current: RoundView? = nil
	local opponentIndex = 1
	local rounds = PaperTossConfig.Rounds
	local you, cpu = 0, 0

	local function sweep(seconds: number): number
		local t = ((os.clock() - sweepStart) / seconds) % 2
		return if t <= 1 then t else 2 - t
	end

	local function setRound(round: RoundView?): ()
		current = round
		if round then
			bin.Position = Vector3.new(0, 0.8, BIN_Z[round.Distance] or -6)
			binRim.Position = Vector3.new(0, 1.7, BIN_Z[round.Distance] or -6)
			windLabel.Text = windText(round.Wind)
		end
	end

	local function setScore(): ()
		local opponent = PaperTossConfig.Opponents[opponentIndex]
		scoreboard.Text = string.format(
			"You %d  –  %d %s %s   ·   Round %d / %d",
			you,
			cpu,
			opponent.Icon,
			opponent.Title,
			math.min(if current then current.Number else rounds, rounds),
			rounds
		)
	end

	local function beginAim(): ()
		phase = "Aim"
		sweepStart = os.clock()
		status.Text = "Tap THROW to stop the aim marker"
		throwButton.Text = "🎯 AIM"
		PanelKit.setDisabled(throwButton, false)
	end

	-- Where a throw lands, from how far it was from the ideal one.
	local function landing(round: RoundView, throw: ThrowView): Vector3
		local idealAim, idealPower =
			PaperTossRules.ideal({ Distance = round.Distance, Wind = round.Wind })
		local binAt = Vector3.new(0, 1.6, BIN_Z[round.Distance] or -6)
		if throw.Result == "Swish" then
			return binAt + Vector3.new(0, -0.6, 0)
		elseif throw.Result == "In" then
			return binAt + Vector3.new((throw.Aim - idealAim) * 4, -0.4, 0)
		end
		local offset = Vector3.new((throw.Aim - idealAim) * 14, 0, -(throw.Power - idealPower) * 16)
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

	RunService.RenderStepped:Connect(function()
		if not gui.Enabled then
			return
		end
		if phase == "Aim" then
			aim = sweep(PaperTossConfig.AimSweepSeconds)
		elseif phase == "Power" then
			power = sweep(PaperTossConfig.PowerSweepSeconds)
		end
		aimMarker.Position = UDim2.fromScale(aim, 0.5)
		powerMarker.Position = UDim2.fromScale(power, 0.5)
	end)

	throwButton.Activated:Connect(function()
		if phase == "Aim" then
			phase = "Power"
			sweepStart = os.clock()
			status.Text = "Tap THROW to stop the power bar"
			throwButton.Text = "💪 POWER"
		elseif phase == "Power" then
			phase = "Flying"
			PanelKit.setDisabled(throwButton, true)
			status.Text = "..."
			remote("Throw"):FireServer(aim, power)
		end
	end)
	quitButton.Activated:Connect(function()
		remote("Quit"):FireServer()
		closeGame()
	end)

	startGame = function(opponent: number, total: number, round: RoundView?)
		opponentIndex = math.clamp(opponent, 1, #PaperTossConfig.Opponents)
		rounds = total
		you, cpu = 0, 0
		gui.Enabled = true
		paper.Transparency = 1
		setRound(round)
		setScore()
		beginAim()
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
		fly(playedRound, mine, THROW_FROM, function()
			status.Text = "You: " .. (RESULT_TEXT[mine.Result] or mine.Result)
			you = number(payload.You) - theirs.Points
			setScore()
			task.delay(0.6, function()
				fly(playedRound, theirs, THROW_FROM + Vector3.new(2.5, 0, 0), function()
					local opponent = PaperTossConfig.Opponents[opponentIndex]
					status.Text = string.format(
						"%s: %s",
						opponent.Title,
						RESULT_TEXT[theirs.Result] or theirs.Result
					)
					you, cpu = number(payload.You), number(payload.Cpu)
					local nextRound = parseRound(payload.Round)
					setRound(nextRound or current)
					setScore()
					task.delay(0.8, function()
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
		gui.Enabled = false
		phase = "Idle"
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
				"Tap THROW to stop the sweeping aim marker, then again to stop the power bar.",
				"Far bins need more power. Aim a little against the breeze (the arrow shows where it blows).",
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
