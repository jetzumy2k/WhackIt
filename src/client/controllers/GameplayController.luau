--!strict
-- Client view of the bosses in the world. Read-only: it finds boss models and
-- reads their server-written attributes; it never decides hits or damage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Attributes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attributes"))
local CombatRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CombatRules"))

local GameplayController = {}

local bossesFolder: Instance? = nil

-- Yields until the server has created Workspace.Bosses (call from start(), not init()).
function GameplayController.waitForBossesFolder(): Instance
	if bossesFolder == nil then
		bossesFolder = Workspace:WaitForChild("Bosses")
	end
	return bossesFolder :: Instance
end

function GameplayController.getInstanceId(model: Instance): string?
	local id = model:GetAttribute(Attributes.BossInstanceId)
	if typeof(id) ~= "string" then
		return nil
	end
	return id
end

function GameplayController.findBoss(instanceId: string): Model?
	if bossesFolder == nil then
		return nil
	end
	for _, child in bossesFolder:GetChildren() do
		if child:IsA("Model") and GameplayController.getInstanceId(child) == instanceId then
			return child
		end
	end
	return nil
end

-- Nearest living boss within reach of the local character: its instance id
-- and BossConfig id, or nil. Locked bosses are included so the caller can say
-- why a swing won't count. The server re-checks everything.
function GameplayController.getNearestBossInReach(): (string?, string?)
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if bossesFolder == nil or root == nil or not root:IsA("BasePart") then
		return nil, nil
	end

	local nearestId: string? = nil
	local nearestBossId: string? = nil
	local nearestDistance = math.huge
	for _, child in bossesFolder:GetChildren() do
		local body = if child:IsA("Model") then child.PrimaryPart else nil
		local id = GameplayController.getInstanceId(child)
		if body == nil or id == nil or child:GetAttribute(Attributes.Defeated) == true then
			continue
		end
		local distance = (root.Position - body.Position).Magnitude
		local bossId = child:GetAttribute(Attributes.BossId)
		if
			CombatRules.isInReach(root.Position, body.Position, 0)
			and distance < nearestDistance
			and typeof(bossId) == "string"
		then
			nearestId = id
			nearestBossId = bossId
			nearestDistance = distance
		end
	end
	return nearestId, nearestBossId
end

function GameplayController.start(): ()
	GameplayController.waitForBossesFolder()
end

return GameplayController
