--!strict
--[[
	Loads, guards and saves each player's data through ProfileStore
	(docs/DATA_SCHEMA.md). ProfileStore provides session locking (one server
	owns a profile at a time, preventing duplication), periodic auto-save,
	retries and saving on shutdown.

	Safety rules:
	  * No data, no play: if a profile can't be loaded the player is kicked
	    with a friendly message; defaults are never played and saved over
	    real progress.
	  * Loaded data is migrated and validated (Lib/PlayerDataSchema) before use;
	    data from a newer schema is left untouched and the player is kicked.
	  * Other services read and change data only for players returned by get().
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataConfig = require(ServerScriptService.Config.DataConfig)
local PlayerDataSchema = require(ServerScriptService.Lib.PlayerDataSchema)

-- The parts of ProfileStore used here (its own types omit the Cancel param).
type Profile = {
	Data: PlayerDataSchema.RawData,
	AddUserId: (self: Profile, userId: number) -> (),
	EndSession: (self: Profile) -> (),
	OnSessionEnd: { Connect: (self: any, listener: () -> ()) -> any },
	OnAfterSave: { Connect: (self: any, listener: (lastSavedData: any) -> ()) -> any },
}
type Store = {
	StartSessionAsync: (self: Store, key: string, params: { Cancel: () -> boolean }) -> Profile?,
}
type ProfileStoreModule = {
	New: (storeName: string, template: PlayerDataSchema.PlayerData) -> Store,
}

local ProfileStore = (
	require(ServerScriptService.ServerPackages.ProfileStore) :: any
) :: ProfileStoreModule

export type PlayerData = PlayerDataSchema.PlayerData
export type LoadedCallback = (player: Player, data: PlayerData) -> ()

local PlayerDataService = {}

local store: Store = ProfileStore.New(DataConfig.StoreName, PlayerDataSchema.template())
local profiles: { [Player]: Profile } = {}
local loadedCallbacks: { LoadedCallback } = {}
local loading: { [Player]: boolean } = {}

local function keyFor(player: Player): string
	return DataConfig.KeyPrefix .. player.UserId
end

-- After prepare() succeeds the table has exactly the PlayerData shape.
local function asPlayerData(data: PlayerDataSchema.RawData): PlayerDataSchema.PlayerData
	return (data :: any) :: PlayerDataSchema.PlayerData
end

local function load(player: Player): ()
	if loading[player] or profiles[player] then
		return
	end
	loading[player] = true

	local profile = store:StartSessionAsync(keyFor(player), {
		-- Stop retrying once the player has left.
		Cancel = function(): boolean
			return player.Parent ~= Players
		end,
	})
	loading[player] = nil

	if profile == nil then
		if player.Parent == Players then
			warn(string.format("[PlayerData] load failed for %d", player.UserId))
			player:Kick(DataConfig.LoadFailedMessage)
		end
		return
	end

	-- Links the key to the user for Roblox data-deletion (right to erasure) requests.
	profile:AddUserId(player.UserId)

	local ok, reason = PlayerDataSchema.prepare(profile.Data)
	if not ok then
		warn(string.format("[PlayerData] refused data for %d: %s", player.UserId, tostring(reason)))
		profile:EndSession()
		player:Kick(DataConfig.NewerDataMessage)
		return
	end

	-- Another server took over this profile (e.g. the player joined elsewhere).
	profile.OnSessionEnd:Connect(function()
		if profiles[player] == profile then
			profiles[player] = nil
			player:Kick(DataConfig.SessionEndedMessage)
		end
	end)

	if player.Parent ~= Players then
		profile:EndSession() -- left while loading
		return
	end

	-- Lets the player see their progress is safe ("Progress saved" in the HUD).
	profile.OnAfterSave:Connect(function()
		if player.Parent == Players then
			ReplicatedStorage.Remotes.Profile.Saved:FireClient(player)
		end
	end)

	profiles[player] = profile
	local data = asPlayerData(profile.Data)
	for _, callback in loadedCallbacks do
		task.spawn(callback, player, data)
	end
end

-- The player's live data, or nil until it has loaded (and after they leave).
-- Changes to the returned table are saved automatically.
function PlayerDataService.get(player: Player): PlayerDataSchema.PlayerData?
	local profile = profiles[player]
	return if profile then asPlayerData(profile.Data) else nil
end

-- Runs `callback` for every player whose data loads, including players who
-- loaded before the callback was registered.
function PlayerDataService.onLoaded(callback: LoadedCallback): ()
	table.insert(loadedCallbacks, callback)
	for player, profile in profiles do
		task.spawn(callback, player, asPlayerData(profile.Data))
	end
end

function PlayerDataService.init(): ()
	Players.PlayerAdded:Connect(load)
	Players.PlayerRemoving:Connect(function(player: Player)
		local profile = profiles[player]
		profiles[player] = nil
		if profile then
			profile:EndSession() -- saves and releases the session lock
		end
	end)
end

function PlayerDataService.start(): ()
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
end

return PlayerDataService
