--!strict
--[[
	The Executive (3rd) Floor and its elevator (ArenaConfig.Executive).

	* Access = the CEO boss is unlocked for the player (every other boss
	  defeated at least once, plus the Player Level; Shared/ProgressionRules).
	* "Ride up" (ProximityPrompt on the 2nd-floor elevator door): the server
	  checks access, moves the player to the Executive Floor and spikes their
	  stress to 100 %. Without access they get a toast saying what's missing.
	* "Ride down" (3rd-floor door): always allowed.
	* Guard: anyone found on the Executive Floor without access (e.g. by
	  cheating past the elevator) is sent back down to the 2nd floor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local LevelRules = require(ReplicatedStorage.Shared.LevelRules)
local MovementGuardService = require(script.Parent.MovementGuardService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressionRules = require(ReplicatedStorage.Shared.ProgressionRules)
local StressService = require(script.Parent.StressService)

local ToastRemote = ReplicatedStorage.Remotes.Notify.Toast

local GUARD_TICK_SECONDS = 1
local PROMPT_DISTANCE = 10

local ExecutiveService = {}

local executive = ArenaConfig.Executive

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function hasAccess(player: Player): boolean
	local data = PlayerDataService.get(player)
	if data == nil then
		return false
	end
	return ProgressionRules.isBossUnlocked(
		executive.CeoBossId,
		data.BossDefeats,
		LevelRules.levelFor(data.Score)
	)
end

-- Why the elevator won't go up, in words.
local function denyReason(player: Player): string
	local data = PlayerDataService.get(player)
	if data == nil then
		return "Still loading your progress..."
	end
	local status = ProgressionRules.unlockStatus(
		executive.CeoBossId,
		data.BossDefeats,
		LevelRules.levelFor(data.Score)
	)
	if status.LevelNeeded > 0 then
		return string.format("Executive Floor: reach Level %d first.", status.LevelNeeded)
	end
	return string.format(
		"Executive Floor: defeat every boss once first (%d to go).",
		status.DefeatsNeeded
	)
end

local function moveTo(player: Player, position: Vector3): ()
	local character = player.Character
	if character == nil then
		return
	end
	MovementGuardService.noteTeleport(player)
	-- Face into the floor (+X, away from the elevator wall).
	character:PivotTo(CFrame.lookAt(position, position + Vector3.new(1, 0, 0)))
end

local function rideUp(player: Player): ()
	if not hasAccess(player) then
		ToastRemote:FireClient(player, denyReason(player))
		return
	end
	moveTo(player, executive.ArriveUp)
	StressService.spike(player)
	ToastRemote:FireClient(player, "Welcome to the Executive Floor. Stress level: MAXIMUM.")
end

local function rideDown(player: Player): ()
	moveTo(player, executive.ArriveDown)
end

local function isOnExecutiveFloor(position: Vector3): boolean
	return position.Y >= executive.FloorY - 0.5
		and position.Y <= executive.CeilingY
		and math.abs(position.X) <= ArenaConfig.BuildingHalfWidth
		and position.Z >= executive.NorthZ
		and position.Z <= executive.SouthZ
end

local function guardTick(): ()
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and isOnExecutiveFloor(root.Position) and not hasAccess(player) then
			rideDown(player)
			ToastRemote:FireClient(player, denyReason(player))
		end
	end
end

local function addPrompt(doorName: string, actionText: string, onTriggered: (Player) -> ()): ()
	local office = Workspace:WaitForChild("Office")
	local door = office:FindFirstChild(doorName, true)
	if door == nil or not door:IsA("BasePart") then
		warn("[ExecutiveService] missing elevator door " .. doorName)
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "Executive Elevator"
	prompt.ActionText = actionText
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = door
	prompt.Triggered:Connect(onTriggered)
end

function ExecutiveService.start(): ()
	assert(
		BossConfig.ById[executive.CeoBossId],
		"ArenaConfig.Executive.CeoBossId must exist in BossConfig"
	)
	addPrompt("ElevatorUpDoor", "Ride up", rideUp)
	addPrompt("ElevatorDownDoor", "Ride down", rideDown)
	while true do
		task.wait(GUARD_TICK_SECONDS)
		guardTick()
	end
end

return ExecutiveService
