--!strict
--[[
	Brings the lounge NPCs to life on this client (built by the server's
	Lib/NpcBuilder; who they are is in Config/NpcConfig). Local visuals only.

	  * Idle: a few TweenService tweens per NPC, set to repeat and started once:
	    looking around (Greet, Coffee), reading with the odd page turn (Read),
	    a slow head sway towards the neighbour (Chat), sipping coffee (Coffee).
	    No per-frame script work.
	  * Talking: every CheckInterval (0.5 s, not every frame) one small loop
	    checks how far you are. An NPC greets you when you walk up (Rita also
	    waves), and now and then one near you says a line, or the couch pair
	    has a little two-line chat. Lines show in a speech bubble above the NPC,
	    only for you.
	Respawning is fine: the loop always uses your current character.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local NpcConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("NpcConfig"))

local NpcController = {}

-- Names set by the server's Lib/NpcBuilder.
local FOLDER_NAME = "LobbyNpcs"
local NPC_ATTRIBUTE = "NpcId"
local HEAD = "Head"
local ARM = "RightArm"

type Live = {
	Config: NpcConfig.Npc,
	Model: Model,
	Head: BasePart,
	Arm: BasePart,
	ArmBase: CFrame,
	Bubble: TextLabel,
	BubbleGui: BillboardGui,
	Shown: number,
	LastGreetAt: number,
	WasNear: boolean,
}

local localPlayer = Players.LocalPlayer
local random = Random.new()
local lives: { [string]: Live } = {}

local function loop(seconds: number, delay: number?): TweenInfo
	return TweenInfo.new(
		seconds,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1,
		true,
		delay or 0
	)
end

-- The arm's CFrame swung forward by `degrees` about its shoulder.
local function armSwung(live: Live, degrees: number): CFrame
	local half = live.Arm.Size.Y / 2
	local shoulder = live.ArmBase * CFrame.new(0, half, 0)
	return shoulder * CFrame.Angles(math.rad(degrees), 0, 0) * CFrame.new(0, -half, 0)
end

local function say(live: Live, text: string): ()
	live.Bubble.Text = text
	live.BubbleGui.Enabled = true
	live.Shown += 1
	local token = live.Shown
	task.delay(NpcConfig.LineSeconds, function()
		if live.Shown == token then
			live.BubbleGui.Enabled = false
		end
	end)
end

local function pick(lines: { string }): string?
	return if #lines > 0 then lines[random:NextInteger(1, #lines)] else nil
end

-- Rita waves: the arm goes up and back twice.
local function wave(live: Live): ()
	local info = TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true)
	TweenService:Create(live.Arm, info, { CFrame = armSwung(live, 120) }):Play()
end

