--!strict
-- Turns click / tap / gamepad presses into hit requests. Sends only the target
-- boss id; the server decides whether the hit lands and for how much.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CombatRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CombatRules"))
local GameplayController = require(script.Parent.GameplayController)

local InputController = {}

local WHACK_INPUT_TYPES: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
}

local WHACK_KEY_CODES: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.ButtonR2] = true,
	[Enum.KeyCode.ButtonX] = true,
}

local requestHammerHit: RemoteEvent
local lastSentAt: number? = nil

local function tryWhack(): ()
	local now = os.clock()
	-- No grace on the client, so it never sends hits the server would drop.
	if not CombatRules.isOffCooldown(now, lastSentAt, 0) then
		return
	end
	local bossInstanceId = GameplayController.getNearestHittableBoss()
	if bossInstanceId == nil then
		return
	end
	lastSentAt = now
	requestHammerHit:FireServer(bossInstanceId)
end

function InputController.start(): ()
	local remote = ReplicatedStorage:WaitForChild("Remotes")
		:WaitForChild("Combat")
		:WaitForChild("RequestHammerHit")
	assert(remote:IsA("RemoteEvent"), "RequestHammerHit must be a RemoteEvent")
	requestHammerHit = remote

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		-- Taps on buttons, the thumbstick or chat are not whacks.
		if gameProcessed then
			return
		end
		if WHACK_INPUT_TYPES[input.UserInputType] or WHACK_KEY_CODES[input.KeyCode] then
			tryWhack()
		end
	end)
end

return InputController
