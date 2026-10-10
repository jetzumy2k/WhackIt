--!strict
--[[
	Studio-only performance probe, client half (docs/UPDATE_TEST_PLAN.md B4,
	polish round 2026-10-10). Does nothing in a live game.

	Every INTERVAL seconds each test client prints one line: frame rate,
	average and worst frame time, memory, network in/out, instances it can
	see in Workspace and where the player stands (so the line can be matched
	to the lobby, a boss fight, the campus or an office).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

local PerfProbeController = {}

local INTERVAL = 15

function PerfProbeController.start(): ()
	if not RunService:IsStudio() then
		return
	end
	local frames, worst, started = 0, 0, os.clock()
	RunService.RenderStepped:Connect(function(dt: number)
		frames += 1
		worst = math.max(worst, dt)
	end)
	while true do
		task.wait(INTERVAL)
		local elapsed = os.clock() - started
		local character = Players.LocalPlayer.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local at = if root and root:IsA("BasePart") then root.Position else Vector3.zero
		print(
			string.format(
				"[Perf] client fps=%.1f avg=%.1fms worst=%.0fms mem=%.0fMB recv=%.1fkB/s send=%.1fkB/s instances=%d at=(%d,%d,%d)",
				frames / elapsed,
				elapsed / math.max(frames, 1) * 1000,
				worst * 1000,
				Stats:GetTotalMemoryUsageMb(),
				Stats.DataReceiveKbps,
				Stats.DataSendKbps,
				#Workspace:GetDescendants(),
				math.floor(at.X),
				math.floor(at.Y),
				math.floor(at.Z)
			)
		)
		frames, worst, started = 0, 0, os.clock()
	end
end

return PerfProbeController
