--!strict
--[[
	Single entry point for client->server RemoteEvents. Every bound remote gets,
	before its handler runs:
	  1. sender still in the game (OnServerEvent's player can't be spoofed, but it
	     may have left while the request was in flight);
	  2. argument count cap;
	  3. per-player token-bucket rate limit.
	Handlers receive raw `unknown` arguments and must validate them with
	Shared/Validate, calling RemoteController.reject on bad input. Handler errors
	are caught and logged so one bad request can't break the connection.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local RemoteLimits = require(ServerScriptService.Config.RemoteLimits)

export type Handler = (player: Player, ...unknown) -> ()

export type Options = {
	name: string,
	maxArgs: number,
	rateLimit: RateLimiter.Config,
}

local RemoteController = {}

-- Every limiter created here, so leaving players' buckets can be cleared.
local limiters: { RateLimiter.RateLimiter } = {}
local rejectLogLimiter = RateLimiter.new(RemoteLimits.RejectLog)
table.insert(limiters, rejectLogLimiter)

-- Logs a rejected request, throttled per player. Returns nothing so handlers can
-- `return RemoteController.reject(...)`.
function RemoteController.reject(player: Player, remoteName: string, reason: string): ()
	if rejectLogLimiter.allow(player.UserId) then
		warn(string.format("[Remote] rejected %s from %d: %s", remoteName, player.UserId, reason))
	end
end

-- Builds the guarded OnServerEvent callback. Exposed separately from bind() so
-- specs can exercise the guards without a live client.
function RemoteController.wrap(options: Options, handler: Handler): Handler
	local limiter = RateLimiter.new(options.rateLimit)
	table.insert(limiters, limiter)

	return function(player: Player, ...: unknown): ()
		if player.Parent ~= Players then
			return
		end
		if select("#", ...) > options.maxArgs then
			return RemoteController.reject(player, options.name, "too many arguments")
		end
		if not limiter.allow(player.UserId) then
			return RemoteController.reject(player, options.name, "rate limited")
		end

		local args = table.pack(...)
		local ok, err = pcall(function()
			handler(player, table.unpack(args, 1, args.n))
		end)
		if not ok then
			warn(
				string.format(
					"[Remote] %s handler error for %d: %s",
					options.name,
					player.UserId,
					tostring(err)
				)
			)
		end
	end
end

function RemoteController.bind(
	remote: RemoteEvent,
	options: Options,
	handler: Handler
): RBXScriptConnection
	return remote.OnServerEvent:Connect(RemoteController.wrap(options, handler))
end

function RemoteController.init(): ()
	Players.PlayerRemoving:Connect(function(player: Player)
		for _, limiter in limiters do
			limiter.remove(player.UserId)
		end
	end)
end

return RemoteController
