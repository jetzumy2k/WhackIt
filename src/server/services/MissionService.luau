--!strict
--[[
	Team boss missions (docs/MISSIONS.md, major update Phase 5b; decisions
	D11-D13). Bosses never attack; nobody takes damage.

	* Teams: a player opens a team for a mission (Mission.Open); others join
	  (Mission.Join) from the card or the panel. The leader starts it
	  (Mission.Begin) once it has TeamMin players; it starts by itself when
	  full, and closes after LobbySeconds. Everyone sees the open teams
	  (Mission.Teams).
	* A run: the team is teleported to a free mission room
	  (Lib/MissionRoomBuilder) and clears the mission's waves before the
	  time limit. Wave bosses are BossService mission bosses: they don't
	  respawn and only the team may hit them; boss health scales with the
	  team size. Each accepted hit on them counts for its player
	  (BossService.onHit). The normal boss rewards apply to every defeat.
	* Clearing it: every player still in the room with enough hits
	  (MissionRules.counted: hits, not damage, so levels don't decide) gets
	  the mission reward, up to DailyRewarded a UTC day (Missions record in
	  the saved data); then everyone goes back to the lobby. Time running out
	  ends it without the mission reward.
	* Leaving: Mission.Leave, leaving the game or a team going empty. A
	  player who leaves a run gets nothing more from it; the others carry on.
	  A reset character is put back in the room.
	Clients send a mission id or a team id; never a hit count, a wave, a
	result or a reward. Every remote is validated and rate-limited.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local Attributes = require(ReplicatedStorage.Shared.Attributes)
local BagRules = require(ReplicatedStorage.Shared.BagRules)
local BossService = require(script.Parent.BossService)
local CustomBossConfig = require(ReplicatedStorage.Config.CustomBossConfig)
local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)
local FurnitureRules = require(ReplicatedStorage.Shared.FurnitureRules)
local MissionConfig = require(ReplicatedStorage.Config.MissionConfig)
local MissionRoomBuilder = require(ServerScriptService.Lib.MissionRoomBuilder)
local MissionRules = require(ReplicatedStorage.Shared.MissionRules)
local MovementGuardService = require(script.Parent.MovementGuardService)
local PickleballConfig = require(ReplicatedStorage.Config.PickleballConfig)
local PickleballRules = require(ReplicatedStorage.Shared.PickleballRules)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)
local QuestRules = require(ReplicatedStorage.Shared.QuestRules)
local RemoteController = require(ServerScriptService.Controllers.RemoteController)
local RemoteLimits = require(ServerScriptService.Config.RemoteLimits)
local SessionService = require(script.Parent.SessionService)
local Validate = require(ReplicatedStorage.Shared.Validate)

local MissionRemotes = ReplicatedStorage.Remotes.Mission
local ToastRemote = ReplicatedStorage.Remotes.Notify.Toast

local REWARD = MissionConfig.Reward
-- How often a running mission re-sends hit counts when they changed.
local STATE_INTERVAL = 2

type Team = {
	Id: string,
	Mission: MissionConfig.Mission,
	Leader: Player,
	Members: { Player },
	ExpiresAt: number, -- server time
}

type Run = {
	Id: string,
	Number: number,
	Mission: MissionConfig.Mission,
	Room: MissionRoomBuilder.Room,
	Members: { Player }, -- as it started
	Present: { [Player]: boolean },
	Allowed: { [number]: boolean }, -- UserIds that may hit its bosses
	Phase: string, -- "Starting" | "Wave" | "Between" | "Cleared" | "Failed"
	Wave: number,
	Bosses: { [string]: boolean }, -- this wave's bosses still standing
	WaveTotal: number,
	Hits: { [number]: number },
	HitsDirty: boolean,
	EndsAt: number, -- server time; 0 until the first wave
	Seq: number,
	Finished: boolean,
}

local MissionService = {}

local rooms: { MissionRoomBuilder.Room } = {}
local teams: { [string]: Team } = {}
local teamOf: { [Player]: Team } = {}
local runs: { [number]: Run } = {} -- room index -> run
local runOf: { [Player]: Run } = {}
local bossRun: { [string]: Run } = {}
local wantedByRoom: { [number]: { BossService.CustomSpawn } } = {}
local lastOpenedAt: { [Player]: number } = {}
local runCount = 0
local random = Random.new()

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function toast(player: Player, text: string): ()
	ToastRemote:FireClient(player, text)
end

local function teleport(player: Player, target: CFrame): ()
	local character = player.Character
	if character == nil or character.Parent == nil then
		return
	end
	MovementGuardService.noteTeleport(player)
	character:PivotTo(target)
end

local function lobby(): CFrame
	local position = ArenaConfig.SpawnPosition + Vector3.new(0, 3, 0)
	return CFrame.lookAt(position, position + Vector3.new(0, 0, 1))
end

local function inPickleball(player: Player): boolean
	local id = player:GetAttribute(Attributes.RecMatch)
	return typeof(id) == "string" and id ~= ""
end

local function isBusy(player: Player): boolean
	return teamOf[player] ~= nil or runOf[player] ~= nil or inPickleball(player)
end

local function freeRoom(): MissionRoomBuilder.Room?
	for _, room in rooms do
		if runs[room.Index] == nil then
			return room
		end
	end
	return nil
end

-- Teams ------------------------------------------------------------------------------

local function seat(player: Player): { [string]: any }
	return { UserId = player.UserId, Name = player.DisplayName }
end

local function teamList(): { [string]: any }
	local list = {}
	for _, team in teams do
		local members = {}
		for _, member in team.Members do
			table.insert(members, seat(member))
		end
		table.insert(list, {
			Id = team.Id,
			MissionId = team.Mission.Id,
			LeaderUserId = team.Leader.UserId,
			LeaderName = team.Leader.DisplayName,
			Members = members,
			ExpiresAt = team.ExpiresAt,
		})
	end
	local free = 0
	for _, room in rooms do
		if runs[room.Index] == nil then
			free += 1
		end
	end
	return { Teams = list, FreeRooms = free }
end

local function broadcastTeams(): ()
	MissionRemotes.Teams:FireAllClients(teamList())
end

local function closeTeam(team: Team): ()
	teams[team.Id] = nil
	for _, member in team.Members do
		if teamOf[member] == team then
			teamOf[member] = nil
		end
	end
	broadcastTeams()
end

local startRun: (team: Team) -> ()

local function onOpen(player: Player, rawMissionId: unknown): ()
	local missionId = Validate.id(rawMissionId, RemoteLimits.MaxIdLength)
	local mission = if missionId then MissionConfig.ById[missionId] else nil
	if mission == nil then
		return RemoteController.reject(player, "Mission.Open", "unknown mission")
	end
	if PlayerDataService.get(player) == nil then
		return
	end
	if isBusy(player) then
		return toast(player, "You're already in a team, a mission or a pickleball match.")
	end
	local last = lastOpenedAt[player]
	if last and now() - last < MissionConfig.LobbyCooldown then
		return toast(player, "Wait a moment before opening another team.")
	end
	lastOpenedAt[player] = now()
	local team: Team = {
		Id = HttpService:GenerateGUID(false),
		Mission = mission,
		Leader = player,
		Members = { player },
		ExpiresAt = now() + MissionConfig.LobbySeconds,
	}
	teams[team.Id] = team
	teamOf[player] = team
	broadcastTeams()
	task.delay(MissionConfig.LobbySeconds, function()
		if teams[team.Id] == team then
			for _, member in team.Members do
				toast(member, "Your mission team closed: not enough players joined in time.")
			end
			closeTeam(team)
		end
	end)
end

local function onJoin(player: Player, rawTeamId: unknown): ()
	local teamId = Validate.id(rawTeamId, 64)
	if teamId == nil then
		return RemoteController.reject(player, "Mission.Join", "bad team id")
	end
	local team = teams[teamId]
	if team == nil then
		return toast(player, "That team isn't open any more.")
	end
	if PlayerDataService.get(player) == nil then
		return
	end
	if isBusy(player) then
		return toast(player, "You're already in a team, a mission or a pickleball match.")
	end
	if #team.Members >= MissionConfig.TeamMax then
		return toast(player, "That team is full.")
	end
	-- Checked and taken without yielding: two players can't both get the last place.
	table.insert(team.Members, player)
	teamOf[player] = team
	for _, member in team.Members do
		if member ~= player then
			toast(member, player.DisplayName .. " joined your mission team.")
		end
	end
	if #team.Members >= MissionConfig.TeamMax then
		startRun(team)
	else
		broadcastTeams()
	end
end

local function leaveTeam(player: Player): ()
	local team = teamOf[player]
	if team == nil then
		return
	end
	teamOf[player] = nil
	local index = table.find(team.Members, player)
	if index then
		table.remove(team.Members, index)
	end
	if #team.Members == 0 then
		closeTeam(team)
		return
	end
	if team.Leader == player then
		team.Leader = team.Members[1]
		toast(team.Leader, "You lead the mission team now.")
	end
	broadcastTeams()
end

local function onBegin(player: Player): ()
	local team = teamOf[player]
	if team == nil then
		return
	end
	if team.Leader ~= player then
		return toast(player, "Only the team leader can start the mission.")
	end
	if #team.Members < MissionConfig.TeamMin then
		return toast(
			player,
			string.format("A mission needs at least %d players.", MissionConfig.TeamMin)
		)
	end
	startRun(team)
end

-- Runs ---------------------------------------------------------------------------------

local function memberIds(run: Run): { number }
	local ids: { number } = {}
	for _, member in run.Members do
		if run.Present[member] then
			table.insert(ids, member.UserId)
		end
	end
	return ids
end

local function sendState(run: Run): ()
	local left = 0
	for _ in run.Bosses do
		left += 1
	end
	local members = {}
	for _, member in run.Members do
		if run.Present[member] then
			table.insert(members, {
				UserId = member.UserId,
				Name = member.DisplayName,
				Hits = run.Hits[member.UserId] or 0,
			})
		end
	end
	local payload = {
		RunId = run.Id,
		MissionId = run.Mission.Id,
		Phase = run.Phase,
		Wave = run.Wave,
		Waves = #run.Mission.Waves,
		BossesLeft = left,
		BossesTotal = run.WaveTotal,
		EndsAt = run.EndsAt,
		Members = members,
	}
	run.HitsDirty = false
	for _, member in run.Members do
		if run.Present[member] then
			MissionRemotes.State:FireClient(member, payload)
		end
	end
end

local function syncBosses(): ()
	local wanted: { BossService.CustomSpawn } = {}
	for _, list in wantedByRoom do
		for _, entry in list do
			table.insert(wanted, entry)
		end
	end
	BossService.setMissionBosses(wanted)
end

local function clearBosses(run: Run): ()
	wantedByRoom[run.Room.Index] = nil
	for bossId, owner in bossRun do
		if owner == run then
			bossRun[bossId] = nil
		end
	end
	table.clear(run.Bosses)
	syncBosses()
end

local function spawnWave(run: Run, waveIndex: number): ()
	local wave = run.Mission.Waves[waveIndex]
	local size = CustomBossConfig.Size
	local teamSize = #memberIds(run)
	local entries: { BossService.CustomSpawn } = {}
	table.clear(run.Bosses)
	for index, offset in MissionRules.bossOffsets(wave.Count) do
		local id = MissionRules.bossId(run.Room.Index, run.Number, waveIndex, index)
		local definition = MissionRules.bossDefinition(id, wave, teamSize)
		if definition then
			local position = run.Room.Center + offset + Vector3.new(0, size.Y / 2, 0)
			table.insert(entries, {
				Definition = definition,
				Spawn = table.freeze({
					BossId = id,
					Position = position,
					Size = size,
					FloorY = run.Room.Center.Y,
				}),
				Signature = id,
				Respawns = false,
				Spent = false,
				Allowed = run.Allowed,
			})
			run.Bosses[id] = true
			bossRun[id] = run
		end
	end
	run.Wave = waveIndex
	run.WaveTotal = #entries
	run.Phase = "Wave"
	run.Seq += 1
	wantedByRoom[run.Room.Index] = entries
	syncBosses()
	run.Room.Board.Text = string.format(
		"%s %s · Wave %d of %d",
		run.Mission.Icon,
		run.Mission.Name,
		waveIndex,
		#run.Mission.Waves
	)
	sendState(run)
end

local function release(run: Run): ()
	if runs[run.Room.Index] == run then
		runs[run.Room.Index] = nil
	end
	clearBosses(run)
	run.Room.Board.Text = "TEAM MISSION"
	for _, member in run.Members do
		if runOf[member] == run then
			runOf[member] = nil
			member:SetAttribute(Attributes.InMission, "")
			if member.Parent then
				teleport(member, lobby())
			end
		end
	end
	broadcastTeams()
end

local function pay(player: Player): { [string]: any }
	local data = PlayerDataService.get(player)
	local paid: { [string]: any } = { Coins = 0, Xp = 0, Supply = "", Egg = false }
	if data == nil then
		return paid
	end
	SessionService.addCoins(player, REWARD.Coins)
	SessionService.addXp(player, REWARD.Xp)
	paid.Coins, paid.Xp = REWARD.Coins, REWARD.Xp
	if REWARD.Supply then
		local item = PickleballRules.rollSupply(PickleballConfig.Supplies.Winner, random)
		if FurnitureRules.grantSpecial(data.Furniture, item, 1) then
			local info = FurnitureConfig.ByKey[item]
			paid.Supply = if info then info.Name else item
		end
	end
	if random:NextNumber() < REWARD.EggChance then
		BagRules.add(data.Bag, REWARD.Egg, 1)
		paid.Egg = true
	end
	return paid
end

local function finish(run: Run, cleared: boolean, reason: string): ()
	if run.Finished then
		return
	end
	run.Finished = true
	run.Seq += 1
	run.Phase = if cleared then "Cleared" else "Failed"
	clearBosses(run)
	run.Room.Board.Text = if cleared then "🎉 MISSION CLEARED!" else "⏰ " .. reason
	sendState(run)
	local counted = MissionRules.counted(run.Hits, memberIds(run))
	local dayKey = QuestRules.dayKey(os.time())
	for _, member in run.Members do
		if run.Present[member] then
			local data = PlayerDataService.get(member)
			local payload: { [string]: any } = {
				MissionId = run.Mission.Id,
				Cleared = cleared,
				Reason = reason,
				Hits = run.Hits[member.UserId] or 0,
				Counted = counted[member.UserId] == true,
				Rewarded = false,
				Coins = 0,
				Xp = 0,
				Supply = "",
				Egg = false,
			}
			if cleared and data then
				data.Missions.Cleared += 1
				if counted[member.UserId] and MissionRules.canEarn(data.Missions, dayKey) then
					data.Missions.DayRewarded += 1
					payload.Rewarded = true
					local paid = pay(member)
					payload.Coins, payload.Xp, payload.Supply, payload.Egg =
						paid.Coins, paid.Xp, paid.Supply, paid.Egg
				end
				ProgressService.sync(member)
			end
			MissionRemotes.Result:FireClient(member, payload)
		end
	end
	task.delay(MissionConfig.EndPause, release, run)
end

local function leaveRun(player: Player, leavingGame: boolean): ()
	local run = runOf[player]
	if run == nil then
		return
	end
	runOf[player] = nil
	run.Present[player] = nil
	player:SetAttribute(Attributes.InMission, "")
	if not leavingGame then
		teleport(player, lobby())
	end
	if run.Finished then
		return
	end
	if #memberIds(run) == 0 then
		-- Nobody left: end it quietly and free the room.
		run.Finished = true
		run.Seq += 1
		release(run)
		return
	end
	for _, member in run.Members do
		if run.Present[member] then
			toast(member, player.DisplayName .. " left the mission.")
		end
	end
	sendState(run)
end

startRun = function(team: Team): ()
	local room = freeRoom()
	if room == nil then
		for _, member in team.Members do
			toast(member, "All mission rooms are busy. Try again in a moment.")
		end
		return
	end
	closeTeam(team)
	runCount += 1
	local run: Run = {
		Id = HttpService:GenerateGUID(false),
		Number = runCount,
		Mission = team.Mission,
		Room = room,
		Members = table.clone(team.Members),
		Present = {},
		Allowed = {},
		Phase = "Starting",
		Wave = 0,
		Bosses = {},
		WaveTotal = 0,
		Hits = {},
		HitsDirty = false,
		EndsAt = 0,
		Seq = 0,
		Finished = false,
	}
	runs[room.Index] = run
	for slot, member in run.Members do
		run.Present[member] = true
		run.Allowed[member.UserId] = true
		runOf[member] = run
		member:SetAttribute(Attributes.InMission, run.Id)
		teleport(member, MissionRoomBuilder.arrival(room.Center, slot))
	end
	room.Board.Text = string.format("%s %s · Get ready!", run.Mission.Icon, run.Mission.Name)
	run.EndsAt = now() + MissionConfig.StartPause + run.Mission.TimeLimit
	sendState(run)
	broadcastTeams()
	task.delay(MissionConfig.StartPause, function()
		if not run.Finished then
			spawnWave(run, 1)
		end
	end)
	task.delay(MissionConfig.StartPause + run.Mission.TimeLimit, function()
		if not run.Finished then
			finish(run, false, "Time's up!")
		end
	end)
end

local function onBossDefeated(bossId: string): ()
	local run = bossRun[bossId]
	if run == nil or run.Finished or not run.Bosses[bossId] then
		return
	end
	run.Bosses[bossId] = nil
	bossRun[bossId] = nil
	if next(run.Bosses) ~= nil then
		sendState(run)
		return
	end
	if run.Wave >= #run.Mission.Waves then
		finish(run, true, "Mission cleared!")
		return
	end
	run.Phase = "Between"
	run.Seq += 1
	sendState(run)
	local seq = run.Seq
	local nextWave = run.Wave + 1
	task.delay(MissionConfig.WavePause, function()
		if run.Seq == seq and not run.Finished then
			spawnWave(run, nextWave)
		end
	end)
end

local function onBossHit(live: BossService.LiveBoss, userId: number): ()
	if not live.State.Definition.Mission then
		return
	end
	local run = bossRun[live.State.Definition.Id]
	if run and not run.Finished then
		run.Hits[userId] = (run.Hits[userId] or 0) + 1
		run.HitsDirty = true
	end
end

-- A reset character goes back to its mission room.
local function onCharacterAdded(player: Player): ()
	task.defer(function()
		local run = runOf[player]
		if run and not run.Finished then
			local slot = table.find(run.Members, player) or 1
			teleport(player, MissionRoomBuilder.arrival(run.Room.Center, slot))
		end
	end)
end

-- Whether a player is in a team or a mission right now (pickleball and
-- office trips ask).
function MissionService.isBusy(player: Player): boolean
	return teamOf[player] ~= nil or runOf[player] ~= nil
end

function MissionService.init(): ()
	rooms = MissionRoomBuilder.build(Workspace)
	BossService.onMissionBossDefeated(onBossDefeated)
	BossService.onHit(onBossHit)

	RemoteController.bind(MissionRemotes.Open, {
		name = "Mission.Open",
		maxArgs = 1,
		rateLimit = RemoteLimits.Mission,
	}, onOpen)
	RemoteController.bind(MissionRemotes.Join, {
		name = "Mission.Join",
		maxArgs = 1,
		rateLimit = RemoteLimits.Mission,
	}, onJoin)
	RemoteController.bind(MissionRemotes.Leave, {
		name = "Mission.Leave",
		maxArgs = 0,
		rateLimit = RemoteLimits.Mission,
	}, function(player: Player)
		if runOf[player] then
			leaveRun(player, false)
		else
			leaveTeam(player)
		end
	end)
	RemoteController.bind(MissionRemotes.Begin, {
		name = "Mission.Begin",
		maxArgs = 0,
		rateLimit = RemoteLimits.Mission,
	}, onBegin)

	local function watch(player: Player): ()
		player:SetAttribute(Attributes.InMission, "")
		player.CharacterAdded:Connect(function()
			onCharacterAdded(player)
		end)
		MissionRemotes.Teams:FireClient(player, teamList())
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		leaveTeam(player)
		leaveRun(player, true)
		lastOpenedAt[player] = nil
	end)
end

function MissionService.start(): ()
	-- Hit counts go out at most every STATE_INTERVAL seconds, only when changed.
	while true do
		task.wait(STATE_INTERVAL)
		for _, run in runs do
			if run.HitsDirty and not run.Finished then
				sendState(run)
			end
		end
	end
end

return MissionService
