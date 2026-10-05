--!strict
-- Per-player, per-server-session state: equipped hammer and score. Score is
-- shown through the standard leaderstats folder. Nothing here is saved yet
-- (persistence arrives in Phase 3 via PlayerDataService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)

export type Session = {
	Player: Player,
	EquippedHammerId: string,
	ScoreValue: IntValue,
}

local SessionService = {}

local sessions: { [Player]: Session } = {}

local function createSession(player: Player): ()
	if sessions[player] then
		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local scoreValue = Instance.new("IntValue")
	scoreValue.Name = "Score"
	scoreValue.Value = GameConfig.StartingScore
	scoreValue.Parent = leaderstats

	leaderstats.Parent = player

	sessions[player] = {
		Player = player,
		EquippedHammerId = GameConfig.DefaultHammerId,
		ScoreValue = scoreValue,
	}
end

function SessionService.get(player: Player): Session?
	return sessions[player]
end

function SessionService.addScore(player: Player, amount: number): ()
	local session = sessions[player]
	if session == nil or amount <= 0 then
		return
	end
	session.ScoreValue.Value += amount
end

function SessionService.init(): ()
	Players.RespawnTime = GameConfig.RespawnTime
	Players.PlayerAdded:Connect(createSession)
	Players.PlayerRemoving:Connect(function(player: Player)
		sessions[player] = nil
	end)
end

function SessionService.start(): ()
	-- Players who joined before init connected PlayerAdded (common in Studio).
	for _, player in Players:GetPlayers() do
		createSession(player)
	end
end

return SessionService
