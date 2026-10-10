--!strict
--[[
	The Pet Arena (docs/PET_ARENA.md, docs/REMOTE_CONTRACTS.md "PetArena").
	Turn-based cartoon pet battles, run entirely on the server
	(Shared/PetArenaRules with the server's own Random).

	  * PetArena.Start(trainerIndex, petId): a battle against a CPU trainer
	    (beat each to unlock the next). The player's pet must be theirs; its
	    stats come from its saved rarity and buffs.
	  * PetArena.Challenge(userId, petId) / PetArena.Answer(fromUserId, accept,
	    petId): a battle against another player in this server. A challenge
	    waits ChallengeSeconds.
	  * PetArena.Move(move): Boop, Charge or Guard for this round. Against the
	    CPU the round plays at once; between players it plays when both chose
	    or after TurnSeconds (a pet whose trainer didn't choose Boops).
	  * PetArena.Forfeit(): gives up (leaving the game does too).
	  * PetArena.State (server -> client): the battle, each round, incoming
	    challenges; PetArena.Result: the end and its reward.
	Rewards (PetArenaRules.cpuWin / playerResult): coins and XP, capped per
	day; the first win of the day against the last trainer also gives an
	office supply.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ActivityService = require(script.Parent.ActivityService)
local Attributes = require(ReplicatedStorage.Shared.Attributes)
local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)
local FurnitureRules = require(ReplicatedStorage.Shared.FurnitureRules)
local PetArenaConfig = require(ReplicatedStorage.Config.PetArenaConfig)
local PetArenaRules = require(ReplicatedStorage.Shared.PetArenaRules)
local PetRules = require(ReplicatedStorage.Shared.PetRules)
local PickleballRules = require(ReplicatedStorage.Shared.PickleballRules)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)
local QuestRules = require(ReplicatedStorage.Shared.QuestRules)
local RemoteController = require(ServerScriptService.Controllers.RemoteController)
local RemoteLimits = require(ServerScriptService.Config.RemoteLimits)
local SessionService = require(script.Parent.SessionService)
local Validate = require(ReplicatedStorage.Shared.Validate)

local Remotes = ReplicatedStorage.Remotes.PetArena
local ToastRemote = ReplicatedStorage.Remotes.Notify.Toast

type Side = PetArenaRules.Side
type Run = {
	Id: string,
	Kind: string, -- "Cpu" | "Player"
	Battle: PetArenaRules.Battle,
	Sides: { [Side]: Player? }, -- B is nil against the CPU
	Trainer: number?, -- CPU battles: the trainer's index
	Moves: { [Side]: PetArenaRules.Move? },
	Deadline: number, -- os.clock(), player battles
}
type Challenge = { From: Player, PetId: string, Expires: number }

local PetArenaService = {}

local MAX_USER_ID = 2 ^ 53
local TICK = 0.5

local random = Random.new()
local runs: { [string]: Run } = {}
local sideOf: { [Player]: { Run: Run, Side: Side } } = {}
-- Pending challenges, by the challenged player.
local challenges: { [Player]: Challenge } = {}
local nextId = 0

local function toast(player: Player, text: string): ()
	ToastRemote:FireClient(player, text)
end

local function dayKey(): string
	return QuestRules.dayKey(os.time())
end

local function busy(player: Player): string?
	if sideOf[player] then
		return "You're already in a pet battle."
	end
	local match = player:GetAttribute(Attributes.RecMatch)
	if typeof(match) == "string" and match ~= "" then
		return "Finish your pickleball match first."
	end
	local mission = player:GetAttribute(Attributes.InMission)
	if typeof(mission) == "string" and mission ~= "" then
		return "Finish your team mission first."
	end
	return nil
end

-- The player's own pet, or nil (and the reason).
local function ownPet(player: Player, rawPetId: unknown): (PetRules.Pet?, string?)
	if typeof(rawPetId) ~= "string" or #rawPetId > 32 or not PetRules.isPetId(rawPetId) then
		return nil, "bad pet id"
	end
	local data = PlayerDataService.get(player)
	local pet = if data then data.Pets[rawPetId] else nil
	if pet == nil then
		return nil, "not your pet"
	end
	return pet, nil
end

-- Payloads ----------------------------------------------------------------------------

local function fighterView(fighter: PetArenaRules.Fighter): { [string]: any }
	return {
		Name = fighter.Name,
		Species = fighter.Species,
		Rarity = fighter.Rarity,
		Pep = fighter.Pep,
		MaxPep = fighter.Stats.MaxPep,
		Power = math.floor(fighter.Stats.Power + 0.5),
		Speed = fighter.Stats.Speed,
		Crit = math.floor(fighter.Stats.Crit * 100 + 0.5),
		Charged = fighter.Charged,
	}
end

local function view(
	run: Run,
	side: Side,
	kind: string,
	events: { PetArenaRules.Event }?
): { [string]: any }
	local battle = run.Battle
	return {
		Kind = kind,
		BattleId = run.Id,
		You = side,
		Vs = run.Kind,
		Round = battle.Round,
		A = fighterView(battle.A),
		B = fighterView(battle.B),
		Events = events or {},
		Waiting = run.Kind == "Player" and run.Moves[side] ~= nil,
		TurnLeft = if run.Kind == "Player" then math.max(0, run.Deadline - os.clock()) else 0,
	}
end

local function sendAll(run: Run, kind: string, events: { PetArenaRules.Event }?): ()
	for _, side in { "A", "B" } :: { Side } do
		local player = run.Sides[side]
		if player and player.Parent == Players then
			Remotes.State:FireClient(player, view(run, side, kind, events))
		end
	end
end

-- Rewards and the end ---------------------------------------------------------------

local function pay(player: Player, reward: PetArenaRules.Reward?): { [string]: any }
	local payload = { Coins = 0, Xp = 0, Supply = "", Rewarded = reward ~= nil }
	if reward == nil then
		return payload
	end
	SessionService.addCoins(player, reward.Coins)
	SessionService.addXp(player, reward.Xp)
	payload.Coins, payload.Xp = reward.Coins, reward.Xp
	if reward.Supply then
		local data = PlayerDataService.get(player)
		local item = PickleballRules.rollSupply(PetArenaConfig.TopTrainerSupply, random)
		if data and FurnitureRules.grantSpecial(data.Furniture, item, 1) then
			local info = FurnitureConfig.ByKey[item]
			payload.Supply = if info then info.Name else item
		end
	end
	return payload
end

local function finish(run: Run): ()
	if runs[run.Id] == nil then
		return
	end
	runs[run.Id] = nil
	local winner = run.Battle.Winner
	for _, side in { "A", "B" } :: { Side } do
		local player = run.Sides[side]
		if player == nil then
			continue
		end
		sideOf[player] = nil
		if player.Parent ~= Players then
			continue
		end
		local data = PlayerDataService.get(player)
		local won = winner == side
		local reward: PetArenaRules.Reward? = nil
		if data then
			if run.Kind == "Cpu" and won and run.Trainer then
				reward = PetArenaRules.cpuWin(data.PetArena, run.Trainer, dayKey())
			elseif run.Kind == "Player" and winner ~= "Draw" then
				local opponent = run.Sides[if side == "A" then "B" else "A"]
				if opponent then
					reward =
						PetArenaRules.playerResult(data.PetArena, opponent.UserId, won, dayKey())
				end
			end
		end
		local paid = pay(player, reward)
		ProgressService.sync(player)
		if won then
			ActivityService.record(player, "PetBattleWin", 1)
		end
		Remotes.Result:FireClient(player, {
			BattleId = run.Id,
			Outcome = if winner == "Draw" then "Draw" elseif won then "Won" else "Lost",
			Vs = run.Kind,
			Trainer = run.Trainer,
			Coins = paid.Coins,
			Xp = paid.Xp,
			Supply = paid.Supply,
			Rewarded = paid.Rewarded,
			Cleared = if data then data.PetArena.Cleared else 0,
		})
	end
end

local function playRound(run: Run): ()
	local moveA: PetArenaRules.Move = run.Moves.A or "Boop"
	local moveB: PetArenaRules.Move = run.Moves.B or "Boop"
	run.Moves = {}
	local events = PetArenaRules.resolve(run.Battle, moveA, moveB, random)
	run.Deadline = os.clock() + PetArenaConfig.TurnSeconds
	sendAll(run, "Round", events)
	if run.Battle.Winner ~= "" then
		finish(run)
	end
end

local function begin(
	kind: "Cpu" | "Player",
	a: Player,
	b: Player?,
	battle: PetArenaRules.Battle,
	trainer: number?
): Run
	nextId += 1
	local run: Run = {
		Id = "arena-" .. nextId,
		Kind = kind,
		Battle = battle,
		Sides = { A = a, B = b },
		Trainer = trainer,
		Moves = {},
		Deadline = os.clock() + PetArenaConfig.TurnSeconds,
	}
	runs[run.Id] = run
	sideOf[a] = { Run = run, Side = "A" }
	if b then
		sideOf[b] = { Run = run, Side = "B" }
	end
	sendAll(run, "Battle")
	return run
end

local function petFighter(player: Player, pet: PetRules.Pet): PetArenaRules.Fighter
	return PetArenaRules.fighter(player.DisplayName, pet.Species, pet.Rarity, pet.Buffs)
end

-- Remote handlers -------------------------------------------------------------------

local function onStart(player: Player, rawTrainer: unknown, rawPetId: unknown): ()
	local index = Validate.integer(rawTrainer, 1, #PetArenaConfig.Trainers)
	if index == nil then
		return RemoteController.reject(player, "PetArena.Start", "bad trainer")
	end
	local pet, why = ownPet(player, rawPetId)
	if pet == nil then
		return RemoteController.reject(player, "PetArena.Start", why or "bad pet")
	end
	local reason = busy(player)
	if reason then
		return toast(player, reason)
	end
	local data = PlayerDataService.get(player)
	if data == nil then
		return
	end
	if not PetArenaRules.canFight(data.PetArena, index) then
		return toast(player, "Beat the trainer before this one first.")
	end
	local trainer = PetArenaConfig.Trainers[index]
	local battle =
		PetArenaRules.newBattle(petFighter(player, pet), PetArenaRules.trainerFighter(trainer))
	begin("Cpu", player, nil, battle, index)
end

local function onMove(player: Player, rawMove: unknown): ()
	if not PetArenaRules.isMove(rawMove) then
		return RemoteController.reject(player, "PetArena.Move", "unknown move")
	end
	local entry = sideOf[player]
	if entry == nil then
		return
	end
	local run = entry.Run
	if run.Moves[entry.Side] then
		return -- already chose this round
	end
	run.Moves[entry.Side] = rawMove :: PetArenaRules.Move
	if run.Kind == "Cpu" then
		local trainer = PetArenaConfig.Trainers[run.Trainer or 1]
		run.Moves.B = PetArenaRules.cpuMove(run.Battle, "B", trainer.Style, random)
		playRound(run)
	elseif run.Moves.A and run.Moves.B then
		playRound(run)
	else
		sendAll(run, "Waiting")
	end
end

local function forfeit(player: Player): ()
	local entry = sideOf[player]
	if entry == nil then
		return
	end
	local run = entry.Run
	run.Battle.Winner = if entry.Side == "A" then "B" else "A"
	finish(run)
end

local function onChallenge(player: Player, rawUserId: unknown, rawPetId: unknown): ()
	local userId = Validate.integer(rawUserId, -MAX_USER_ID, MAX_USER_ID)
	if userId == nil or userId == 0 then
		return RemoteController.reject(player, "PetArena.Challenge", "bad userId")
	end
	local pet, why = ownPet(player, rawPetId)
	if pet == nil then
		return RemoteController.reject(player, "PetArena.Challenge", why or "bad pet")
	end
	local target = Players:GetPlayerByUserId(userId)
	if target == nil or target == player then
		return toast(player, "That player isn't here.")
	end
	local reason = busy(player)
		or (if busy(target) then target.DisplayName .. " is busy right now." else nil)
	if reason then
		return toast(player, reason)
	end
	local pending = challenges[target]
	if pending and pending.Expires > os.clock() then
		return toast(player, target.DisplayName .. " already has a challenge waiting.")
	end
	challenges[target] = {
		From = player,
		PetId = rawPetId :: string,
		Expires = os.clock() + PetArenaConfig.ChallengeSeconds,
	}
	Remotes.State:FireClient(target, {
		Kind = "Challenge",
		FromUserId = player.UserId,
		FromName = player.DisplayName,
		Species = pet.Species,
		Rarity = pet.Rarity,
		Seconds = PetArenaConfig.ChallengeSeconds,
	})
	toast(player, "🐾 Challenge sent to " .. target.DisplayName .. ".")
end

local function onAnswer(
	player: Player,
	rawUserId: unknown,
	rawAccept: unknown,
	rawPetId: unknown
): ()
	local userId = Validate.integer(rawUserId, -MAX_USER_ID, MAX_USER_ID)
	if userId == nil or typeof(rawAccept) ~= "boolean" then
		return RemoteController.reject(player, "PetArena.Answer", "bad answer")
	end
	local pending = challenges[player]
	if pending == nil or pending.From.UserId ~= userId then
		return toast(player, "That challenge is gone.")
	end
	challenges[player] = nil
	local challenger = pending.From
	if not rawAccept then
		if challenger.Parent == Players then
			toast(challenger, player.DisplayName .. " said no to the pet battle.")
		end
		return
	end
	if pending.Expires < os.clock() or challenger.Parent ~= Players then
		return toast(player, "That challenge ran out.")
	end
	local myPet, why = ownPet(player, rawPetId)
	if myPet == nil then
		return RemoteController.reject(player, "PetArena.Answer", why or "bad pet")
	end
	local theirPet = ownPet(challenger, pending.PetId)
	local reason = busy(player) or busy(challenger)
	if theirPet == nil or reason then
		return toast(player, reason or "That challenge is gone.")
	end
	local battle =
		PetArenaRules.newBattle(petFighter(challenger, theirPet), petFighter(player, myPet))
	begin("Player", challenger, player, battle, nil)
end

local function tick(): ()
	local now = os.clock()
	for _, run in runs do
		if run.Kind == "Player" and now >= run.Deadline then
			playRound(run) -- whoever didn't choose Boops
		end
	end
	for target, pending in challenges do
		if pending.Expires < now then
			challenges[target] = nil
		end
	end
end

function PetArenaService.init(): ()
	local function bind(
		remote: Instance,
		name: string,
		maxArgs: number,
		handler: RemoteController.Handler
	): ()
		assert(remote:IsA("RemoteEvent"), name .. " must be a RemoteEvent")
		RemoteController.bind(
			remote,
			{ name = name, maxArgs = maxArgs, rateLimit = RemoteLimits.PetArena },
			handler
		)
	end
	bind(Remotes.Start, "PetArena.Start", 2, onStart :: RemoteController.Handler)
	bind(Remotes.Move, "PetArena.Move", 1, onMove :: RemoteController.Handler)
	bind(Remotes.Forfeit, "PetArena.Forfeit", 0, forfeit :: RemoteController.Handler)
	bind(Remotes.Challenge, "PetArena.Challenge", 2, onChallenge :: RemoteController.Handler)
	bind(Remotes.Answer, "PetArena.Answer", 3, onAnswer :: RemoteController.Handler)

	Players.PlayerRemoving:Connect(function(player: Player)
		challenges[player] = nil
		for target, pending in challenges do
			if pending.From == player then
				challenges[target] = nil
			end
		end
		forfeit(player)
	end)
end

function PetArenaService.start(): ()
	while true do
		task.wait(TICK)
		tick()
	end
end

return PetArenaService
