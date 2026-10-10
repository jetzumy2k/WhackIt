--!strict
--[[
	Studio-only performance probe for the baseline (docs/UPDATE_TEST_PLAN.md
	B4/B5, polish round 2026-10-10). Does nothing in a live game.

	Every INTERVAL seconds the server prints one line to the Output (and so to
	Studio's log file): heartbeat rate and worst frame, memory, instances and
	parts in Workspace, players, network in/out and StreamingEnabled. The
	client half is Controllers/PerfProbeController.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

local PerfProbeService = {}

local INTERVAL = 15

local function countWorkspace(): (number, number)
	local instances, parts = 0, 0
	for _, descendant in Workspace:GetDescendants() do
		instances += 1
		if descendant:IsA("BasePart") then
			parts += 1
		end
	end
	return instances, parts
end

function PerfProbeService.start(): ()
	if not RunService:IsStudio() then
		return
	end
	local frames, worst, started = 0, 0, os.clock()
	RunService.Heartbeat:Connect(function(dt: number)
		frames += 1
		worst = math.max(worst, dt)
	end)
	while true do
		task.wait(INTERVAL)
		local elapsed = os.clock() - started
		local instances, parts = countWorkspace()
		print(
			string.format(
				"[Perf] server heartbeat=%.1f/s worst=%.0fms mem=%.0fMB instances=%d parts=%d players=%d recv=%.1fkB/s send=%.1fkB/s streaming=%s",
				frames / elapsed,
				worst * 1000,
				Stats:GetTotalMemoryUsageMb(),
				instances,
				parts,
				#Players:GetPlayers(),
				Stats.DataReceiveKbps,
				Stats.DataSendKbps,
				tostring(Workspace.StreamingEnabled)
			)
		)
		frames, worst, started = 0, 0, os.clock()
	end
end

return PerfProbeService
