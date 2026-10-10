--!strict
--[[
	The tower elevator's floor panel (docs/TOWER.md). Display and requests
	only: the server checks every ride (TowerService).

	Opened by the "Elevator" prompt on any elevator door. Lists every floor,
	top first: its number, name and what's there; "You are here" on the
	current one; Go on the ones you may visit; and for locked floors what's
	missing with a progress bar (Shared/TowerRules, from the snapshot).
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attributes"))
local TowerRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TowerRules"))

local PanelKit = require(script.Parent.Parent.Lib.PanelKit)
local ProgressController = require(script.Parent.ProgressController)

local TowerController = {}

local C = PanelKit.Colors
local ACCENT = Color3.fromRGB(230, 170, 60)
local PROMPT_NAME = "TowerPrompt" -- TowerService.PROMPT_NAME

local localPlayer = Players.LocalPlayer
local rideRemote: RemoteEvent? = nil
local openPanel: (() -> ())? = nil

function TowerController.open(): ()
	if openPanel then
		openPanel()
	end
end

local function currentFloor(): TowerRules.Floor?
	local character = localPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return TowerRules.floorAt(root.Position)
	end
	return nil
end

local function buildPanel(parent: Instance): ()
	local window = PanelKit.window({
		Name = "Elevator",
		Title = "🛗 Elevator",
		Subtitle = "Pick a floor. Locked floors show what you still need.",
		Accent = ACCENT,
		DisplayOrder = 5,
	}, parent)
	local content = window.Content

	local function render(): ()
		window:clear()
		local snapshot = ProgressController.get()
		if snapshot == nil then
			PanelKit.text(content, "Loading your progress...", "Muted")
			return
		end
		local adminUnlocks: { [string]: boolean } = {}
		for _, bossId in snapshot.AdminUnlocks do
			adminUnlocks[bossId] = true
		end
		local bypass = localPlayer:GetAttribute(Attributes.AdminBypass) == true
		local here = currentFloor()
		local floors = TowerRules.floors()
		for index = #floors, 1, -1 do
			local floor = floors[index]
			local section = PanelKit.section(
				content,
				string.format("%d · %s", floor.Number, floor.Name),
				false,
				true
			)
			PanelKit.text(section.Body, floor.Text, "Muted")
			local status = TowerRules.status(
				floor.Id,
				snapshot.BossDefeats,
				snapshot.Level,
				adminUnlocks,
				bypass
			)
			if here and here.Id == floor.Id then
				PanelKit.text(section.Body, "📍 You are here", "Heading")
			elseif status.Open then
				local row = PanelKit.row(section.Body)
				local go = PanelKit.button(row, "Go to floor " .. floor.Number, ACCENT)
				go.Size = UDim2.new(0.5, -4, 1, 0)
				go.Activated:Connect(function()
					window:close()
					local remote = rideRemote
					if remote then
						remote:FireServer(floor.Id)
					end
				end)
			else
				local bar = PanelKit.progressBar(section.Body, C.Neutral)
				bar.set(status.Progress, "🔒 " .. status.Reason)
			end
		end
	end

	window:onOpen(function()
		task.defer(render)
	end)
	openPanel = function()
		if window:isOpen() then
			render()
		else
			window:open()
		end
	end
	ProgressController.Changed:Connect(function()
		if window:isOpen() then
			render()
		end
	end)
end

function TowerController.start(): ()
	local remote =
		ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Tower"):WaitForChild("Ride")
	assert(remote:IsA("RemoteEvent"), "Tower.Ride must be a RemoteEvent")
	rideRemote = remote
	buildPanel(localPlayer:WaitForChild("PlayerGui"))
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name == PROMPT_NAME then
			TowerController.open()
		end
	end)
end

return TowerController
