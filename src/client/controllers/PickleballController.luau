--!strict
--[[
	Pickleball on the client (docs/PICKLEBALL.md). Display and input only:
	the server decides who plays, every hit, line call, fault, score and
	reward (RecreationService).

	  * Challenges (Rec.Challenges): a card with ACCEPT for each new one
	    (unless "Hide challenge notices" is on, or you're playing), a
	    "🏓 n open" chip on the HUD, and the Pickleball panel: challenge
	    Singles or Doubles, open challenges to join (doubles: pick a team),
	    your rating and today's rewarded matches, how to play, the prizes.
	    Opened from the chip, the Recreation Center sign or the Social page.
	  * Matches (Rec.MatchState, the RecMatch attribute): a score bar with the
	    called score, who serves and what just happened, the time left and
	    Forfeit. Controls: click / tap 🏓 / R2 swings, Q / Soft / L2 hits soft,
	    E / Hard / R1 hits hard. You aim at a spot on the other side with the
	    mouse (or where the camera looks); the server clamps the aim and adds
	    spread for hard or stretched shots.
	  * The ball (Rec.Shot): every client draws every court's ball from the
	    server's launch numbers (Shared/BallFlight), with a ring where it will
	    bounce. One RenderStepped connection, only while a ball is moving.
	  * Results (Rec.Result): a card with the coins, the office supply and
	    the rating change.
	  * The season (Rec.Season): the board (top 10, all servers when the
	    server can read it) on the panel's Season tab, and a card when the
	    server hands out a finished season's prize.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = ReplicatedStorage:WaitForChild("Config")
local Attributes = require(Shared:WaitForChild("Attributes"))
local BallFlight = require(Shared:WaitForChild("BallFlight"))
local FurnitureConfig = require(Config:WaitForChild("FurnitureConfig"))
local PickleballConfig = require(Config:WaitForChild("PickleballConfig"))
local PickleballRules = require(Shared:WaitForChild("PickleballRules"))

local AnnouncementController = require(script.Parent.AnnouncementController)
local EventController = require(script.Parent.EventController)
local PanelKit = require(script.Parent.Parent.Lib.PanelKit)
local ProgressController = require(script.Parent.ProgressController)
local Responsive = require(script.Parent.Parent.Lib.Responsive)
local SettingsController = require(script.Parent.SettingsController)
local UiTokens = require(script.Parent.Parent.Lib.UiTokens)

local PickleballController = {}

local C = PanelKit.Colors
local ACCENT = Color3.fromRGB(110, 210, 120)
local CARD_COLOR = Color3.fromRGB(26, 29, 41)
local BALL_COLOR = Color3.fromRGB(230, 240, 90)
local REACH_COLOR = Color3.fromRGB(90, 255, 120)
local COURT = PickleballConfig.Court
local BALL = PickleballConfig.Ball
local SHOT = PickleballConfig.Shot
local MAX_NAME = 40
-- A ball that has come to rest disappears after this long.
local REST_SECONDS = 3
local SWING_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ARM_WINDUP = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ARM_SWEEP = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local ARM_BACK = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

export type Seat = { UserId: number, Name: string }

export type BoardRow = { UserId: number, Name: string, Rating: number }

export type SeasonBoard = {
	SeasonId: number,
	EndsAt: number,
	Global: boolean,
	Top: { BoardRow },
}

export type Challenge = {
	Id: string,
	Mode: string,
	HostUserId: number,
	HostName: string,
	Teams: { { Seat } },
	TeamSize: number,
	ExpiresAt: number,
	QueuePosition: number,
}

type MatchView = {
	MatchId: string,
	Court: number,
	Mode: string,
	Phase: string,
	Teams: { { Seat } },
	Points: { number },
	Serving: number,
	ServerNumber: number,
	ServerUserId: number,
	Callout: string,
	Message: string,
	EndsAt: number,
	Friendly: boolean,
}

type Ball = {
	Part: Part,
	Marker: Part,
	Center: Vector3,
	Flight: BallFlight.Flight?,
	Events: BallFlight.Events?,
}

local localPlayer = Players.LocalPlayer
local remotes: Folder? = nil
local challengeList: { Challenge } = {}
local freeCourts = 0
local seen: { [string]: boolean } = {}
local match: MatchView? = nil
local balls: { [number]: Ball } = {}
local renderConnection: RBXScriptConnection? = nil
local changedEvent = Instance.new("BindableEvent")
local openPanel: (() -> ())? = nil
local seasonBoard: SeasonBoard? = nil
-- Each shoulder joint's C0 before the first swing (the swing returns to it).
local shoulderRest: { [Motor6D]: CFrame? } = setmetatable({}, { __mode = "k" }) :: any

-- Fires when the challenge list or the match changes.
PickleballController.Changed = changedEvent.Event

local function remote(name: string): RemoteEvent
	local folder = remotes :: Folder
	local event = folder:WaitForChild(name)
	assert(event:IsA("RemoteEvent"), "Rec." .. name .. " must be a RemoteEvent")
	return event
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function text(value: unknown, fallback: string): string
	if typeof(value) == "string" and #value <= 300 and utf8.len(value) ~= nil then
		return value
	end
	return fallback
end

local function number(value: unknown, fallback: number): number
	return if typeof(value) == "number" and value == value then value else fallback
end

local function parseSeats(raw: unknown): { { Seat } }
	local teams: { { Seat } } = { {}, {} }
	if typeof(raw) ~= "table" then
		return teams
	end
	for team = 1, 2 do
		local list = (raw :: { unknown })[team]
		if typeof(list) == "table" then
			for _, entry in list :: { unknown } do
				if typeof(entry) == "table" then
					local seat = entry :: { [string]: unknown }
					local userId = number(seat.UserId, 0)
					-- Not "> 0": Studio's local test players have negative ids.
					if userId ~= 0 then
						table.insert(teams[team], {
							UserId = userId,
							Name = string.sub(text(seat.Name, "Player"), 1, MAX_NAME),
						})
					end
				end
			end
		end
	end
	return teams
end

local function teamOfMine(teams: { { Seat } }): number?
	for team = 1, 2 do
		for _, seat in teams[team] do
			if seat.UserId == localPlayer.UserId then
				return team
			end
		end
	end
	return nil
end

local function names(seats: { Seat }): string
	local list = {}
	for _, seat in seats do
		table.insert(list, if seat.UserId == localPlayer.UserId then "You" else seat.Name)
	end
	return if #list > 0 then table.concat(list, " & ") else "?"
end

local function playing(): boolean
	local id = localPlayer:GetAttribute(Attributes.RecMatch)
	return typeof(id) == "string" and id ~= ""
end

function PickleballController.challenges(): { Challenge }
	return challengeList
end

function PickleballController.freeCourts(): number
	return freeCourts
end

-- The open challenge the local player is in, if any.
function PickleballController.mine(): Challenge?
	for _, challenge in challengeList do
		if teamOfMine(challenge.Teams) then
			return challenge
		end
	end
	return nil
end

function PickleballController.challenge(mode: string): ()
	remote("Challenge"):FireServer(mode)
end

function PickleballController.accept(challengeId: string, team: number?): ()
	remote("Accept"):FireServer(challengeId, team)
end

function PickleballController.cancel(): ()
	remote("Cancel"):FireServer()
end

function PickleballController.open(): ()
	if openPanel then
		openPanel()
	end
end

-- The ball ---------------------------------------------------------------------------

local function ballFor(index: number): Ball?
	local existing = balls[index]
	if existing then
		return existing
	end
	local centerPoint: Vector3? = PickleballConfig.Center.Courts[index]
	if centerPoint == nil then
		return nil
	end
	local folder = Workspace:FindFirstChild("PickleballBalls")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "PickleballBalls"
		folder.Parent = Workspace
	end
	local part = Instance.new("Part")
	part.Name = "Ball" .. index
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * BALL.Radius * 2
	part.Color = BALL_COLOR
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Parent = folder
	local marker = Instance.new("Part")
	marker.Name = "Bounce" .. index
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(0.05, 1.6, 1.6)
	marker.Color = BALL_COLOR
	marker.Material = Enum.Material.Neon
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Transparency = 1
	marker.Parent = folder
	local ball: Ball = { Part = part, Marker = marker, Center = centerPoint }
	balls[index] = ball
	return ball
end

local function hide(ball: Ball): ()
	ball.Flight, ball.Events = nil, nil
	ball.Part.Transparency = 1
	ball.Marker.Transparency = 1
end

-- Whether the local player could hit a ball at `position` (court-local) on
-- court `index` now; the same reach the server checks (RecreationService).
local function inMyReach(index: number, ball: Ball, position: Vector3): boolean
	local current = match
	local character = localPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if current == nil or current.Court ~= index or root == nil or not root:IsA("BasePart") then
		return false
	end
	local team = teamOfMine(current.Teams)
	if team == nil or not PickleballRules.onHalf(team, position) then
		return false
	end
	local spot = root.Position - ball.Center
	local distance = Vector2.new(position.X - spot.X, position.Z - spot.Z).Magnitude
	return position.Y <= SHOT.MaxHitHeight and distance <= SHOT.Reach
end

local function step(): ()
	local now = serverNow()
	local moving = false
	for index, ball in balls do
		local flight, events = ball.Flight, ball.Events
		if flight and events then
			local t = now - flight.T0
			local position = BallFlight.positionAt(flight, events, BALL, t)
			ball.Part.Position = ball.Center + position + Vector3.new(0, BALL.Radius, 0)
			ball.Part.Transparency = 0
			-- Green while it's in reach: swing now.
			local reachable = inMyReach(index, ball, position)
			ball.Part.Color = if reachable then REACH_COLOR else BALL_COLOR
			ball.Part.Material = if reachable
				then Enum.Material.Neon
				else Enum.Material.SmoothPlastic
			-- The bounce ring shows until the ball gets there.
			ball.Marker.Transparency = if t < events.BounceTime and not events.NetHit
				then 0.4
				else 1
			local finished = if events.NetHit
				then (events.NetTime or 0) + 1
				else events.SecondBounceTime
			if t > finished + REST_SECONDS then
				hide(ball)
			else
				moving = true
			end
		end
	end
	if not moving and renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
end

local function onShot(payload: unknown): ()
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	local index = number(data.Court, 0)
	local ball = ballFor(index)
	if ball == nil then
		return
	end
	if data.Clear == true then
		hide(ball)
		return
	end
	local launch, velocity = data.Launch, data.Velocity
	if typeof(launch) ~= "Vector3" or typeof(velocity) ~= "Vector3" then
		return
	end
	local flight: BallFlight.Flight =
		{ Launch = launch, Velocity = velocity, T0 = number(data.T0, serverNow()) }
	local events = BallFlight.events(flight, BALL, COURT)
	ball.Flight, ball.Events = flight, events
	ball.Marker.CFrame = CFrame.new(ball.Center + events.BouncePoint + Vector3.new(0, 0.08, 0))
		* CFrame.Angles(0, 0, math.rad(90))
	if renderConnection == nil then
		renderConnection = RunService.RenderStepped:Connect(step)
	end
end

-- Swinging ---------------------------------------------------------------------------

-- Where the player aims on the other side: (u across, v deep), from the
-- mouse or, without one, the middle of the screen.
local function aim(team: number, courtIndex: number, usePointer: boolean): (number, number)
	local centerPoint: Vector3? = PickleballConfig.Center.Courts[courtIndex]
	local camera = Workspace.CurrentCamera
	if centerPoint == nil or camera == nil then
		return 0, 0.6
	end
	local screen = if usePointer
		then UserInputService:GetMouseLocation()
		else camera.ViewportSize / 2
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	if ray.Direction.Y > -0.01 then
		return 0, 0.6
	end
	local distance = (centerPoint.Y - ray.Origin.Y) / ray.Direction.Y
	local spot = ray.Origin + ray.Direction * distance - centerPoint
	local opponents = PickleballRules.other(team)
	local u = spot.X / (COURT.Width / 2 - 0.5)
	if not PickleballRules.onHalf(opponents, spot) then
		return math.clamp(u, -1, 1), 0.6
	end
	local v = (math.abs(spot.Z) - 1) / (COURT.Length / 2 - 1.5)
	return math.clamp(u, -1, 1), math.clamp(v, 0, 1)
end

local function rightShoulder(character: Model): Motor6D?
	local upper = character:FindFirstChild("RightUpperArm") -- R15
	local motor = if upper then upper:FindFirstChild("RightShoulder") else nil
	if motor == nil then
		local torso = character:FindFirstChild("Torso") -- R6
		motor = if torso then torso:FindFirstChild("Right Shoulder") else nil
	end
	return if motor and motor:IsA("Motor6D") then motor else nil
end

-- A forehand: the arm winds back to the right, sweeps across and returns.
-- Turned in the torso's frame, so R6 and R15 swing the same way. Local
-- only (other players see the ball fly).
local function animateSwing(): ()
	local character = localPlayer.Character
	if character == nil then
		return
	end
	local motor = rightShoulder(character)
	if motor then
		local saved: CFrame? = shoulderRest[motor]
		local rest: CFrame = saved or motor.C0
		shoulderRest[motor] = rest
		local function turned(pitch: number, yaw: number): CFrame
			return CFrame.new(rest.Position)
				* CFrame.Angles(math.rad(pitch), math.rad(yaw), 0)
				* rest.Rotation
		end
		local windUp = TweenService:Create(motor, ARM_WINDUP, { C0 = turned(10, -55) })
		local sweep = TweenService:Create(motor, ARM_SWEEP, { C0 = turned(25, 50) })
		local back = TweenService:Create(motor, ARM_BACK, { C0 = rest })
		windUp.Completed:Connect(function()
			sweep:Play()
		end)
		sweep.Completed:Connect(function()
			back:Play()
		end)
		windUp:Play()
	end
	local tool = character:FindFirstChildOfClass("Tool")
	if tool == nil or tool:GetAttribute("Paddle") ~= true then
		return
	end
	local rest = CFrame.new(0, -0.2, 0)
	local swung = rest * CFrame.Angles(math.rad(-70), math.rad(30), 0)
	local out = TweenService:Create(tool, UiTokens.motion(SWING_TWEEN), { Grip = swung })
	out.Completed:Connect(function()
		TweenService:Create(tool, UiTokens.motion(SWING_TWEEN), { Grip = rest }):Play()
	end)
	out:Play()
end

local function swing(power: number, usePointer: boolean): ()
	local current = match
	if current == nil or not playing() then
		return
	end
	local team = teamOfMine(current.Teams)
	if team == nil then
		return
	end
	local u, v = aim(team, current.Court, usePointer)
	animateSwing()
	remote("Swing"):FireServer(u, v, power)
end

-- Cards ------------------------------------------------------------------------------

local function seatsText(challenge: Challenge): string
	if challenge.Mode ~= "Doubles" then
		return "Singles (1 v 1)"
	end
	local joined = #challenge.Teams[1] + #challenge.Teams[2]
	return string.format("Doubles (2 v 2) · %d of 4 joined", joined)
end

local function feeText(): string
	return string.format(
		"Entry fee %d coins · win %d, lose %d + an office supply",
		PickleballConfig.Rewards.Fee,
		PickleballConfig.Rewards.Win,
		PickleballConfig.Rewards.Lose
	)
end

local function announce(challenge: Challenge): ()
	if
		SettingsController.get("HideChallenges")
		or playing()
		or PickleballController.mine() ~= nil
	then
		return
	end
	AnnouncementController.show({
		Title = "🏓 PICKLEBALL CHALLENGE",
		Body = string.format("%s wants a %s match!", challenge.HostName, challenge.Mode),
		Detail = seatsText(challenge) .. "\n" .. feeText(),
		Accent = ACCENT,
		Seconds = 10,
		ActionLabel = "ACCEPT",
		OnAction = function()
			PickleballController.accept(challenge.Id, nil)
		end,
	})
end

local function onChallenges(payload: unknown): ()
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	local list: { Challenge } = {}
	local raw = data.Challenges
	if typeof(raw) == "table" then
		for _, entry in raw :: { unknown } do
			if typeof(entry) == "table" then
				local item = entry :: { [string]: unknown }
				local id = text(item.Id, "")
				local mode = text(item.Mode, "")
				if id ~= "" and PickleballRules.isMode(mode) then
					table.insert(list, {
						Id = id,
						Mode = mode,
						HostUserId = number(item.HostUserId, 0),
						HostName = string.sub(text(item.HostName, "Someone"), 1, MAX_NAME),
						Teams = parseSeats(item.Teams),
						TeamSize = PickleballRules.teamSize(mode),
						ExpiresAt = number(item.ExpiresAt, 0),
						QueuePosition = number(item.QueuePosition, 0),
					})
				end
			end
		end
	end
	challengeList = list
	freeCourts = number(data.FreeCourts, 0)
	local current: { [string]: boolean } = {}
	for _, challenge in list do
		current[challenge.Id] = true
		if not seen[challenge.Id] then
			seen[challenge.Id] = true
			if challenge.HostUserId ~= localPlayer.UserId then
				announce(challenge)
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

local function onResult(payload: unknown): ()
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	if data.Cancelled == true then
		AnnouncementController.show({
			Title = "🏓 MATCH CANCELLED",
			Body = text(data.Reason, "The match was cancelled."),
			Accent = C.Muted,
			Seconds = 8,
		})
		return
	end
	local won = data.Won == true
	local points = data.Points
	local team = number(data.Team, 1)
	local final = ""
	if typeof(points) == "table" then
		local list = points :: { unknown }
		local own, theirs = number(list[team], 0), number(list[PickleballRules.other(team)], 0)
		final = string.format("Final score %d-%d", own, theirs)
	end
	local lines: { string } = {}
	if data.Friendly == true then
		table.insert(lines, "Friendly match: no coins, supplies or rating today.")
	else
		table.insert(lines, string.format("+%d coins", number(data.Coins, 0)))
		local supply = text(data.Supply, "")
		if supply ~= "" then
			table.insert(lines, "📦 " .. supply .. " for your office")
		end
	end
	local change = number(data.RatingChange, 0)
	local detail = final
	if data.Friendly ~= true then
		detail = string.format(
			"%s · Rating %d (%s%d)",
			final,
			number(data.Rating, 0),
			if change >= 0 then "+" else "",
			change
		)
	end
	AnnouncementController.show({
		Title = if won then "🏆 YOU WON!" else "🏓 GOOD GAME!",
		Body = text(data.Reason, "") .. "\n" .. table.concat(lines, " · "),
		Detail = detail,
		Accent = if won then C.Heading else ACCENT,
		Celebrate = won,
		Seconds = 12,
		ActionLabel = "PLAY AGAIN",
		OnAction = PickleballController.open,
	})
end

local function parseMatch(payload: unknown): MatchView?
	if typeof(payload) ~= "table" then
		return nil
	end
	local data = payload :: { [string]: unknown }
	local id = text(data.MatchId, "")
	if id == "" then
		return nil
	end
	local points = { 0, 0 }
	if typeof(data.Points) == "table" then
		local list = data.Points :: { unknown }
		points = { number(list[1], 0), number(list[2], 0) }
	end
	return {
		MatchId = id,
		Court = number(data.Court, 1),
		Mode = text(data.Mode, "Singles"),
		Phase = text(data.Phase, ""),
		Teams = parseSeats(data.Teams),
		Points = points,
		Serving = number(data.Serving, 1),
		ServerNumber = number(data.ServerNumber, 1),
		ServerUserId = number(data.ServerUserId, 0),
		Callout = text(data.Callout, ""),
		Message = text(data.Message, ""),
		EndsAt = number(data.EndsAt, 0),
		Friendly = data.Friendly == true,
	}
end

-- The season -------------------------------------------------------------------------

local function parseBoard(data: { [string]: unknown }): SeasonBoard
	local rows: { BoardRow } = {}
	if typeof(data.Top) == "table" then
		for _, raw in data.Top :: { unknown } do
			if typeof(raw) == "table" and #rows < PickleballConfig.SeasonBoard.Size then
				local row = raw :: { [string]: unknown }
				local userId = number(row.UserId, 0)
				if userId ~= 0 then
					table.insert(rows, {
						UserId = userId,
						Name = string.sub(text(row.Name, "Player"), 1, MAX_NAME),
						Rating = number(row.Rating, 0),
					})
				end
			end
		end
	end
	return {
		SeasonId = number(data.SeasonId, 0),
		EndsAt = number(data.EndsAt, 0),
		Global = data.Global == true,
		Top = rows,
	}
end

local function onSeason(payload: unknown): ()
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	if data.Kind == "Board" then
		seasonBoard = parseBoard(data)
		changedEvent:Fire()
	elseif data.Kind == "Prize" then
		local item = text(data.Item, "")
		AnnouncementController.show({
			Title = "🏆 SEASON RESULTS",
			Body = string.format(
				"Pickleball Season %d is over: you finished #%d!",
				PickleballRules.seasonNumber(number(data.SeasonId, 0)),
				number(data.Rank, 0)
			),
			Detail = string.format("+%d coins", number(data.Coins, 0))
				.. if item ~= "" then " · " .. item .. " (in your office storage)" else "",
			Accent = C.Heading,
			Celebrate = true,
			Seconds = 15,
		})
	end
end

function PickleballController.season(): SeasonBoard?
	return seasonBoard
end

-- Match HUD --------------------------------------------------------------------------

local function buildHud(): (ScreenGui, () -> ())
	local gui = Instance.new("ScreenGui")
	gui.Name = "PickleballHud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 4
	gui.Enabled = false

	local bar = Instance.new("Frame")
	bar.Name = "ScoreBar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
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
		label.RichText = false
		label.Parent = bar
		Responsive.capText(label, size, 11)
		return label
	end
	local scoreLine = line(1, Enum.Font.FredokaOne, 24, C.Text)
	local serveLine = line(2, Enum.Font.GothamBold, 16, C.Heading)
	local messageLine = line(3, Enum.Font.GothamMedium, 16, ACCENT)
	local hintLine = line(4, Enum.Font.GothamMedium, 13, C.Muted)

	-- Shot buttons (touch) and Forfeit.
	local buttons = Instance.new("Frame")
	buttons.Name = "Shots"
	buttons.BackgroundTransparency = 1
	buttons.AnchorPoint = Vector2.new(1, 1)
	buttons.Parent = gui
	local function shotButton(name: string, label: string, color: Color3, power: number): TextButton
		local button = PanelKit.button(buttons, label, color)
		button.Name = name
		button.Activated:Connect(function()
			swing(power, false)
		end)
		return button
	end
	local soft = shotButton("Soft", "Soft", C.Primary, SHOT.SoftPower)
	local normal = shotButton("Swing", "🏓", ACCENT, SHOT.NormalPower)
	local hard = shotButton("Hard", "Hard", C.Danger, SHOT.HardPower)
	local forfeit = PanelKit.button(gui, "Forfeit", C.Neutral)
	forfeit.Name = "Forfeit"
	forfeit.AnchorPoint = Vector2.new(1, 0)
	local confirmUntil = 0
	forfeit.Activated:Connect(function()
		if os.clock() < confirmUntil then
			remote("Forfeit"):FireServer()
			confirmUntil = 0
			forfeit.Text = "Forfeit"
			return
		end
		confirmUntil = os.clock() + 3
		forfeit.Text = "Sure? Tap again"
		task.delay(3, function()
			if os.clock() >= confirmUntil then
				forfeit.Text = "Forfeit"
			end
		end)
	end)

	Responsive.onChanged(function()
		local phone = Responsive.formFactor() == "Phone"
		local touch = Responsive.hasTouch()
		bar.Position = UDim2.new(0.5, 0, 1, if touch then -12 else -16)
		bar.Size = UDim2.fromScale(if phone then 0.5 else 0.42, 0)
		buttons.Visible = touch
		buttons.Position = UDim2.new(1, -16, 1, -150)
		local size = if phone then 64 else 76
		buttons.Size = UDim2.fromOffset(size * 3 + 16, size)
		for index, button in { soft, normal, hard } do
			button.Size = UDim2.fromOffset(size, size)
			button.Position = UDim2.fromOffset((index - 1) * (size + 8), 0)
		end
		forfeit.Position = UDim2.new(1, -16, 0, if phone then 64 else 120)
		forfeit.Size = UDim2.fromOffset(150, 40)
		hintLine.Visible = not touch
	end)

	local function refresh(): ()
		local current = match
		if current == nil or not playing() then
			gui.Enabled = false
			return
		end
		gui.Enabled = true
		local mine = teamOfMine(current.Teams) or 1
		local other = PickleballRules.other(mine)
		scoreLine.Text = string.format(
			"%s  %d - %d  %s",
			names(current.Teams[mine]),
			current.Points[mine],
			current.Points[other],
			names(current.Teams[other])
		)
		local serverName = "?"
		for _, team in current.Teams do
			for _, seat in team do
				if seat.UserId == current.ServerUserId then
					serverName = if seat.UserId == localPlayer.UserId then "You" else seat.Name
				end
			end
		end
		local left = math.max(0, current.EndsAt - serverNow())
		local clock = string.format("%d:%02d left", left // 60, math.floor(left % 60))
		if current.Phase == "Ended" then
			serveLine.Text = "Match over"
		elseif current.Phase == "Starting" then
			serveLine.Text = "Get ready! " .. clock
		else
			serveLine.Text = string.format(
				"Score %s · %s serving%s · %s",
				current.Callout,
				serverName,
				if serverName == "You" and current.Phase == "Serve" then " (swing!)" else "",
				clock
			)
		end
		messageLine.Text = current.Message
		messageLine.Visible = current.Message ~= ""
		hintLine.Text = "Aim with the mouse · Click: swing when the ball turns green · Q: soft · E: hard"
			.. if current.Friendly then " · Friendly match" else ""
	end
	return gui, refresh
end

-- Panel -------------------------------------------------------------------------------

local function buildPanel(parent: Instance): ()
	local window = PanelKit.window({
		Name = "Pickleball",
		Title = "🏓 Pickleball",
		Subtitle = "Challenge other players at the Recreation Center behind the office.",
		Accent = ACCENT,
		DisplayOrder = 5,
	}, parent)
	local content = window.Content
	local activeTab = "Play"
	local countdowns: { [TextLabel]: number } = {}

	local function playPage(): ()
		local snapshot = ProgressController.get()
		local you = PanelKit.section(content, "You", false, true)
		if snapshot then
			local record = snapshot.Recreation
			local grid = PanelKit.grid(you.Body, 150, 70)
			PanelKit.statTile(grid, "Rating", tostring(record.Rating), C.Heading)
			PanelKit.statTile(
				grid,
				"This season",
				string.format("%d W · %d L", record.Wins, record.Losses)
			)
			PanelKit.statTile(
				grid,
				"All time",
				string.format("%d W · %d L", record.TotalWins, record.TotalLosses)
			)
			local today = PickleballRules.dayKey(os.time())
			local used = if record.DayKey == today then record.DayMatches else 0
			PanelKit.statTile(
				grid,
				"Rewarded today",
				string.format("%d / %d", used, PickleballConfig.Rewards.DailyRewarded)
			)
		end

		local start = PanelKit.section(content, "Start a match", false, true)
		local mine = PickleballController.mine()
		if playing() then
			PanelKit.text(start.Body, "You're playing a match right now.", "Muted")
		elseif mine then
			local status = if mine.QueuePosition > 0
				then string.format(
					"Full! Waiting for a free court (#%d in line).",
					mine.QueuePosition
				)
				else string.format("Your %s challenge is open. %s", mine.Mode, seatsText(mine))
			PanelKit.text(start.Body, status, "Muted")
			local row = PanelKit.row(start.Body)
			local leave = PanelKit.button(
				row,
				if mine.HostUserId == localPlayer.UserId then "Cancel challenge" else "Leave",
				C.Danger
			)
			leave.Size = UDim2.new(0.5, -4, 1, 0)
			leave.Activated:Connect(PickleballController.cancel)
		else
			PanelKit.text(start.Body, feeText(), "Muted")
			local row = PanelKit.row(start.Body)
			for _, mode in PickleballConfig.Modes do
				local button = PanelKit.button(
					row,
					if mode == "Singles" then "Challenge: Singles" else "Challenge: Doubles",
					ACCENT
				)
				button.Size = UDim2.new(0.5, -4, 1, 0)
				button.Activated:Connect(function()
					PickleballController.challenge(mode)
				end)
			end
			PanelKit.text(
				start.Body,
				"Everyone in the server sees your challenge and can accept it. The fee is only charged when the match starts.",
				"Muted"
			)
		end

		local open = PanelKit.section(
			content,
			string.format("Open challenges · %d court(s) free", freeCourts),
			false,
			true
		)
		local others = 0
		for _, challenge in challengeList do
			if challenge.HostUserId == localPlayer.UserId then
				continue
			end
			others += 1
			local row = PanelKit.row(open.Body, 56)
			local label = Instance.new("TextLabel")
			label.LayoutOrder = 1
			label.BackgroundTransparency = 1
			label.Size = UDim2.new(1, -230, 1, 0)
			label.Font = PanelKit.FONT
			label.TextColor3 = C.Text
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextWrapped = true
			label.Text = string.format(
				"%s · %s\n%s",
				challenge.HostName,
				seatsText(challenge),
				if challenge.Mode == "Doubles"
					then string.format(
						"Team A: %s · Team B: %s",
						names(challenge.Teams[1]),
						names(challenge.Teams[2])
					)
					else ""
			)
			label.Parent = row
			PanelKit.setTextSize(label, PanelKit.SMALL_SIZE)
			local joined = teamOfMine(challenge.Teams) ~= nil
			local busy = playing() or (mine ~= nil and not joined)
			if challenge.Mode == "Doubles" and not joined then
				for team = 1, 2 do
					local full = #challenge.Teams[team] >= challenge.TeamSize
					local join =
						PanelKit.button(row, if team == 1 then "Join A" else "Join B", C.Primary)
					join.Size = UDim2.fromOffset(105, 46)
					PanelKit.setDisabled(join, full or busy or challenge.QueuePosition > 0)
					join.Activated:Connect(function()
						PickleballController.accept(challenge.Id, team)
					end)
				end
			elseif not joined then
				local accept = PanelKit.button(row, "Accept", ACCENT)
				accept.Size = UDim2.fromOffset(150, 46)
				PanelKit.setDisabled(accept, busy or challenge.QueuePosition > 0)
				accept.Activated:Connect(function()
					PickleballController.accept(challenge.Id, nil)
				end)
			else
				local joinedLabel = PanelKit.text(row, "You're in", "Muted")
				joinedLabel.Size = UDim2.fromOffset(150, 46)
			end
			if challenge.QueuePosition == 0 then
				local countdown = PanelKit.text(open.Body, "", "Muted")
				countdowns[countdown] = challenge.ExpiresAt
			end
		end
		if others == 0 then
			PanelKit.notice(open.Body, "Empty", "No open challenges right now. Start one above!")
		end
	end

	local function rulesPage(): ()
		local how = PanelKit.section(content, "How to play", false, true)
		for _, line in
			{
				"Walk to the ball and swing: click or tap 🏓 (R2 on a controller). Q / Soft (L2) for a gentle dink or lob, E / Hard (R1) for a drive.",
				"Aim with the mouse at a spot on the other side (on touch or a controller, where the camera looks). Hard shots and balls at the edge of your reach go less straight.",
				"The yellow ring shows where the ball will bounce.",
			}
		do
			PanelKit.text(how.Body, line)
		end
		local rules = PanelKit.section(content, "Rules (standard pickleball)", false, true)
		for _, line in
			{
				"One game to 11, win by 2. Only the serving side scores.",
				"Serve diagonally, past the kitchen and its line. Singles: from the right on an even score, from the left on an odd one.",
				"Doubles: both partners serve before the other side gets the serve, except at the start (0-0-2). The score is called serving team, receiving team, server number.",
				"Two-bounce rule: the serve and the return must each bounce before they're hit.",
				"The kitchen: the 7-stud zone next to the net. No volleys (hitting before the bounce) while standing in it.",
				"Faults: into the net, out (a ball on a line is in), two bounces, a volley from the kitchen or before the two-bounce rule allows.",
				"Leaving before the first point cancels the match and refunds the fees. Leaving or forfeiting later loses the match for your side. 20 minutes at most: the side ahead wins.",
			}
		do
			PanelKit.text(rules.Body, line)
		end
	end

	local function prizesPage(): ()
		local rewards = PickleballConfig.Rewards
		local coins = PanelKit.section(content, "Coins", false, true)
		PanelKit.text(coins.Body, feeText() .. ". Doubles pays every player the same.")
		PanelKit.text(
			coins.Body,
			string.format(
				"Up to %d rewarded matches a day (UTC), and %d against the same opponents. After that, matches are friendly: no fee, no coins, no supplies, no rating change.",
				rewards.DailyRewarded,
				rewards.SameOpponentsPerDay
			),
			"Muted"
		)
		for _, pool in
			{
				{ Title = "Office supplies: winners", List = PickleballConfig.Supplies.Winner },
				{ Title = "Office supplies: losers", List = PickleballConfig.Supplies.Loser },
			}
		do
			local section = PanelKit.section(content, pool.Title, true, true)
			for _, entry in pool.List do
				local item = FurnitureConfig.ByKey[entry.Item]
				PanelKit.text(
					section.Body,
					string.format("%s: %d%%", if item then item.Name else entry.Item, entry.Weight)
				)
			end
		end
		local season = PanelKit.section(content, "Season prizes (top 10)", false, true)
		local from = 1
		for _, prize in PickleballConfig.SeasonPrizes do
			local item = FurnitureConfig.ByKey[prize.Item]
			PanelKit.text(
				season.Body,
				string.format(
					"%s: %d coins + %s",
					if from == prize.MaxRank
						then string.format("#%d", from)
						else string.format("#%d-%d", from, prize.MaxRank),
					prize.Coins,
					if item then item.Name else prize.Item
				)
			)
			from = prize.MaxRank + 1
		end
		PanelKit.text(
			season.Body,
			string.format(
				"Ranked after %d rated matches in the season. Prizes are handed out when you next play after the season ends.",
				PickleballConfig.SeasonBoard.MinMatches
			),
			"Muted"
		)
		local rating = PanelKit.section(content, "Rating and seasons", false, true)
		PanelKit.text(
			rating.Body,
			string.format(
				"Everyone starts each season at %d. Beating stronger players gains more. Seasons last 4 weeks and start on Mondays (00:00 UTC).",
				PickleballConfig.Rating.Start
			)
		)
	end

	local function seasonPage(): ()
		local board = seasonBoard
		local seasonId = if board then board.SeasonId else PickleballRules.seasonId(os.time())
		local left = math.max(0, PickleballRules.seasonEnds(seasonId) - serverNow())
		local header = PanelKit.section(
			content,
			string.format("Season %d", PickleballRules.seasonNumber(seasonId)),
			false,
			true
		)
		PanelKit.text(
			header.Body,
			string.format(
				"Ends in %d d %d h. The top %d when it ends win a prize (🏆 Prizes tab).",
				left // 86400,
				(left % 86400) // 3600,
				PickleballConfig.SeasonBoard.Size
			)
		)
		local snapshot = ProgressController.get()
		if snapshot then
			local record = snapshot.Recreation
			local played = if record.SeasonId == seasonId then record.Wins + record.Losses else 0
			local need = PickleballConfig.SeasonBoard.MinMatches - played
			local rank = nil
			if board then
				for index, row in board.Top do
					if row.UserId == localPlayer.UserId then
						rank = index
					end
				end
			end
			PanelKit.text(
				header.Body,
				if need > 0
					then string.format(
						"Play %d more rated match%s this season to be ranked.",
						need,
						if need == 1 then "" else "es"
					)
					elseif rank then string.format("You're #%d. Keep it up!", rank)
					else "You're ranked, but not in the top 10 yet.",
				"Muted"
			)
		end
		local top = PanelKit.section(content, "Top 10", false, true)
		if board == nil or #board.Top == 0 then
			PanelKit.notice(
				top.Body,
				"Empty",
				string.format(
					"Nobody is ranked yet. Play %d rated matches to get on the board!",
					PickleballConfig.SeasonBoard.MinMatches
				)
			)
		else
			for index, row in board.Top do
				local mine = row.UserId == localPlayer.UserId
				PanelKit.text(
					top.Body,
					string.format(
						"%d. %s · %d",
						index,
						if mine then row.Name .. " (you)" else row.Name,
						row.Rating
					),
					if mine then "Heading" else nil
				)
			end
		end
		if board and not board.Global then
			PanelKit.text(top.Body, "This server only (the season board is offline).", "Muted")
		end
	end

	local function render(): ()
		window:clear()
		table.clear(countdowns)
		window:selectTab(activeTab)
		if activeTab == "Play" then
			playPage()
		elseif activeTab == "Rules" then
			rulesPage()
		elseif activeTab == "Season" then
			seasonPage()
		else
			prizesPage()
		end
	end

	window:setTabs({
		{ Id = "Play", Label = "🏓 Play" },
		{ Id = "Rules", Label = "📖 How to play" },
		{ Id = "Season", Label = "📈 Season" },
		{ Id = "Prizes", Label = "🏆 Prizes" },
	}, function(id: string)
		activeTab = id
		render()
	end)
	window:onOpen(function()
		task.defer(render)
	end)
	openPanel = function()
		activeTab = "Play"
		if window:isOpen() then
			render()
		else
			window:open()
		end
	end
	local function refresh(): ()
		if window:isOpen() and (activeTab == "Play" or activeTab == "Season") then
			render()
		end
	end
	PickleballController.Changed:Connect(refresh)
	ProgressController.Changed:Connect(refresh)
	task.spawn(function()
		while true do
			task.wait(1)
			if window:isOpen() then
				local now = serverNow()
				for label, expiresAt in countdowns do
					label.Text =
						string.format("Expires in %d s", math.max(0, math.ceil(expiresAt - now)))
				end
			end
		end
	end)
end

-- HUD chip: open challenges ------------------------------------------------------

local function buildChip(parent: Instance): ()
	local gui = Instance.new("ScreenGui")
	gui.Name = "PickleballChip"
	gui.ResetOnSpawn = false
	gui.Parent = parent
	local chip = Instance.new("TextButton")
	chip.Name = "ChallengesChip"
	chip.Size = UDim2.fromOffset(140, 36)
	chip.BackgroundColor3 = Color3.fromRGB(40, 90, 60)
	chip.TextColor3 = C.Text
	chip.Font = Enum.Font.FredokaOne
	chip.AutoButtonColor = true
	chip.Visible = false
	chip.Parent = gui
	Instance.new("UICorner").Parent = chip
	Responsive.capText(chip, 18)
	chip.Activated:Connect(PickleballController.open)
	local function update(): ()
		local count = #challengeList
		chip.Visible = count > 0 and not playing()
		chip.Text = string.format("🏓 %d OPEN", count)
		-- Beside the events chip when one shows (EventController), else in its place.
		local x = if #EventController.active() > 0 then 16 + 128 else 16
		chip.Position = UDim2.fromOffset(x, 16 + 56)
	end
	PickleballController.Changed:Connect(update)
	EventController.Changed:Connect(update)
	localPlayer:GetAttributeChangedSignal(Attributes.RecMatch):Connect(update)
	update()
end

function PickleballController.start(): ()
	remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Rec") :: Folder
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	buildPanel(playerGui)
	buildChip(playerGui)
	local hud, refreshHud = buildHud()
	hud.Parent = playerGui

	remote("Challenges").OnClientEvent:Connect(onChallenges)
	remote("Shot").OnClientEvent:Connect(onShot)
	remote("Result").OnClientEvent:Connect(onResult)
	remote("Season").OnClientEvent:Connect(onSeason)
	remote("MatchState").OnClientEvent:Connect(function(payload: unknown)
		local parsed = parseMatch(payload)
		if parsed then
			match = parsed
			refreshHud()
			changedEvent:Fire()
		end
	end)
	localPlayer:GetAttributeChangedSignal(Attributes.RecMatch):Connect(function()
		if not playing() then
			match = nil
		end
		refreshHud()
		changedEvent:Fire()
	end)

	-- Controls during a match only; presses on buttons or chat don't count.
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or not playing() then
			return
		end
		local kind, key = input.UserInputType, input.KeyCode
		if kind == Enum.UserInputType.MouseButton1 then
			swing(SHOT.NormalPower, true)
		elseif key == Enum.KeyCode.ButtonR2 then
			swing(SHOT.NormalPower, false)
		elseif key == Enum.KeyCode.Q then
			swing(SHOT.SoftPower, true)
		elseif key == Enum.KeyCode.ButtonL2 then
			swing(SHOT.SoftPower, false)
		elseif key == Enum.KeyCode.E then
			swing(SHOT.HardPower, true)
		elseif key == Enum.KeyCode.ButtonR1 then
			swing(SHOT.HardPower, false)
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name == "PickleballPrompt" then
			PickleballController.open()
		end
	end)

	-- The clock on the score bar.
	task.spawn(function()
		while true do
			task.wait(1)
			if match and playing() then
				refreshHud()
			end
		end
	end)
end

return PickleballController
