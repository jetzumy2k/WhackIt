--!strict
-- The only server Script. All server logic lives in ModuleScripts under
-- ServerScriptService.Services and .Controllers, booted via Lifecycle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Lifecycle = require(ReplicatedStorage.Shared.Lifecycle)

Lifecycle.boot({
	ServerScriptService.Services,
	ServerScriptService.Controllers,
})
