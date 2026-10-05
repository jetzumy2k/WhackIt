--!strict
-- Per-player gameplay session: equipped hammer and score, shown through the
-- standard leaderstats folder. A session exists only once the player's saved
-- data has loaded (PlayerDataService), so nothing can be earned before then.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)

export type Session = {
	Player: Player,
	EquippedHammerId: string,
	ScoreValue: IntValue,
}

local SessionService = {}

local sessions: { [Player]: Session } = {}

local function createSession(player: Player, data: PlayerDataService.PlayerData): ()
	if sessions[player] or player.Parent ~= Players then
		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local scoreValue = Instance.new("IntValue")
	scoreValue.Name = "Score"
	scoreValue.Value = data.Score
	scoreValue.Parent = leaderstats

	leaderstats.Parent = player

	sessions[player] = {
		Player = player,
		EquippedHammerId = data.EquippedHammerId,
		ScoreValue = scoreValue,
	}
end

function SessionService.get(player: Player): Session?
	return sessions[player]
end

-- Adds to the saved lifetime score and the leaderstats display.
function SessionService.addScore(player: Player, amount: number): ()
	local session = sessions[player]
	local data = PlayerDataService.get(player)
	if session == nil or data == nil or amount <= 0 then
		return
	end
	data.Score += amount
	session.ScoreValue.Value = data.Score
end

function SessionService.init(): ()
	Players.RespawnTime = GameConfig.RespawnTime
	PlayerDataService.onLoaded(createSession)
	Players.PlayerRemoving:Connect(function(player: Player)
		sessions[player] = nil
	end)
end

return SessionService
