--!strict
--[[
	Paper Toss Showdown (docs/PAPER_TOSS.md, docs/REMOTE_CONTRACTS.md
	"PaperToss"). One player against a CPU coworker; the server owns the
	game (Shared/PaperTossRules with the server's Random).

	  * PaperToss.Start(opponent): a new 5-round game (beat each opponent to
	    unlock the next). The rounds' bin distances and breezes are the
	    server's.
	  * PaperToss.Throw(aim, power): two numbers 0..1 from the meters. The
	    server judges it, throws for the CPU and moves to the next round; at
	    least MinThrowSeconds apart.
	  * PaperToss.Quit(): ends the game (no reward).
	  * PaperToss.State (server -> client): the game, each round's two
	    throws, and the end with its reward.
	The meters are drawn by the client, so a cheater could send a perfect
	throw; rewards are small and capped per day (DailyRewardedWins).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ActivityService = require(script.Parent.ActivityService)
local Attributes = require(ReplicatedStorage.Shared.Attributes)
local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)
local FurnitureRules = require(ReplicatedStorage.Shared.FurnitureRules)
local PaperTossConfig = require(ReplicatedStorage.Config.PaperTossConfig)
local PaperTossRules = require(ReplicatedStorage.Shared.PaperTossRules)
local PickleballRules = require(ReplicatedStorage.Shared.PickleballRules)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)
local QuestRules = require(ReplicatedStorage.Shared.QuestRules)
local RemoteController = require(ServerScriptService.Controllers.RemoteController)
local RemoteLimits = require(ServerScriptService.Config.RemoteLimits)
local SessionService = require(script.Parent.SessionService)
local Validate = require(ReplicatedStorage.Shared.Validate)

local Remotes = ReplicatedStorage.Remotes.PaperToss
local ToastRemote = ReplicatedStorage.Remotes.Notify.Toast

type Running = { Match: PaperTossRules.Game, LastThrow: number }

local PaperTossService = {}

local random = Random.new()
local running: { [Player]: Running } = {}

local function roundView(match: PaperTossRules.Game): { [string]: any }?
	local round = match.Rounds[match.Round]
	if round == nil then
		return nil
	end
	return { Number = match.Round, Distance = round.Distance, Wind = round.Wind }
end

local function busy(player: Player): string?
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

local function onStart(player: Player, rawOpponent: unknown): ()
	local index = Validate.integer(rawOpponent, 1, #PaperTossConfig.Opponents)
	if index == nil then
		return RemoteController.reject(player, "PaperToss.Start", "bad opponent")
	end
	local reason = busy(player)
	if reason then
		return ToastRemote:FireClient(player, reason)
	end
	local data = PlayerDataService.get(player)
	if data == nil then
		return
	end
	if not PaperTossRules.canPlay(data.PaperToss, index) then
		return ToastRemote:FireClient(player, "Beat the coworker before this one first.")
	end
	local match = PaperTossRules.newGame(index, random)
	running[player] = { Match = match, LastThrow = 0 }
	Remotes.State:FireClient(player, {
		Kind = "Start",
		Opponent = index,
		Rounds = #match.Rounds,
		Round = roundView(match),
		You = 0,
		Cpu = 0,
	})
end

local function onThrow(player: Player, rawAim: unknown, rawPower: unknown): ()
	if not PaperTossRules.isMeter(rawAim) or not PaperTossRules.isMeter(rawPower) then
		return RemoteController.reject(player, "PaperToss.Throw", "bad throw")
	end
	local current = running[player]
	if current == nil then
		return
	end
	local now = os.clock()
	if now - current.LastThrow < PaperTossConfig.MinThrowSeconds then
		return -- too quick: the paper is still flying
	end
	current.LastThrow = now
	local match = current.Match
	local played = match.Rounds[match.Round]
	local mine, theirs = PaperTossRules.play(match, rawAim :: number, rawPower :: number, random)
	if mine == nil or theirs == nil or played == nil then
		return
	end
	local over = PaperTossRules.isOver(match)
	local payload: { [string]: any } = {
		Kind = "Round",
		Played = { Distance = played.Distance, Wind = played.Wind },
		YouThrow = mine,
		CpuThrow = theirs,
		You = match.You,
		Cpu = match.Cpu,
		Round = roundView(match),
	}
	if over then
		running[player] = nil
		local data = PlayerDataService.get(player)
		local reward = if data
			then PaperTossRules.finish(data.PaperToss, match, QuestRules.dayKey(os.time()))
			else nil
		local supply = ""
		if reward then
			SessionService.addCoins(player, reward.Coins)
			SessionService.addXp(player, reward.Xp)
			if reward.Supply and data then
				local item = PickleballRules.rollSupply(PaperTossConfig.CeoSupply, random)
				if FurnitureRules.grantSpecial(data.Furniture, item, 1) then
					local info = FurnitureConfig.ByKey[item]
					supply = if info then info.Name else item
				end
			end
		end
		ProgressService.sync(player)
		local outcome = PaperTossRules.outcome(match)
		if outcome == "Won" then
			ActivityService.record(player, "PaperTossWin", 1)
		end
		payload.Outcome = outcome
		payload.Coins = if reward then reward.Coins else 0
		payload.Xp = if reward then reward.Xp else 0
		payload.Supply = supply
		payload.Rewarded = reward ~= nil
	end
	Remotes.State:FireClient(player, payload)
end

local function onQuit(player: Player): ()
	if running[player] then
		running[player] = nil
		Remotes.State:FireClient(player, { Kind = "Quit" })
	end
end

function PaperTossService.init(): ()
	local function bind(
		remote: Instance,
		name: string,
		maxArgs: number,
		handler: RemoteController.Handler
	): ()
		assert(remote:IsA("RemoteEvent"), name .. " must be a RemoteEvent")
		RemoteController.bind(
			remote,
			{ name = name, maxArgs = maxArgs, rateLimit = RemoteLimits.PaperToss },
			handler
		)
	end
	bind(Remotes.Start, "PaperToss.Start", 1, onStart :: RemoteController.Handler)
	bind(Remotes.Throw, "PaperToss.Throw", 2, onThrow :: RemoteController.Handler)
	bind(Remotes.Quit, "PaperToss.Quit", 0, onQuit :: RemoteController.Handler)
	Players.PlayerRemoving:Connect(function(player: Player)
		running[player] = nil
	end)
end

return PaperTossService
