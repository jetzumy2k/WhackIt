--!strict
--[[
	The tower elevator (docs/TOWER.md, Phase 3a; decisions D14-D16).

	* Doors: one per floor in the shaft at the corridor's west end
	  (ArenaConfig.Tower, built by Lib/OfficeBuilder). Each has an "Elevator"
	  ProximityPrompt (TowerPrompt); the client opens its floor panel.
	* Rides (Tower.Ride(floorId)): the server checks the floor exists, the
	  player stands at an elevator door, isn't already on that floor, and may
	  go there (Shared/TowerRules.status from saved data); then moves them
	  (MovementGuardService.noteTeleport first). Arriving on the Executive
	  Floor spikes stress to 100 % as before. A refused ride gets a toast
	  saying what's missing.
	* Guard: anyone found on the 3rd floor (Department Heads) without access (e.g. by cheating
	  past the elevator) is sent down to the Senior floor. The Executive
	  Floor keeps its own guard (ExecutiveService).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local BuffService = require(script.Parent.BuffService)
local LevelRules = require(ReplicatedStorage.Shared.LevelRules)
local MovementGuardService = require(script.Parent.MovementGuardService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteController = require(ServerScriptService.Controllers.RemoteController)
local RemoteLimits = require(ServerScriptService.Config.RemoteLimits)
local StressService = require(script.Parent.StressService)
local TowerRules = require(ReplicatedStorage.Shared.TowerRules)
local Validate = require(ReplicatedStorage.Shared.Validate)

local RideRemote = ReplicatedStorage.Remotes.Tower.Ride
local ToastRemote = ReplicatedStorage.Remotes.Notify.Toast

local TowerService = {}

TowerService.PROMPT_NAME = "TowerPrompt"
local PROMPT_DISTANCE = 10
-- A ride must be asked for this close to a door (the prompt's reach plus lag).
local DOOR_REACH = PROMPT_DISTANCE + 6
local GUARD_TICK_SECONDS = 1
local MAX_FLOOR_ID = 24

local function toast(player: Player, text: string): ()
	ToastRemote:FireClient(player, text)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function statusFor(player: Player, floorId: string): TowerRules.Status?
	local data = PlayerDataService.get(player)
	if data == nil then
		return nil
	end
	return TowerRules.status(
		floorId,
		data.BossDefeats,
		LevelRules.levelFor(data.Xp),
		data.AdminUnlocks,
		BuffService.hasBossBypass(player)
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

local function onRide(player: Player, rawFloorId: unknown): ()
	local floorId = Validate.id(rawFloorId, MAX_FLOOR_ID)
	local floor = if floorId then TowerRules.floor(floorId) else nil
	if floor == nil or floorId == nil then
		return RemoteController.reject(player, "Tower.Ride", "unknown floor")
	end
	local root = rootOf(player)
	if root == nil then
		return
	end
	if not TowerRules.atDoor(root.Position, DOOR_REACH) then
		return toast(player, "Use the elevator at the west end of the corridor.")
	end
	local here = TowerRules.floorAt(root.Position)
	if here and here.Id == floor.Id then
		return toast(player, "You're already on this floor.")
	end
	local status = statusFor(player, floor.Id)
	if status == nil then
		return toast(player, "Still loading your progress...")
	end
	if not status.Open then
		return toast(player, string.format("%s: %s first.", floor.Name, status.Reason))
	end
	local arrival = TowerRules.arrival(floor.Id) :: Vector3
	moveTo(player, arrival)
	if floor.Id == "Executive" then
		StressService.spike(player)
		toast(player, "Welcome to the Executive Floor. Stress level: MAXIMUM.")
	end
end

local function guardTick(): ()
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		local here = if root then TowerRules.floorAt(root.Position) else nil
		if here and here.Id == "Department" then
			local status = statusFor(player, "Department")
			if status and not status.Open then
				moveTo(player, TowerRules.arrival("Senior") :: Vector3)
				toast(player, string.format("Department Heads: %s first.", status.Reason))
			end
		end
	end
end

local function addPrompt(floor: TowerRules.Floor): ()
	local office = Workspace:WaitForChild("Office")
	local door = office:FindFirstChild(floor.DoorName, true)
	if door == nil or not door:IsA("BasePart") then
		warn("[TowerService] missing elevator door " .. floor.DoorName)
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = TowerService.PROMPT_NAME
	prompt.ObjectText = string.format("Elevator · Floor %d", floor.Number)
	prompt.ActionText = "Choose a floor"
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = door
end

function TowerService.init(): ()
	RemoteController.bind(RideRemote, {
		name = "Tower.Ride",
		maxArgs = 1,
		rateLimit = RemoteLimits.Tower,
	}, onRide)
end

function TowerService.start(): ()
	for _, floor in TowerRules.floors() do
		addPrompt(floor)
	end
	while true do
		task.wait(GUARD_TICK_SECONDS)
		guardTick()
	end
end

return TowerService
