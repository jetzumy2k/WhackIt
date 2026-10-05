--!strict
-- The only client LocalScript. All client logic lives in ModuleScripts under
-- the sibling Controllers folder, booted via Lifecycle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lifecycle = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Lifecycle"))

Lifecycle.boot({
	script.Parent:WaitForChild("Controllers"),
})