local function buildBubble(head: BasePart): (BillboardGui, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Name = "NpcBubble"
	gui.Adornee = head
	gui.Size = UDim2.fromScale(7, 1.4) -- studs
	gui.StudsOffset = Vector3.new(0, head.Size.Y / 2 + 1.2, 0)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.MaxDistance = NpcConfig.ChatterStuds + 10
	gui.Enabled = false
	gui.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(245, 240, 230)
	label.TextColor3 = Color3.fromRGB(35, 30, 40)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextWrapped = true
	label.Parent = gui
	Instance.new("UICorner").Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = label
	return gui, label
end

local function startIdle(live: Live): ()
	local head = live.Head
	local headBase = head.CFrame
	local behavior = live.Config.Behavior
	local offset = random:NextNumber(0, 1)
	if behavior == "Greet" or behavior == "Coffee" then
		-- Looking around the lobby.
		head.CFrame = headBase * CFrame.Angles(0, math.rad(-25), 0)
		TweenService
			:Create(
				head,
				loop(3.2 + offset),
				{ CFrame = headBase * CFrame.Angles(0, math.rad(25), 0) }
			)
			:Play()
	elseif behavior == "Read" then
		-- Eyes down on the book, looking up now and then.
		head.CFrame = headBase * CFrame.Angles(math.rad(-14), 0, 0)
		TweenService:Create(
			head,
			loop(1.2, 4 + offset),
			{ CFrame = headBase * CFrame.Angles(math.rad(4), 0, 0) }
		):Play()
		-- Turning a page.
		TweenService:Create(live.Arm, loop(0.5, 5 + offset), { CFrame = armSwung(live, 12) }):Play()
	elseif behavior == "Chat" then
		TweenService:Create(
			head,
			loop(2.6 + offset),
			{ CFrame = headBase * CFrame.Angles(math.rad(5), math.rad(-10), 0) }
		):Play()
	end
	if behavior == "Coffee" or behavior == "Chat" then
		-- A sip: the mug comes up to the face, then back down.
		TweenService:Create(live.Arm, loop(0.8, 3.5 + offset * 2), { CFrame = armSwung(live, 70) })
			:Play()
	end
end

local function attach(model: Instance): ()
	if not model:IsA("Model") then
		return
	end
	local id = model:GetAttribute(NPC_ATTRIBUTE)
	local config = if typeof(id) == "string" then NpcConfig.ById[id] else nil
	local head = model:FindFirstChild(HEAD)
	local arm = model:FindFirstChild(ARM)
	if
		config == nil
		or head == nil
		or arm == nil
		or not head:IsA("BasePart")
		or not arm:IsA("BasePart")
	then
		return
	end
	local gui, label = buildBubble(head)
	local live: Live = {
		Config = config,
		Model = model,
		Head = head,
		Arm = arm,
		ArmBase = arm.CFrame,
		Bubble = label,
		BubbleGui = gui,
		Shown = 0,
		LastGreetAt = -math.huge,
		WasNear = false,
	}
	lives[config.Id] = live
	startIdle(live)
	model.Destroying:Connect(function()
		if lives[config.Id] == live then
			lives[config.Id] = nil
		end
	end)
end

local function distanceTo(live: Live, from: Vector3): number
	return (live.Head.Position - from).Magnitude
end

-- One check every CheckInterval: greetings and the odd bit of chatter.
local function watch(): ()
	local nextChatterAt = os.clock() + random:NextNumber(NpcConfig.ChatterMin, NpcConfig.ChatterMax)
	while true do
		task.wait(NpcConfig.CheckInterval)
		local character = localPlayer.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if root == nil or not root:IsA("BasePart") then
			continue
		end
		local now = os.clock()
		local nearby: { Live } = {}
		for _, live in lives do
			if live.Model.Parent == nil then
				continue
			end
			local distance = distanceTo(live, root.Position)
			local near = distance <= NpcConfig.GreetStuds
			if near and not live.WasNear and now - live.LastGreetAt >= NpcConfig.GreetCooldown then
				live.LastGreetAt = now
				local line = pick(live.Config.Lines)
				if line then
					say(live, line)
				end
				if live.Config.Behavior == "Greet" then
					wave(live)
				end
			end
			live.WasNear = near
			if distance <= NpcConfig.ChatterStuds then
				table.insert(nearby, live)
			end
		end
		if now >= nextChatterAt then
			nextChatterAt = now + random:NextNumber(NpcConfig.ChatterMin, NpcConfig.ChatterMax)
			if #nearby > 0 then
				local speaker = nearby[random:NextInteger(1, #nearby)]
				local line = pick(speaker.Config.Lines)
				if line then
					say(speaker, line)
				end
				-- The couch pair answer each other.
				local partner = if speaker.Config.Partner
					then lives[speaker.Config.Partner]
					else nil
				if partner then
					task.delay(NpcConfig.LineSeconds * 0.8, function()
						local reply = pick(partner.Config.Lines)
						if reply and partner.Model.Parent then
							say(partner, reply)
						end
					end)
				end
			end
		end
	end
end

function NpcController.start(): ()
	local folder = Workspace:WaitForChild(FOLDER_NAME, 60)
	if folder == nil then
		return
	end
	folder.ChildAdded:Connect(attach)
	for _, child in folder:GetChildren() do
		attach(child)
	end
	watch()
end

return NpcController
