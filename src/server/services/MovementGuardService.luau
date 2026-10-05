--!strict
--[[
	Server-side movement sanity. Roblox lets each client simulate its own
	character, so a cheater could teleport next to a boss (or speed-hack) to
	pass the reach check. This samples every character's position and, after an
	impossibly fast horizontal move, makes CombatService ignore that player's
	hits for a few seconds (MovementLimits, server-only).

	Respawns are legitimate teleports, so each new character starts fresh.
	This catches teleports and large speed hacks, not small speed boosts below
	MaxHorizontalSpeed (documented in docs/REMOTE_CONTRACTS.md).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local MovementLimits = require(ServerScriptService.Config.MovementLimits)
local MovementRules = require(ServerScriptService.Lib.MovementRules)

local IS_STUDIO = RunService:IsStudio()

type Sample = {
	Character: Model,
	Position: Vector3,
	At: number,
}

local MovementGuardService = {}

local lastSample: { [Player]: Sample } = {}
local flaggedAt: { [Player]: number } = {}

local function rootPosition(character: Model): Vector3?
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function sample(): ()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local position = if character then rootPosition(character) else nil
		if character == nil or position == nil then
			lastSample[player] = nil
			continue
		end

		local previous = lastSample[player]
		-- Compare only within the same character: a respawn is a fair teleport.
		if previous and previous.Character == character then
			local elapsed = now - previous.At
			if
				MovementRules.isTooFast(
					previous.Position,
					position,
					elapsed,
					MovementLimits.MaxHorizontalSpeed
				)
			then
				flaggedAt[player] = now
				if IS_STUDIO then
					print(
						string.format(
							"[MovementGuard] %s moved %.0f studs/s; hits ignored for %d s",
							player.Name,
							MovementRules.horizontalSpeed(previous.Position, position, elapsed),
							MovementLimits.SuspectSeconds
						)
					)
				end
			end
		end
		lastSample[player] = { Character = character, Position = position, At = now }
	end
end

-- True while the player's hits should be ignored after an implausible move.
function MovementGuardService.isSuspect(player: Player): boolean
	return MovementRules.isSuspect(flaggedAt[player], os.clock(), MovementLimits.SuspectSeconds)
end

function MovementGuardService.init(): ()
	Players.PlayerRemoving:Connect(function(player: Player)
		lastSample[player] = nil
		flaggedAt[player] = nil
	end)
end

function MovementGuardService.start(): ()
	while true do
		task.wait(MovementLimits.SampleInterval)
		sample()
	end
end

return MovementGuardService
