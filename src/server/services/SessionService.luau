--!strict
-- Per-player gameplay session: score, coins and the equipped hammer. Score and
-- coins are shown through the standard leaderstats folder. A session exists
-- only once the player's saved data has loaded (PlayerDataService), so nothing
-- can be earned, spent or equipped before then. Saved values live in the
-- player's data; the IntValues only display them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local Attributes = require(ReplicatedStorage.Shared.Attributes)
local LevelRules = require(ReplicatedStorage.Shared.LevelRules)
local PlayerDataService = require(script.Parent.PlayerDataService)

export type Session = {
	Player: Player,
	ScoreValue: IntValue,
	CoinsValue: IntValue,
}

local SessionService = {}

local sessions: { [Player]: Session } = {}

local function statValue(name: string, value: number, parent: Instance): IntValue
	local stat = Instance.new("IntValue")
	stat.Name = name
	stat.Value = value
	stat.Parent = parent
	return stat
end

local function createSession(player: Player, data: PlayerDataService.PlayerData): ()
	if sessions[player] or player.Parent ~= Players then
		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local scoreValue = statValue("Score", data.Score, leaderstats)
	local coinsValue = statValue("Coins", data.Coins, leaderstats)
	leaderstats.Parent = player

	sessions[player] = {
		Player = player,
		ScoreValue = scoreValue,
		CoinsValue = coinsValue,
	}
	player:SetAttribute(Attributes.Level, LevelRules.levelFor(data.Xp))
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

-- Adds XP (which drives Player Level) and refreshes the Level attribute.
function SessionService.addXp(player: Player, amount: number): ()
	local data = PlayerDataService.get(player)
	if sessions[player] == nil or data == nil or amount <= 0 then
		return
	end
	data.Xp += math.floor(amount + 0.5)
	player:SetAttribute(Attributes.Level, LevelRules.levelFor(data.Xp))
end

-- Replaces XP outright (admin Set Level) and refreshes the Level attribute.
function SessionService.setXp(player: Player, xp: number): ()
	local data = PlayerDataService.get(player)
	if sessions[player] == nil or data == nil or xp < 0 or xp ~= xp then
		return
	end
	data.Xp = math.floor(xp)
	player:SetAttribute(Attributes.Level, LevelRules.levelFor(data.Xp))
end

function SessionService.addCoins(player: Player, amount: number): ()
	local session = sessions[player]
	local data = PlayerDataService.get(player)
	if session == nil or data == nil or amount <= 0 then
		return
	end
	data.Coins += amount
	session.CoinsValue.Value = data.Coins
end

-- Deducts coins only if the player has enough; never goes negative.
function SessionService.trySpendCoins(player: Player, amount: number): boolean
	local session = sessions[player]
	local data = PlayerDataService.get(player)
	if session == nil or data == nil or amount < 0 or data.Coins < amount then
		return false
	end
	data.Coins -= amount
	session.CoinsValue.Value = data.Coins
	return true
end

-- Callers must check ownership first (ShopService).
function SessionService.setEquippedHammer(player: Player, hammerId: string): ()
	local session = sessions[player]
	local data = PlayerDataService.get(player)
	if session == nil or data == nil then
		return
	end
	data.EquippedHammerId = hammerId
end

function SessionService.init(): ()
	Players.RespawnTime = GameConfig.RespawnTime
	PlayerDataService.onLoaded(createSession)
	Players.PlayerRemoving:Connect(function(player: Player)
		sessions[player] = nil
	end)
end

return SessionService
