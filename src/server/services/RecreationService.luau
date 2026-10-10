--!strict
--[[
	Pickleball at the Recreation Center (docs/PICKLEBALL.md,
	docs/REMOTE_CONTRACTS.md "Rec"). The server owns everything: who plays,
	the ball, line calls, faults, the score, coins, office supplies and the
	rating. Clients only ask (challenge, accept, cancel, swing with an aim,
	forfeit) and draw what they're told.

	  * Challenges: Rec.Challenge(mode) opens one, announced to everyone in the
	    server (Rec.Challenges, the client shows a card unless the player hides
	    challenge notices). Rec.Accept(id, team?) takes a place: checked and set
	    without yielding, so two players can't both get the last one.
	    Rec.Cancel() withdraws (the challenger cancels it for everyone). A
	    challenge expires if it doesn't fill in time; a full one waits for a
	    free court.
	  * Matches: the entry fee is charged to everyone at the start (a match is
	    friendly, with no fee and no rewards, if anyone has reached today's
	    reward caps). Players are moved onto the court, the hammer is put away
	    and a paddle handed over. Rec.Swing(u, v, power) is accepted only from a
	    player whose side the ball is on, with the ball within reach; the
	    server then launches the next flight (Shared/BallFlight) and calls the
	    bounces, faults and score (Shared/PickleballRules).
	  * The end: winners and losers get coins and an office-supply roll, and
	    both ratings change (Elo), once per match id. Leaving before the first
	    point cancels the match and refunds every fee; leaving or forfeiting
	    later loses it for that side (a doubles partner may play on alone).
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Attributes = require(ReplicatedStorage.Shared.Attributes)
local BallFlight = require(ReplicatedStorage.Shared.BallFlight)
local CourtBuilder = require(ServerScriptService.Lib.CourtBuilder)
local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)
local FurnitureRules = require(ReplicatedStorage.Shared.FurnitureRules)
local HammerService = require(script.Parent.HammerService)
local MovementGuardService = require(script.Parent.MovementGuardService)
local PickleballConfig = require(ReplicatedStorage.Config.PickleballConfig)
local PickleballRules = require(ReplicatedStorage.Shared.PickleballRules)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)
local ActivityService = require(script.Parent.ActivityService)
local RecreationRankService = require(script.Parent.RecreationRankService)
local RemoteController = require(ServerScriptService.Controllers.RemoteController)
local RemoteLimits = require(ServerScriptService.Config.RemoteLimits)
local SessionService = require(script.Parent.SessionService)
local Validate = require(ReplicatedStorage.Shared.Validate)

local RecRemotes = ReplicatedStorage.Remotes.Rec
local ToastRemote = ReplicatedStorage.Remotes.Notify.Toast

local COURT = PickleballConfig.Court
local BALL = PickleballConfig.Ball
local SHOT = PickleballConfig.Shot
local GAME = PickleballConfig.Game
local REWARDS = PickleballConfig.Rewards

local PADDLE_ATTRIBUTE = "Paddle"
-- Aim values a client may send (clamped further by the rules).
local AIM_LIMIT = 2
-- How finely a held swing looks ahead for the ball (seconds).
local HOLD_STEP = 0.05

type Challenge = {
	Id: string,
	Mode: string,
	Host: Player,
	Teams: { { Player } },
	CreatedAt: number,
	ExpiresAt: number, -- server time
	Full: boolean, -- waiting for a court
}

type Rally = {
	Flight: BallFlight.Flight?,
	Events: BallFlight.Events?,
	HitterTeam: number, -- who hit the ball in the air now (the server before the serve)
	ShotIndex: number, -- 0 = the serve
	ServeSide: string?, -- set while the serve is in the air
}

type Match = {
	Id: string,
	Mode: string,
	Court: CourtBuilder.Court,
	Teams: { { Player } }, -- [team][slot], as the match started
	Present: { [Player]: boolean }, -- still playing (not left or forfeited)
	Score: PickleballRules.Score,
	Phase: string, -- "Starting" | "Serve" | "Rally" | "Point" | "Ended"
	Rally: Rally,
	Seq: number, -- bumped on every change; delayed checks compare it
	EndsAt: number, -- server time of the time limit
	PointPlayed: boolean,
	Rewarded: boolean, -- false = a friendly match
	Paid: { [Player]: boolean },
	TeamRating: { number }, -- each team's average rating at the start
	LastSwing: { [Player]: number },
	Message: string,
	Finished: boolean,
}

local RecreationService = {}

local center: CourtBuilder.Center? = nil
local challenges: { [string]: Challenge } = {}
local challengeOf: { [Player]: Challenge } = {}
local matches: { [number]: Match } = {} -- court index -> match
local matchOf: { [Player]: Match } = {}
local lastChallengeAt: { [Player]: number } = {}
-- Players leaving the game right now: nothing is handed back to them.
local leavingGame: { [Player]: boolean } = {}
local random = Random.new()

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function toast(player: Player, text: string): ()
	ToastRemote:FireClient(player, text)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function teleport(player: Player, target: CFrame): ()
	local character = player.Character
	if character == nil or character.Parent == nil then
		return
	end
	MovementGuardService.noteTeleport(player)
	character:PivotTo(target)
end

-- The player's pickleball record, moved to this season and UTC day.
local function recordOf(player: Player): PickleballRules.Record?
	local data = PlayerDataService.get(player)
	if data == nil then
		return nil
	end
	local unix = os.time()
	PickleballRules.forSeason(data.Recreation, PickleballRules.seasonId(unix))
	PickleballRules.forDay(data.Recreation, PickleballRules.dayKey(unix))
	return data.Recreation
