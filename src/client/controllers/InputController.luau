--!strict
--[[
	Swings the held hammer and asks the server for a hit.

	Swings are triggered from raw input (mouse click, screen tap, gamepad R2),
	ignoring input already used by GUI. Tool.Activated is also listened to as a
	backup; the cooldown means one press never swings twice.

	Each swing is a full wind-up / strike / follow-through (Lib/SwingAnimator)
	that starts immediately, even for a miss. The hit request is sent at the
	moment the hammer lands, so the boss reacts in time with the strike. Only the
	target boss id is sent; the server decides everything else.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CombatRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CombatRules"))
local SwingPose = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SwingPose"))
local GameplayController = require(script.Parent.GameplayController)
local SwingAnimator = require(script.Parent.Parent.Lib.SwingAnimator)
local UIController = require(script.Parent.UIController)

local InputController = {}

local SWING_INPUT_TYPES: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
}
local SWING_KEY_CODES: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.ButtonR2] = true,
}

-- Built-in Roblox sound shipped with every client; no uploaded asset needed.
local SWING_SOUND_ID = "rbxasset://sounds/swordslash.wav"
local SWING_VOLUME = 0.6
local TOO_FAR_HINT = "Get closer to the boss!"

local localPlayer = Players.LocalPlayer
local requestHammerHit: RemoteEvent
local lastSwingAt: number? = nil
-- The whoosh plays as the hammer starts coming down, not on the click.
local WHOOSH_PROGRESS = 0.38
local hookedTools: { [Tool]: boolean } = {}

local function getHeldHammer(): (Tool?, Humanoid?)
	local character = localPlayer.Character
	if character == nil then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local tool = character:FindFirstChildOfClass("Tool")
	if humanoid == nil or humanoid.Health <= 0 or tool == nil then
		return nil, nil
	end
	return tool, humanoid
end

local function playWhoosh(tool: Tool): ()
	local handle = tool:FindFirstChild("Handle")
	if handle == nil then
		return
	end
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

-- Runs when the hammer comes down: picks the boss in reach at that moment.
local function onImpact(): ()
	local tool = getHeldHammer()
	if tool == nil then
		return -- died or lost the hammer mid-swing
	end
	local bossInstanceId = GameplayController.getNearestHittableBoss()
	if bossInstanceId then
		requestHammerHit:FireServer(bossInstanceId)
	else
		UIController.showToast(TOO_FAR_HINT)
	end
end

local function swing(): ()
	local tool, humanoid = getHeldHammer()
	if tool == nil or humanoid == nil then
		return
	end

	local now = os.clock()
	-- One swing per cooldown; the swing lasts exactly one cooldown, so presses
	-- during a swing are ignored instead of cutting it short.
	if not CombatRules.isOffCooldown(now, lastSwingAt, 0) then
		return
	end
	lastSwingAt = now

	local character = humanoid.Parent
	if character and character:IsA("Model") then
		SwingAnimator.play(character)
	end
	task.delay(SwingAnimator.secondsUntil(WHOOSH_PROGRESS), playWhoosh, tool)
	task.delay(SwingAnimator.secondsUntil(SwingPose.IMPACT), onImpact)
end

-- Backup trigger: some setups deliver presses to the Tool rather than raw input.
local function hookTool(tool: Tool): ()
	if hookedTools[tool] then
		return
	end
	hookedTools[tool] = true
	tool.Activated:Connect(swing)
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

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		-- Presses on buttons, the thumbstick or chat are not swings.
		if gameProcessed then
			return
		end
		if SWING_INPUT_TYPES[input.UserInputType] or SWING_KEY_CODES[input.KeyCode] then
			swing()
		end
	end)

	localPlayer.CharacterAdded:Connect(onCharacterAdded)
	if localPlayer.Character then
		onCharacterAdded(localPlayer.Character)
	end
end

return InputController
