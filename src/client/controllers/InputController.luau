--!strict
--[[
	Swings the held hammer and asks the server for a hit. Uses the Tool's own
	Activated event, which Roblox fires for mouse click, screen tap and gamepad R2.

	The swing animation and sound play immediately on every swing (even a miss)
	so the game feels responsive; the boss only reacts once the server confirms.
	Only the target boss id is sent; the server decides everything else.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CombatRules"))
local GameplayController = require(script.Parent.GameplayController)

local InputController = {}

-- Roblox's default Animate script plays its built-in slash animation when a
-- StringValue named "toolanim" with value "Slash" appears under the held Tool.
local TOOL_ANIM_NAME = "toolanim"
local TOOL_ANIM_SLASH = "Slash"
-- Built-in Roblox sound shipped with every client; no uploaded asset needed.
local SWING_SOUND_ID = "rbxasset://sounds/swordslash.wav"
local SWING_VOLUME = 0.6

local localPlayer = Players.LocalPlayer
local requestHammerHit: RemoteEvent
local lastSwingAt: number? = nil
local hookedTools: { [Tool]: boolean } = {}

local function playSwing(tool: Tool): ()
	local trigger = Instance.new("StringValue")
	trigger.Name = TOOL_ANIM_NAME
	trigger.Value = TOOL_ANIM_SLASH
	trigger.Parent = tool -- consumed (removed) by the Animate script

	local handle = tool:FindFirstChild("Handle")
	if handle then
		local sound = handle:FindFirstChild("SwingSound")
		if sound == nil then
			local created = Instance.new("Sound")
			created.Name = "SwingSound"
			created.SoundId = SWING_SOUND_ID
			created.Volume = SWING_VOLUME
			created.Parent = handle
			sound = created
		end
		if sound and sound:IsA("Sound") then
			sound:Play()
		end
	end
end

local function onActivated(tool: Tool): ()
	local now = os.clock()
	-- No grace on the client, so it never sends hits the server would drop.
	if not CombatRules.isOffCooldown(now, lastSwingAt, 0) then
		return
	end
	lastSwingAt = now
	playSwing(tool)

	local bossInstanceId = GameplayController.getNearestHittableBoss()
	if bossInstanceId then
		requestHammerHit:FireServer(bossInstanceId)
	end
end

local function hookTool(tool: Tool): ()
	if hookedTools[tool] then
		return
	end
	hookedTools[tool] = true
	tool.Activated:Connect(function()
		onActivated(tool)
	end)
	tool.Destroying:Connect(function()
		hookedTools[tool] = nil
	end)
end

local function onCharacterAdded(character: Model): ()
	-- The server equips the hammer shortly after spawn.
	character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") then
			hookTool(child)
		end
	end)
	for _, child in character:GetChildren() do
		if child:IsA("Tool") then
			hookTool(child)
		end
	end
end

function InputController.start(): ()
	local remote = ReplicatedStorage:WaitForChild("Remotes")
		:WaitForChild("Combat")
		:WaitForChild("RequestHammerHit")
	assert(remote:IsA("RemoteEvent"), "RequestHammerHit must be a RemoteEvent")
	requestHammerHit = remote

	localPlayer.CharacterAdded:Connect(onCharacterAdded)
	if localPlayer.Character then
		onCharacterAdded(localPlayer.Character)
	end
end

return InputController