end

local function isBusy(player: Player): boolean
	return challengeOf[player] ~= nil or matchOf[player] ~= nil
end

-- Whether the player still has rewarded matches today (and so pays a fee).
local function hasRewardsLeft(player: Player): boolean
	local record = recordOf(player)
	return record ~= nil and record.DayMatches < REWARDS.DailyRewarded
end

local function canPay(player: Player): boolean
	local data = PlayerDataService.get(player)
	if data == nil then
		return false
	end
	if hasRewardsLeft(player) and data.Coins < REWARDS.Fee then
		toast(player, string.format("You need %d coins for the entry fee.", REWARDS.Fee))
		return false
	end
	return true
end

-- Challenges ----------------------------------------------------------------------

local function counts(teams: { { Player } }): { number }
	return { #teams[1], #teams[2] }
end

local function playerView(player: Player): { [string]: any }
	return { UserId = player.UserId, Name = player.DisplayName }
end

local function teamsView(teams: { { Player } }): { { { [string]: any } } }
	local view = {}
	for team = 1, 2 do
		local list = {}
		for _, player in teams[team] do
			table.insert(list, playerView(player))
		end
		view[team] = list
	end
	return view
end

local function freeCourts(): number
	local free = 0
	for index in PickleballConfig.Center.Courts do
		if matches[index] == nil then
			free += 1
		end
	end
	return free
end

local function challengeList(): { [string]: any }
	local ordered: { Challenge } = {}
	for _, challenge in challenges do
		table.insert(ordered, challenge)
	end
	table.sort(ordered, function(a, b)
		return a.CreatedAt < b.CreatedAt
	end)
	local list = {}
	local queuePosition = 0
	for _, challenge in ordered do
		if challenge.Full then
			queuePosition += 1
		end
		table.insert(list, {
			Id = challenge.Id,
			Mode = challenge.Mode,
			HostUserId = challenge.Host.UserId,
			HostName = challenge.Host.DisplayName,
			Teams = teamsView(challenge.Teams),
			TeamSize = PickleballRules.teamSize(challenge.Mode),
			ExpiresAt = challenge.ExpiresAt,
			QueuePosition = if challenge.Full then queuePosition else 0,
		})
	end
	return { Challenges = list, FreeCourts = freeCourts() }
end

local function broadcastChallenges(): ()
	RecRemotes.Challenges:FireAllClients(challengeList())
end

local function removeChallenge(challenge: Challenge): ()
	challenges[challenge.Id] = nil
	for _, team in challenge.Teams do
		for _, member in team do
			if challengeOf[member] == challenge then
				challengeOf[member] = nil
			end
		end
	end
end

local startMatch: (challenge: Challenge, court: CourtBuilder.Court) -> ()

-- Starts waiting full challenges, oldest first, on free courts.
local function startQueued(): ()
	local built = center
	if built == nil then
		return
	end
	local waiting: { Challenge } = {}
	for _, challenge in challenges do
		if challenge.Full then
			table.insert(waiting, challenge)
		end
	end
	table.sort(waiting, function(a, b)
		return a.CreatedAt < b.CreatedAt
	end)
	for _, challenge in waiting do
		local court: CourtBuilder.Court? = nil
		for _, candidate in built.Courts do
			if matches[candidate.Index] == nil then
				court = candidate
				break
			end
		end
		if court == nil then
			return
		end
		startMatch(challenge, court)
	end
end

local function expire(challengeId: string, expiresAt: number): ()
	local challenge = challenges[challengeId]
	if challenge == nil or challenge.Full or challenge.ExpiresAt ~= expiresAt then
		return
	end
	removeChallenge(challenge)
	toast(challenge.Host, "Nobody took your pickleball challenge in time.")
	for _, member in challenge.Teams[2] do
		toast(member, "That pickleball challenge expired.")
	end
	for index, member in challenge.Teams[1] do
		if index > 1 then
			toast(member, "That pickleball challenge expired.")
		end
	end
	broadcastChallenges()
end

local function onChallenge(player: Player, rawMode: unknown): ()
	if not PickleballRules.isMode(rawMode) then
		return RemoteController.reject(player, "Rec.Challenge", "unknown mode")
	end
	local mode = rawMode :: string
	if PlayerDataService.get(player) == nil then
		return
	end
	if isBusy(player) then
		return toast(player, "You're already in a pickleball challenge or match.")
	end
	local last = lastChallengeAt[player]
	local cooldown = PickleballConfig.Challenge.Cooldown
	if last and now() - last < cooldown then
		return toast(
			player,
			string.format(
				"Wait %d s before your next challenge.",
				math.ceil(cooldown - (now() - last))
			)
		)
	end
	if not canPay(player) then
		return
	end
	local seconds = PickleballConfig.Challenge.Seconds[mode]
	local challenge: Challenge = {
		Id = HttpService:GenerateGUID(false),
		Mode = mode,
		Host = player,
		Teams = { { player }, {} },
		CreatedAt = now(),
		ExpiresAt = now() + seconds,
		Full = false,
	}
	challenges[challenge.Id] = challenge
	challengeOf[player] = challenge
	lastChallengeAt[player] = now()
	task.delay(seconds, expire, challenge.Id, challenge.ExpiresAt)
	broadcastChallenges()
end

local function onAccept(player: Player, rawId: unknown, rawTeam: unknown): ()
	local challengeId = Validate.id(rawId, RemoteLimits.MaxIdLength)
	if challengeId == nil then
		return RemoteController.reject(player, "Rec.Accept", "bad challenge id")
	end
	local wanted: number? = nil
	if rawTeam ~= nil then
		wanted = Validate.integer(rawTeam, 1, 2)
		if wanted == nil then
			return RemoteController.reject(player, "Rec.Accept", "bad team")
		end
	end
	if PlayerDataService.get(player) == nil then
		return
	end
	-- From here to the seat being taken nothing yields (check-then-set).
	local challenge = challenges[challengeId]
	if challenge == nil then
		return toast(player, "That challenge isn't open any more.")
	end
	if challenge.Host == player then
		return toast(player, "That's your own challenge.")
	end
	if isBusy(player) then
		return toast(player, "You're already in a pickleball challenge or match.")
	end
	if challenge.Full then
		return toast(player, "That match is full.")
	end
	if not canPay(player) then
		return
	end
	local team = PickleballRules.pickTeam(challenge.Mode, counts(challenge.Teams), wanted)
	if team == nil then
		return toast(player, "That match is full.")
	end
	table.insert(challenge.Teams[team], player)
	challengeOf[player] = challenge
	if PickleballRules.isFull(challenge.Mode, counts(challenge.Teams)) then
		challenge.Full = true
		startQueued()
		if challenges[challenge.Id] then
			for _, list in challenge.Teams do
				for _, member in list do
					toast(member, "Both courts are busy: your match starts when one is free.")
				end
			end
		end
	end
	broadcastChallenges()
end

local function leaveChallenge(player: Player): ()
	local challenge = challengeOf[player]
	if challenge == nil then
		return
	end
	if challenge.Host == player then
		removeChallenge(challenge)
		for _, team in challenge.Teams do
			for _, member in team do
				if member ~= player then
					toast(member, player.DisplayName .. " cancelled the pickleball challenge.")
				end
			end
		end
	else
		for _, team in challenge.Teams do
			local index = table.find(team, player)
			if index then
				table.remove(team, index)
			end
		end
		challengeOf[player] = nil
		if challenge.Full then
			-- Waiting for a court no more: it needs a player again, in time.
			challenge.Full = false
			local seconds = PickleballConfig.Challenge.Seconds[challenge.Mode]
			challenge.ExpiresAt = now() + seconds
			task.delay(seconds, expire, challenge.Id, challenge.ExpiresAt)
		end
	end
	broadcastChallenges()
end

local function onCancel(player: Player): ()
	leaveChallenge(player)
end

-- Matches: helpers ---------------------------------------------------------------

local function teamOf(match: Match, player: Player): (number?, number?)
	for team = 1, 2 do
		local slot = table.find(match.Teams[team], player)
		if slot then
			return team, slot
		end
	end
	return nil, nil
end

-- The player in a team's slot; if they left, their partner covers.
local function playerAt(match: Match, team: number, slot: number): Player?
	local player = match.Teams[team][slot]
	if player and match.Present[player] then
		return player
	end
	for _, other in match.Teams[team] do
		if match.Present[other] then
			return other
		end
	end
	return nil
end

local function presentPlayers(match: Match): { Player }
	local list: { Player } = {}
	for _, team in match.Teams do
		for _, player in team do
			if match.Present[player] then
				table.insert(list, player)
			end
		end
	end
	return list
end

local function sideX(team: number, side: string): number
	return PickleballRules.rightSign(team) * (if side == "Right" then 1 else -1)
end

-- Where a player stands before a serve (court-local): at the baseline, or
-- at the kitchen line for the receiver's partner.
local function standPoint(match: Match, team: number, slot: number): Vector3
	local score = match.Score
	local side = PickleballRules.positionOf(score, team, slot)
	local receivingTeam, receiverSlot = PickleballRules.receiver(score)
	local z = PickleballRules.halfSign(team)
	local depth = COURT.Length / 2 + 1.5
	if score.Mode == "Doubles" and team == receivingTeam and slot ~= receiverSlot then
		depth = COURT.Kitchen + 1.5
	end
	return Vector3.new(sideX(team, side) * COURT.Width / 4, 3, z * depth)
end

local function placeAt(match: Match, player: Player, localPoint: Vector3): ()
	local world = CourtBuilder.toWorld(match.Court.Center, localPoint)
	local facing = Vector3.new(world.X, world.Y, match.Court.Center.Z)
	teleport(player, CFrame.lookAt(world, facing))
end

-- The spot a player takes: a doubles player left alone on their team
-- covers whichever of the serve or the return is theirs.
local function coverSlot(match: Match, team: number, slot: number): number
	local present = 0
	for _, player in match.Teams[team] do
		if match.Present[player] then
			present += 1
		end
	end
	if present ~= 1 or match.Mode ~= "Doubles" then
		return slot
	end
	local serverTeam, serverSlot = PickleballRules.server(match.Score)
	local _, receiverSlot = PickleballRules.receiver(match.Score)
	return if team == serverTeam then serverSlot else receiverSlot
end

local function placePlayers(match: Match): ()
	for team = 1, 2 do
		for slot, player in match.Teams[team] do
			if match.Present[player] then
				placeAt(match, player, standPoint(match, team, coverSlot(match, team, slot)))
			end
		end
	end
end

local function buildPaddle(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Paddle"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute(PADDLE_ATTRIBUTE, true)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 1, 0.3)
	handle.Color = Color3.fromRGB(40, 42, 50)
	handle.Massless = true
	handle.CanCollide = false
	handle.CanTouch = false
	handle.Parent = tool
	local face = Instance.new("Part")
	face.Name = "Face"
	face.Size = Vector3.new(1.4, 1.6, 0.15)
	face.Color = Color3.fromRGB(70, 120, 200)
	face.Massless = true
	face.CanCollide = false
	face.CanTouch = false
	face.CFrame = handle.CFrame * CFrame.new(0, 1.25, 0)
	face.Parent = tool
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = face
	weld.Parent = face
	tool.Grip = CFrame.new(0, -0.2, 0)
	return tool
end

local function removePaddles(player: Player): ()
	local containers: { Instance? } = { player.Character, player:FindFirstChildOfClass("Backpack") }
	for _, container in containers do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute(PADDLE_ATTRIBUTE) then
					child:Destroy()
				end
			end
		end
	end
end

local function givePaddle(player: Player): ()
	removePaddles(player)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local backpack = player:FindFirstChildOfClass("Backpack")
	if humanoid == nil or backpack == nil then
		return
	end
	local tool = buildPaddle()
	tool.Parent = backpack
	humanoid:EquipTool(tool)
	humanoid.WalkSpeed = GAME.WalkSpeed
end

local function boardText(match: Match): string
	local function names(team: number): string
		local list = {}
		for _, player in match.Teams[team] do
			table.insert(list, player.DisplayName)
		end
		return table.concat(list, " & ")
	end
	local score = match.Score
	local header = string.format("Court %d · %s", match.Court.Index, match.Mode)
	if match.Phase == "Ended" then
		local winner = score.Winner
		return string.format(
			"%s\n%s %d - %d %s\n%s",
			header,
			names(1),
			score.Points[1],
			score.Points[2],
			names(2),
			if winner then names(winner) .. " won!" else "Match over"
		)
	end
	return string.format(
		"%s\n%s %d - %d %s\nScore: %s",
		header,
		names(1),
		score.Points[1],
		score.Points[2],
		names(2),
		PickleballRules.callout(score)
	)
end

local function sendState(match: Match): ()
	local score = match.Score
	local serverTeam, serverSlot = PickleballRules.server(score)
	local receiverTeam, receiverSlot = PickleballRules.receiver(score)
	local server = playerAt(match, serverTeam, serverSlot)
	local receiver = playerAt(match, receiverTeam, receiverSlot)
	local payload = {
		MatchId = match.Id,
		Court = match.Court.Index,
		Mode = match.Mode,
		Phase = match.Phase,
		Teams = teamsView(match.Teams),
		Points = { score.Points[1], score.Points[2] },
		Serving = score.Serving,
		ServerNumber = score.ServerNumber,
		ServerUserId = if server then server.UserId else 0,
		ReceiverUserId = if receiver then receiver.UserId else 0,
		Callout = PickleballRules.callout(score),
		Message = match.Message,
		EndsAt = match.EndsAt,
		Friendly = not match.Rewarded,
		Winner = score.Winner or 0,
	}
	for _, player in presentPlayers(match) do
		RecRemotes.MatchState:FireClient(player, payload)
	end
	match.Court.Board.Text = boardText(match)
end

local function clearBall(match: Match): ()
	RecRemotes.Shot:FireAllClients({ Court = match.Court.Index, Clear = true })
end

-- Leaving the court: paddle away, hammer back, walk off (not for a player
-- leaving the game).
local function detach(match: Match, player: Player): ()
	if matchOf[player] == match then
		matchOf[player] = nil
	end
	player:SetAttribute(Attributes.RecMatch, nil)
	if leavingGame[player] or player.Parent ~= Players then
		return
	end
	removePaddles(player)
	HammerService.setPutAway(player, false)
	local exit = PickleballConfig.Center.ExitPoint
	local offset = Vector3.new(random:NextNumber(-4, 4), 0, random:NextNumber(-1, 1))
	teleport(player, CFrame.lookAt(exit + offset, exit + offset + Vector3.new(0, 0, 1)))
end

local function release(match: Match): ()
	for _, team in match.Teams do
		for _, player in team do
			if matchOf[player] == match then
				detach(match, player)
			end
		end
	end
	if matches[match.Court.Index] == match then
		matches[match.Court.Index] = nil
	end
	match.Court.Board.Text = string.format("Court %d\nFree", match.Court.Index)
	clearBall(match)
	startQueued()
	broadcastChallenges()
end

local function refundAll(match: Match): ()
	for player in match.Paid do
		if player.Parent == Players then
			SessionService.addCoins(player, REWARDS.Fee)
			ProgressService.sync(player)
		end
	end
	table.clear(match.Paid)
end

local function cancelMatch(match: Match, text: string): ()
	if match.Finished then
		return
	end
	match.Finished = true
	match.Seq += 1
	match.Phase = "Ended"
	refundAll(match)
	for _, player in presentPlayers(match) do
		RecRemotes.Result:FireClient(player, {
			MatchId = match.Id,
			Cancelled = true,
			Reason = text,
		})
	end
	release(match)
end

-- Rewards (once per match id) ---------------------------------------------------

local function markProcessed(player: Player, matchId: string): boolean
	local data = PlayerDataService.get(player)
	if data == nil or table.find(data.ProcessedMatches, matchId) then
		return false
	end
	table.insert(data.ProcessedMatches, matchId)
	while #data.ProcessedMatches > PickleballConfig.MaxProcessedMatches do
		table.remove(data.ProcessedMatches, 1)
	end
	return true
end

local function opponentsOf(match: Match, team: number): string
	local ids = {}
	for _, player in match.Teams[PickleballRules.other(team)] do
		table.insert(ids, player.UserId)
	end
	return PickleballRules.opponentsKey(ids)
end

-- Rating and counters for one player. Returns the rating change.
local function applyRecord(match: Match, player: Player, team: number, won: boolean): number
	local record = recordOf(player)
	if record == nil or not match.Rewarded then
		return 0
	end
	local change = PickleballRules.ratingChange(
		match.TeamRating[team],
		match.TeamRating[PickleballRules.other(team)],
		won
	)
	record.Rating = PickleballRules.clampRating(record.Rating + change)
	if won then
		record.Wins += 1
		record.TotalWins += 1
	else
		record.Losses += 1
		record.TotalLosses += 1
	end
	PickleballRules.noteRewarded(record, opponentsOf(match, team))
	RecreationRankService.noteRecord(player, record)
	return change
end

local function reward(match: Match, player: Player, team: number, won: boolean, reason: string): ()
	if not markProcessed(player, match.Id) then
		return
	end
	local payload: { [string]: any } = {
		MatchId = match.Id,
		Won = won,
		Reason = reason,
		Friendly = not match.Rewarded,
		Points = { match.Score.Points[1], match.Score.Points[2] },
		Team = team,
		Coins = 0,
		Supply = "",
		RatingChange = 0,
		Rating = 0,
	}
	if match.Rewarded then
		local coins = if won then REWARDS.Win else REWARDS.Lose
		SessionService.addCoins(player, coins)
		local pool = if won
			then PickleballConfig.Supplies.Winner
			else PickleballConfig.Supplies.Loser
		local item = PickleballRules.rollSupply(pool, random)
		local data = PlayerDataService.get(player)
		if data and FurnitureRules.grantSpecial(data.Furniture, item, 1) then
			local info = FurnitureConfig.ByKey[item]
			payload.Supply = if info then info.Name else item
		end
		payload.Coins = coins
		payload.RatingChange = applyRecord(match, player, team, won)
		ActivityService.record(player, "PlayMatch", 1)
		if won then
			ActivityService.record(player, "WinMatch", 1)
		end
	end
	local record = recordOf(player)
	payload.Rating = if record then record.Rating else 0
	RecRemotes.Result:FireClient(player, payload)
	ProgressService.sync(player)
end

local function finish(match: Match, winner: number, reason: string): ()
	if match.Finished then
		return
	end
	match.Finished = true
	match.Seq += 1
	match.Phase = "Ended"
	match.Score.Winner = winner
	match.Message = reason
	sendState(match)
	for team = 1, 2 do
		for _, player in match.Teams[team] do
			if match.Present[player] then
				reward(match, player, team, team == winner, reason)
			end
		end
	end
	task.delay(GAME.EndPause, release, match)
end

-- Rallies ------------------------------------------------------------------------

local beginServe: (match: Match) -> ()

local function rallyOver(match: Match, faultTeam: number, fault: string): ()
	if match.Finished then
		return
	end
	match.Seq += 1
	match.Phase = "Point"
	match.PointPlayed = true
	local winner = PickleballRules.other(faultTeam)
	local outcome = PickleballRules.rallyWon(match.Score, winner)
	local faultText = PickleballConfig.FaultText[fault] or "Fault!"
	local result = if outcome == "Point"
		then "Point!"
		elseif outcome == "SecondServer" then "Second server."
		else "Side out."
	match.Message = faultText .. " " .. result
	local champion = match.Score.Winner
	if champion then
		match.Score.Winner = nil -- finish() sets it again
		finish(match, champion, "Game!")
		return
	end
	sendState(match)
	local seq = match.Seq
	task.delay(GAME.PointPause, function()
		if match.Seq == seq and not match.Finished then
			beginServe(match)
		end
	end)
end

local function launch(
	match: Match,
	team: number,
	from: Vector3,
	target: Vector3,
	power: number,
	serveSide: string?
): ()
	local distance = Vector2.new(target.X - from.X, target.Z - from.Z).Magnitude
	local duration = PickleballRules.shotDuration(SHOT, distance, power)
	local flight: BallFlight.Flight = {
		Launch = from,
		Velocity = BallFlight.solve(from, target, duration, BALL.Gravity),
		T0 = now(),
	}
	local events = BallFlight.events(flight, BALL, COURT)
	match.Seq += 1
	match.Phase = "Rally"
	match.Rally = {
		Flight = flight,
		Events = events,
		HitterTeam = team,
		ShotIndex = if serveSide then 0 else match.Rally.ShotIndex + 1,
		ServeSide = serveSide,
	}
	match.Message = ""
	RecRemotes.Shot:FireAllClients({
		Court = match.Court.Index,
		Launch = flight.Launch,
		Velocity = flight.Velocity,
		T0 = flight.T0,
	})
	local seq = match.Seq
	local function still(): boolean
		return match.Seq == seq and not match.Finished
	end
	local netTime = events.NetTime
	if events.NetHit and netTime then
		task.delay(netTime, function()
			if still() then
				rallyOver(match, team, "Net")
			end
		end)
		return
	end
	task.delay(events.BounceTime, function()
		if not still() then
			return
		end
		local fault = PickleballRules.judgeBounce(COURT, events.BouncePoint, team, serveSide)
		if fault then
			rallyOver(match, team, fault)
			return
		end
		task.delay(events.SecondBounceTime - events.BounceTime, function()
			if still() then
				rallyOver(match, PickleballRules.other(team), "DoubleBounce")
			end
		end)
	end)
end

local function serve(match: Match, player: Player, u: number, v: number, power: number): ()
	local team, slot, side = PickleballRules.server(match.Score)
	if playerAt(match, team, slot) ~= player then
		return
	end
	-- From where the server stands, kept behind the baseline on their side.
	local root = rootOf(player)
	local spot = if root
		then CourtBuilder.toLocal(match.Court.Center, root.Position)
		else standPoint(match, team, slot)
	local sign = sideX(team, side)
	local x = sign * math.clamp(spot.X * sign, 0.5, COURT.Width / 2 - 0.5)
	local z = PickleballRules.halfSign(team)
		* math.max(spot.Z * PickleballRules.halfSign(team), COURT.Length / 2 + 0.5)
	local from = Vector3.new(x, BALL.ServeHeight, z)
	local aim = PickleballRules.aimTarget(COURT, team, u, v, side)
	local target =
		PickleballRules.scatter(aim, PickleballRules.scatterRadius(SHOT, 0, power), random)
	launch(match, team, from, target, power, side)
end

function beginServe(match: Match): ()
	if match.Finished then
		return
	end
	match.Seq += 1
	match.Phase = "Serve"
	local team, slot = PickleballRules.server(match.Score)
	match.Rally = { HitterTeam = team, ShotIndex = 0 }
	clearBall(match)
	placePlayers(match)
	sendState(match)
	-- An idle server serves automatically (a gentle, middle serve).
	local seq = match.Seq
	task.delay(GAME.ServeTimeout, function()
		if match.Seq ~= seq or match.Finished then
			return
		end
		local server = playerAt(match, team, slot)
		if server then
			serve(match, server, 0, 0.5, SHOT.NormalPower)
		end
	end)
end

-- The ball's horizontal distance from `spot` if a player of `team` standing
-- there can reach it at `point`, else nil.
local function reachOf(team: number, point: Vector3, spot: Vector3): number?
	local distance = Vector2.new(point.X - spot.X, point.Z - spot.Z).Magnitude
	if
		PickleballRules.onHalf(team, point)
		and point.Y <= SHOT.MaxHitHeight
		and distance <= SHOT.Reach + SHOT.ReachGrace
	then
		return distance
	end
	return nil
end

local function lastLiveTime(events: BallFlight.Events): number
	return if events.NetHit then (events.NetTime or 0) else events.SecondBounceTime
end

-- Where the ball was closest to the player within the lag window, if within
-- reach and not before `minTime`: (seconds after launch, ball position, distance).
local function ballInReach(
	rally: Rally,
	team: number,
	spot: Vector3,
	minTime: number
): (number?, Vector3?, number?)
	local flight, events = rally.Flight, rally.Events
	if flight == nil or events == nil then
		return nil, nil, nil
	end
	local elapsed = now() - flight.T0
	local lastLive = lastLiveTime(events)
	local best: number?, bestPoint: Vector3?, bestDistance: number? = nil, nil, nil
	for step = 0, 4 do
		local t = elapsed - SHOT.LagWindow * step / 4
		if t >= 0 and t >= minTime and t <= lastLive then
			local point = BallFlight.positionAt(flight, events, BALL, t)
			local distance = reachOf(team, point, spot)
			if distance and (bestDistance == nil or distance < bestDistance) then
				best, bestPoint, bestDistance = t, point, distance
			end
		end
	end
	return best, bestPoint, bestDistance
end

-- The first moment in the next SwingHold seconds (and not before `minTime`)
-- when the ball comes within reach of `spot`, as seconds from now.
local function heldWait(rally: Rally, team: number, spot: Vector3, minTime: number): number?
	local flight, events = rally.Flight, rally.Events
	if flight == nil or events == nil then
		return nil
	end
	local elapsed = now() - flight.T0
	local lastLive = lastLiveTime(events)
	for wait = HOLD_STEP, SHOT.SwingHold + 1e-6, HOLD_STEP do
		local t = elapsed + wait
		if t > lastLive then
			return nil
		end
		if t >= minTime and reachOf(team, BallFlight.positionAt(flight, events, BALL, t), spot) then
			return wait
		end
	end
	return nil
end

-- A swing during a rally. A swing a little early is held (`held` false the
-- first time) until the ball comes in reach, and a volley that would be a
-- fault waits for the bounce if it's coming soon; otherwise it's called.
local function strike(
	match: Match,
	player: Player,
	u: number,
	v: number,
	power: number,
	held: boolean
): ()
	local team = teamOf(match, player)
	local rally = match.Rally
	local events = rally.Events
	if team == nil or events == nil or match.Phase ~= "Rally" or rally.HitterTeam == team then
		return -- no ball to hit, or it's still coming from this side
	end
	local root = rootOf(player)
	if root == nil then
		return
	end
	local spot = CourtBuilder.toLocal(match.Court.Center, root.Position)
	local inKitchen = PickleballRules.inKitchen(COURT, team, spot)
	-- Volleying (hitting before the bounce) here would be this fault.
	local volleyFault = PickleballRules.hitFault(rally.ShotIndex + 1, false, inKitchen)
	local minTime = if volleyFault then events.BounceTime else 0
	local t, point, distance = ballInReach(rally, team, spot, minTime)
	if t == nil or point == nil or distance == nil then
		if not held then
			local wait = heldWait(rally, team, spot, minTime)
			if wait then
				local seq = match.Seq
				task.delay(wait, function()
					if match.Seq == seq and not match.Finished and match.Present[player] then
						strike(match, player, u, v, power, true)
					end
				end)
				return
			end
		end
		if volleyFault and ballInReach(rally, team, spot, 0) ~= nil then
			rallyOver(match, team, volleyFault)
		end
		return -- a miss: the rally goes on
	end
	local from = Vector3.new(point.X, math.max(point.Y, BALL.MinHitHeight), point.Z)
	local aim = PickleballRules.aimTarget(COURT, team, u, v, nil)
	local target =
		PickleballRules.scatter(aim, PickleballRules.scatterRadius(SHOT, distance, power), random)
	launch(match, team, from, target, power, nil)
end

local function onSwing(player: Player, rawU: unknown, rawV: unknown, rawPower: unknown): ()
	local u = Validate.number(rawU, -AIM_LIMIT, AIM_LIMIT)
	local v = Validate.number(rawV, -AIM_LIMIT, AIM_LIMIT)
	local power = Validate.number(rawPower, 0, 1)
	if u == nil or v == nil or power == nil then
		return RemoteController.reject(player, "Rec.Swing", "bad aim or power")
	end
	local match = matchOf[player]
	if match == nil or match.Finished or not match.Present[player] then
		return
	end
	-- Someone moving impossibly fast (e.g. teleporting to the ball) can't hit.
	if MovementGuardService.isSuspect(player) then
		return
	end
	local last = match.LastSwing[player]
	if last and now() - last < SHOT.SwingCooldown then
		return
	end
	match.LastSwing[player] = now()
	if match.Phase == "Serve" then
		serve(match, player, u, v, power)
		return
	end
	strike(match, player, u, v, power, false)
end

-- Leaving and forfeiting --------------------------------------------------------

local function leaveMatch(match: Match, player: Player, how: string): ()
	if not match.Present[player] then
		return
	end
	if match.Finished then
		match.Present[player] = nil
		detach(match, player)
		return
	end
	if not match.PointPlayed then
		cancelMatch(
			match,
			string.format("%s %s before the first point: fees refunded.", player.DisplayName, how)
		)
		return
	end
	local team = teamOf(match, player) :: number
	match.Present[player] = nil
	-- The leaver's side loses this match for them: counted and rated now, no
	-- coins or supplies (and never again for this match id).
	if markProcessed(player, match.Id) then
		applyRecord(match, player, team, false)
	end
	detach(match, player)
	local partnerLeft = false
	for _, other in match.Teams[team] do
		if match.Present[other] then
			partnerLeft = true
		end
	end
	if not partnerLeft then
		finish(match, PickleballRules.other(team), player.DisplayName .. " " .. how .. ".")
		return
	end
	match.Message = player.DisplayName .. " " .. how .. ". Play on, or forfeit."
	sendState(match)
	if match.Phase == "Serve" then
		beginServe(match) -- the partner covers the serve
	end
end

local function onForfeit(player: Player): ()
	local match = matchOf[player]
	if match then
		leaveMatch(match, player, "forfeited")
	end
end

-- Starting a match -------------------------------------------------------------------

function startMatch(challenge: Challenge, court: CourtBuilder.Court): ()
	removeChallenge(challenge)
	local everyone: { Player } = {}
	for _, team in challenge.Teams do
		for _, player in team do
			if player.Parent ~= Players or PlayerDataService.get(player) == nil then
				-- Someone left in the meantime (normally removed on leave).
				for _, list in challenge.Teams do
					for _, member in list do
						toast(member, "A player left, so the match couldn't start.")
					end
				end
				broadcastChallenges()
				return
			end
			table.insert(everyone, player)
		end
	end
	local match: Match = {
		Id = challenge.Id,
		Mode = challenge.Mode,
		Court = court,
		Teams = { table.clone(challenge.Teams[1]), table.clone(challenge.Teams[2]) },
		Present = {},
		Score = PickleballRules.newScore(challenge.Mode, 1),
		Phase = "Starting",
		Rally = { HitterTeam = 1, ShotIndex = 0 },
		Seq = 0,
		EndsAt = now() + GAME.TimeLimit,
		PointPlayed = false,
		Rewarded = true,
		Paid = {},
		TeamRating = { PickleballConfig.Rating.Start, PickleballConfig.Rating.Start },
		LastSwing = {},
		Message = "Get ready!",
		Finished = false,
	}
	-- Friendly if anyone has used up today's rewarded matches (or against
	-- these opponents): no fee, coins, supplies or rating for anyone.
	for team = 1, 2 do
		local ratings = {}
		for _, player in match.Teams[team] do
			local record = recordOf(player)
			if record == nil or not PickleballRules.canEarn(record, opponentsOf(match, team)) then
				match.Rewarded = false
			end
			table.insert(ratings, if record then record.Rating else PickleballConfig.Rating.Start)
		end
		match.TeamRating[team] = PickleballRules.average(ratings)
	end
	if match.Rewarded then
		for _, player in everyone do
			if not SessionService.trySpendCoins(player, REWARDS.Fee) then
				refundAll(match)
				for _, member in everyone do
					toast(
						member,
						player.DisplayName .. " can't pay the entry fee: the match is cancelled."
					)
				end
				broadcastChallenges()
				return
			end
			match.Paid[player] = true
			ProgressService.sync(player)
		end
	end
	matches[court.Index] = match
	for _, player in everyone do
		match.Present[player] = true
		matchOf[player] = match
		player:SetAttribute(Attributes.RecMatch, match.Id)
		HammerService.setPutAway(player, true)
		givePaddle(player)
		if not match.Rewarded then
			toast(player, "Friendly match: today's rewarded matches are used up for someone here.")
		end
	end
	placePlayers(match)
	sendState(match)
	broadcastChallenges()
	task.delay(GAME.StartPause, beginServe, match)
	task.delay(GAME.TimeLimit, function()
		if match.Finished then
			return
		end
		local leader = PickleballRules.leader(match.Score)
		if leader then
			finish(match, leader, "Time's up!")
		else
			cancelMatch(
				match,
				"Time's up with the score tied: the match is cancelled and fees refunded."
			)
		end
	end)
end

-- Court guard ---------------------------------------------------------------------------

local function courtBox(court: CourtBuilder.Court): (Vector3, Vector3)
	local half = Vector3.new(COURT.Width / 2 + COURT.RunOff, 0, COURT.Length / 2 + COURT.RunOff)
	return court.Center - half, court.Center + half
end

local function guardTick(): ()
	local built = center
	if built == nil then
		return
	end
	for _, court in built.Courts do
		local match = matches[court.Index]
		if match == nil or match.Finished then
			continue
		end
		local low, high = courtBox(court)
		for _, player in Players:GetPlayers() do
			local root = rootOf(player)
			if root == nil then
				continue
			end
			local position = root.Position
			local inside = position.X >= low.X
				and position.X <= high.X
				and position.Z >= low.Z
				and position.Z <= high.Z
				and position.Y < court.Center.Y + 30
			local team, slot = teamOf(match, player)
			if team and slot and match.Present[player] then
				-- Players stay on their own half of their court.
				local spot = CourtBuilder.toLocal(court.Center, position)
				if not inside or not PickleballRules.onHalf(team, spot) then
					placeAt(match, player, standPoint(match, team, coverSlot(match, team, slot)))
				end
			elseif inside then
				-- Spectators watch from outside the fence.
				local side = if position.X < court.Center.X then -1 else 1
				local x = court.Center.X + side * (COURT.Width / 2 + COURT.RunOff + 2)
				local target = Vector3.new(x, court.Center.Y + 3, position.Z)
				teleport(
					player,
					CFrame.lookAt(target, Vector3.new(court.Center.X, target.Y, target.Z))
				)
			end
		end
	end
end

-- Lifecycle ---------------------------------------------------------------------------

local function onCharacterAdded(player: Player): ()
	local match = matchOf[player]
	if match == nil or match.Finished then
		return
	end
	task.defer(function()
		local character = player.Character
		if character then
			character:WaitForChild("Humanoid", 10)
		end
		if matchOf[player] ~= match or match.Finished then
			return
		end
		HammerService.setPutAway(player, true)
		givePaddle(player)
		local team, slot = teamOf(match, player)
		if team and slot then
			placeAt(match, player, standPoint(match, team, coverSlot(match, team, slot)))
		end
	end)
end

local watched: { [Player]: boolean } = {}

local function watch(player: Player): ()
	if watched[player] then
		return
	end
	watched[player] = true
	player.CharacterAdded:Connect(function()
		onCharacterAdded(player)
	end)
end

local function onPlayerRemoving(player: Player): ()
	leavingGame[player] = true
	leaveChallenge(player)
	local match = matchOf[player]
	if match then
		leaveMatch(match, player, "left")
	end
	lastChallengeAt[player] = nil
	leavingGame[player] = nil
end

function RecreationService.init(): ()
	RemoteController.bind(RecRemotes.Challenge, {
		name = "Rec.Challenge",
		maxArgs = 1,
		rateLimit = RemoteLimits.Rec,
	}, onChallenge)
	RemoteController.bind(RecRemotes.Accept, {
		name = "Rec.Accept",
		maxArgs = 2,
		rateLimit = RemoteLimits.Rec,
	}, onAccept)
	RemoteController.bind(RecRemotes.Cancel, {
		name = "Rec.Cancel",
		maxArgs = 0,
		rateLimit = RemoteLimits.Rec,
	}, onCancel)
	RemoteController.bind(RecRemotes.Forfeit, {
		name = "Rec.Forfeit",
		maxArgs = 0,
		rateLimit = RemoteLimits.Rec,
	}, onForfeit)
	RemoteController.bind(RecRemotes.Swing, {
		name = "Rec.Swing",
		maxArgs = 3,
		rateLimit = RemoteLimits.RecSwing,
	}, onSwing)
	Players.PlayerAdded:Connect(watch)
	-- Before the leaver's data is saved, so a forfeit by leaving counts.
	PlayerDataService.beforeRelease(onPlayerRemoving)
	-- Players whose data never loaded can't be in a challenge or match, but
	-- clean up anyway.
	Players.PlayerRemoving:Connect(function(player: Player)
		onPlayerRemoving(player)
		watched[player] = nil
	end)
end

function RecreationService.start(): ()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	center = CourtBuilder.build(Workspace)
	PlayerDataService.onLoaded(function(player: Player)
		recordOf(player) -- start a new season or day if one began since the last visit
		ProgressService.sync(player)
		RecRemotes.Challenges:FireClient(player, challengeList())
	end)
	while true do
		task.wait(GAME.GuardInterval)
		guardTick()
	end
end

return RecreationService
