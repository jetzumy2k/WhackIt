--!strict
--[[
	Places the friendly lounge NPCs (Lib/NpcBuilder, Config/NpcConfig) when the
	server starts. They're static decoration: the server never moves them and
	runs nothing per frame; each client animates them and shows their speech
	bubbles (NpcController). They aren't in Workspace.Bosses and have no
	Humanoid, so combat, stress, XP, coins and the leaderboard never see them.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local NpcBuilder = require(ServerScriptService.Lib.NpcBuilder)

local NpcService = {}

function NpcService.init(): ()
	NpcBuilder.build(Workspace)
end

return NpcService
