--!strict
--[[
	Places the hammer vending machine in the lobby (Lib/StoreMachineBuilder)
	when the server starts, so it's there after every restart. It's only an
	entry point: the client opens the existing Hammers shop when its prompt is
	used (StoreMachineController), and every purchase still goes through
	Shop.BuyHammer and ShopService's server-side checks. The server doesn't act
	on the prompt at all, so there's nothing here a client could abuse.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local StoreMachineBuilder = require(ServerScriptService.Lib.StoreMachineBuilder)

local StoreMachineService = {}

function StoreMachineService.init(): ()
	StoreMachineBuilder.build(Workspace)
end

return StoreMachineService
