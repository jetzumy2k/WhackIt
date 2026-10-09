--!strict
--[[
	Pets on screen (docs/PETS.md). Display only: the server owns pets, eggs,
	timers and buffs (PetService); this draws them and sends requests.

	  * Followers: every player's equipped pet (the PetSpecies attribute)
	    follows that player's character, built locally (Lib/PetVisual), never
	    colliding or blocking anything. One Heartbeat moves them all with one
	    BulkMoveTo, skipping pets far from the camera. Walkers trail behind and
	    to the right at the owner's feet; flyers hover beside the shoulder.
	    A pet only snaps when it falls far behind (e.g. after a teleport).
	  * Incubators: each shows its egg's rarity, countdown, progress bar and
	    owner (from the incubator's attributes), updated 4x a second while
	    near. When an egg hatches the egg shakes, a few sparkles pop and the
	    pet appears for a moment.
	  * World eggs bob gently.
	  * Egg picker: when you use an incubator with several kinds of egg, pick
	    one (Pets.ChooseEgg -> Pets.Incubate).
	  * "Egg hatched!" card (Pets.Hatched), with EQUIP if it isn't already.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Attributes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attributes"))
local PetConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("PetConfig"))
local PetRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PetRules"))
local StoreConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StoreConfig"))

local AnnouncementController = require(script.Parent.AnnouncementController)
local PetMotion = require(script.Parent.Parent.Lib.PetMotion)
local PetVisual = require(script.Parent.Parent.Lib.PetVisual)
local ProgressController = require(script.Parent.ProgressController)
local Responsive = require(script.Parent.Parent.Lib.Responsive)

local PetController = {}

local DRAW_DISTANCE = 150
-- Beyond this from the camera a pet moves 10 times a second instead of every frame.
local LOD_DISTANCE = 70
local LOD_STEP = 0.1
local GROUND_RAY_SECONDS = 0.12
local GROUND_RAY_UP = 4
local GROUND_RAY_LENGTH = 14
local FILTER_REFRESH_SECONDS = 1
local DISPLAY_DISTANCE = 90
local DISPLAY_TICK = 0.25
local HATCH_SHAKE_SECONDS = 1.2
local HATCH_SHOW_SECONDS = 3.5
local CARD_COLOR = Color3.fromRGB(26, 29, 41)
local TEXT_COLOR = Color3.fromRGB(240, 242, 248)
local MUTED_COLOR = Color3.fromRGB(170, 176, 198)
local READY_COLOR = Color3.fromRGB(255, 214, 120)
local BAR_BACK = Color3.fromRGB(52, 57, 80)

type Follower = {
	Owner: Player,
	Species: string,
	Rig: PetVisual.Rig,
	Motion: PetMotion.State,
	Root: BasePart?, -- the owner's root it followed last (a new one = respawned)
	GroundY: number,
	NextRayAt: number,
	Pending: number, -- time owed to a far pet (level of detail)
}

local localPlayer = Players.LocalPlayer
local followers: { [Player]: Follower } = {}
local petsFolder: Folder? = nil
local equipRemote: RemoteEvent? = nil

-- Asks the server to equip a pet ("" puts it away). The server checks ownership.
function PetController.equip(petId: string): ()
	local remote = equipRemote
	if remote then
		remote:FireServer(petId)
	end
end

-- "00:42" for up to an hour, then "1:02:03".
function PetController.countdown(seconds: number): string
	local total = math.max(0, math.ceil(seconds))
	if total >= 3600 then
		return string.format("%d:%02d:%02d", total // 3600, (total % 3600) // 60, total % 60)
	end
	return string.format("%02d:%02d", total // 60, total % 60)
end

-- Followers ------------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
local nextFilterAt = 0

-- Ground rays skip characters, pets, boss hitboxes and the incubators.
local function refreshRayFilter(now: number): ()
	if now < nextFilterAt then
		return
	end
	nextFilterAt = now + FILTER_REFRESH_SECONDS
	local skip: { Instance } = {}
	for _, name in { "ClientPets", "Bosses", "PetCenter" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(skip, folder)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(skip, player.Character)
		end
	end
	rayParams.FilterDescendantsInstances = skip
end

local function removeFollower(player: Player): ()
	local follower = followers[player]
	if follower then
		followers[player] = nil
		-- The glitter emitter is inside the model, so it goes too.
		follower.Rig.Model:Destroy()
	end
end

-- One visual pet per player: the old one is always removed first, so
-- equipping, swapping or respawning never leaves a duplicate behind.
local function refreshFollower(player: Player): ()
	local species = player:GetAttribute(Attributes.PetSpecies)
	local current = followers[player]
	if typeof(species) ~= "string" or species == "" then
		removeFollower(player)
		return
	end
	if current and current.Species == species then
		return
	end
	removeFollower(player)
	local now = os.clock()
	local rig = PetVisual.build(species, { LowDetail = Responsive.formFactor() == "Phone" })
	rig.Model.Name = player.Name .. "_Pet"
	rig.Model.Parent = petsFolder
	followers[player] = {
		Owner = player,
		Species = species,
		Rig = rig,
		Motion = PetMotion.new(species, now, player.UserId),
		Root = nil,
		GroundY = 0,
		NextRayAt = 0,
		Pending = 0,
	}
end

local function watchPlayer(player: Player): ()
	player:GetAttributeChangedSignal(Attributes.PetSpecies):Connect(function()
		refreshFollower(player)
	end)
	refreshFollower(player)
end

-- The ground under `position` (or the owner's feet if there's nothing there).
local function groundUnder(position: Vector3, ownerRoot: BasePart, ownerFeetY: number): number
	local origin = Vector3.new(position.X, ownerRoot.Position.Y + GROUND_RAY_UP, position.Z)
	local hit = Workspace:Raycast(origin, Vector3.new(0, -GROUND_RAY_LENGTH, 0), rayParams)
	return if hit then hit.Position.Y else ownerFeetY
end

-- Moves one pet; returns its parts and CFrames (nil when it isn't drawn now).
local function stepFollower(
	follower: Follower,
	dt: number,
	now: number,
	eye: Vector3
): ({ BasePart }?, { CFrame }?)
	local character = follower.Owner.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if character == nil or root == nil or not root:IsA("BasePart") then
		return nil, nil -- respawning: it stays put until the new character arrives
	end
	local motion = follower.Motion
	if root ~= follower.Root then
		follower.Root = root
		motion.Placed = false -- new character: back beside its owner
	end
	local cameraDistance = (root.Position - eye).Magnitude
	if cameraDistance > DRAW_DISTANCE then
		motion.Placed = false -- snaps back in when it comes near again
		follower.Pending = 0
		return nil, nil
	end
	-- Level of detail: far pets move 10 times a second.
	follower.Pending += dt
	if cameraDistance > LOD_DISTANCE and follower.Pending < LOD_STEP then
		return nil, nil
	end
	local stepDt = follower.Pending
	follower.Pending = 0

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hip = if humanoid then humanoid.HipHeight else 2
	local feetY = root.Position.Y - hip - root.Size.Y / 2
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	local ownerYaw = if look.Magnitude > 0.01 then PetMotion.yawOf(look) else motion.Yaw
	local velocity = root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)

	-- The ground under the pet, a few times a second (eased in between).
	if now >= follower.NextRayAt or not motion.Placed then
		follower.NextRayAt = now + GROUND_RAY_SECONDS
		local probe = if motion.Placed then motion.Position else root.Position
		local target = groundUnder(probe, root, feetY)
		if not motion.Placed or math.abs(target - follower.GroundY) > 4 then
			follower.GroundY = target -- new place or a big drop: no slow slide
		else
			follower.GroundY += (target - follower.GroundY) * 0.6
		end
	end

	local pivot, pose = PetMotion.step(motion, {
		OwnerPosition = root.Position,
		OwnerYaw = ownerYaw,
		OwnerSpeed = velocity.Magnitude,
		GroundY = follower.GroundY,
		Time = now,
		Dt = stepDt,
	})
	return PetVisual.pose(follower.Rig, pivot, pose)
end

-- Every pet in one pass and one BulkMoveTo (no per-pet loops or physics).
local function stepFollowers(dt: number): ()
	if next(followers) == nil then
		return
	end
	local now = os.clock()
	refreshRayFilter(now)
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	for _, follower in followers do
		local rigParts, rigFrames = stepFollower(follower, dt, now, eye)
		if rigParts and rigFrames then
			table.move(rigParts, 1, #rigParts, #parts + 1, parts)
			table.move(rigFrames, 1, #rigFrames, #cframes + 1, cframes)
		end
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- The owner landed a hit: their pet gets briefly excited (it never attacks).
local function onCombatFeedback(payload: unknown): ()
	if typeof(payload) ~= "table" then
		return
	end
	local hitter = (payload :: { [string]: unknown }).HitterUserId
	local player = if typeof(hitter) == "number" then Players:GetPlayerByUserId(hitter) else nil
	local follower = if player then followers[player] else nil
	if follower then
		PetMotion.react(follower.Motion, os.clock())
	end
end

-- Incubators -----------------------------------------------------------------

type Display = {
	Model: Model,
	Title: TextLabel,
	Status: TextLabel,
	Owner: TextLabel,
	Fill: Frame,
	Bar: Frame,
}

local function displayFor(model: Model): Display?
	local pod = model:FindFirstChild("Pod")
	if pod == nil or not pod:IsA("BasePart") then
		return nil
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "IncubatorDisplay"
	billboard.Adornee = pod
	billboard.Size = UDim2.fromScale(6, 2.8) -- studs
	billboard.StudsOffset = Vector3.new(0, 3.6, 0)
	billboard.MaxDistance = DISPLAY_DISTANCE
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	local card = Instance.new("Frame")
	card.BackgroundColor3 = CARD_COLOR
	card.BackgroundTransparency = 0.15
	card.Size = UDim2.fromScale(1, 1)
	card.Parent = billboard
	Instance.new("UICorner").Parent = card
	local function line(name: string, y: number, height: number, color: Color3): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0.04, y)
		label.Size = UDim2.fromScale(0.92, height)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = color
		label.RichText = false
		label.Parent = card
		return label
	end
	local title = line("Title", 0.04, 0.26, TEXT_COLOR)
	local status = line("Status", 0.3, 0.24, READY_COLOR)
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundColor3 = BAR_BACK
	bar.Position = UDim2.fromScale(0.08, 0.58)
	bar.Size = UDim2.fromScale(0.84, 0.12)
	bar.Parent = card
	Instance.new("UICorner").Parent = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Color3.fromRGB(90, 210, 200)
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = bar
	Instance.new("UICorner").Parent = fill
	local owner = line("Owner", 0.74, 0.2, MUTED_COLOR)
	billboard.Parent = localPlayer:WaitForChild("PlayerGui")
	return { Model = model, Title = title, Status = status, Owner = owner, Fill = fill, Bar = bar }
end

local function stringAttr(model: Instance, name: string): string
	local value = model:GetAttribute(name)
	return if typeof(value) == "string" then value else ""
end

local function numberAttr(model: Instance, name: string): number
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function refreshDisplay(display: Display, now: number): ()
	local model = display.Model
	local index = numberAttr(model, Attributes.IncubatorIndex)
	local ownerId = numberAttr(model, Attributes.OwnerUserId)
	local hatched = stringAttr(model, Attributes.HatchedSpecies)
	local ownerName = stringAttr(model, Attributes.OwnerName)
	if hatched ~= "" then
		display.Title.Text = "✨ EGG HATCHED!"
		display.Status.Text = PetRules.title(hatched)
		display.Bar.Visible = false
		display.Owner.Text = if ownerName ~= "" then ownerName .. "'s new pet" else ""
		return
	end
	if ownerId == 0 then
		display.Title.Text = string.format("🥚 INCUBATOR %d", index)
		display.Status.Text = "Empty: place an egg!"
		display.Bar.Visible = false
		display.Owner.Text = "60 seconds to hatch"
		return
	end
	local rarity = stringAttr(model, Attributes.EggRarity)
	local endsAt = numberAttr(model, Attributes.EndsAt)
	local left = endsAt - now
	local total = PetConfig.IncubationSeconds
	display.Title.Text = "🥚 " .. string.upper(rarity) .. " EGG"
	display.Status.Text = if left > 0
		then "Incubating... " .. PetController.countdown(left)
		else "✨ Hatching!"
	display.Bar.Visible = true
	display.Fill.Size = UDim2.fromScale(math.clamp(1 - left / total, 0, 1), 1)
	display.Owner.Text = "Owner: " .. ownerName
end

-- Egg shakes, sparkles pop, the pet appears for a moment (all local).
local function playHatch(model: Model, species: string): ()
	local egg = model:FindFirstChild("Egg")
	local pod = model:FindFirstChild("Pod")
	if egg == nil or not egg:IsA("BasePart") or pod == nil or not pod:IsA("BasePart") then
		return
	end
	local rest = egg.CFrame
	local shakes = 8
	for step = 1, shakes do
		local tilt = math.rad(if step % 2 == 0 then 12 else -12)
		egg.CFrame = rest * CFrame.Angles(0, 0, tilt)
		task.wait(HATCH_SHAKE_SECONDS / shakes)
	end
	egg.CFrame = rest
	egg.LocalTransparencyModifier = 1
	local burst = Instance.new("ParticleEmitter")
	burst.Rate = 0
	burst.Lifetime = NumberRange.new(0.5, 0.9)
	burst.Speed = NumberRange.new(3, 6)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Size = NumberSequence.new(0.25, 0)
	burst.LightEmission = 0.4
	burst.Color = ColorSequence.new(READY_COLOR)
	burst.Parent = pod
	burst:Emit(14)
	local rig = PetVisual.build(species)
	rig.Model.Parent = petsFolder
	local base = rest * CFrame.new(0, if rig.Flies then 0.3 else -1.1, 0)
	local born = os.clock()
	local connection = RunService.Heartbeat:Connect(function()
		local parts, cframes = PetVisual.pose(rig, base, PetVisual.restPose(os.clock() - born))
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end)
	task.delay(HATCH_SHOW_SECONDS, function()
		connection:Disconnect()
		rig.Model:Destroy()
		burst:Destroy()
		egg.LocalTransparencyModifier = 0
	end)
end

local function watchIncubators(): { Display }
	local displays: { Display } = {}
	local center = Workspace:WaitForChild("PetCenter", 30)
	local folder = if center then center:WaitForChild("Incubators", 30) else nil
	if folder == nil then
		return displays
	end
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			local display = displayFor(child)
			if display then
				table.insert(displays, display)
			end
			child:GetAttributeChangedSignal(Attributes.HatchedSpecies):Connect(function()
				local species = stringAttr(child, Attributes.HatchedSpecies)
				if species ~= "" then
					task.spawn(playHatch, child, species)
				end
			end)
		end
	end
	return displays
end

-- World eggs bob gently (local tween on the server's anchored egg).
local function watchWorldEggs(): ()
	local center = Workspace:WaitForChild("PetCenter", 30)
	local folder = if center then center:WaitForChild("WorldEggs", 30) else nil
	if folder == nil then
		return
	end
	local function bob(model: Instance): ()
		local egg = model:WaitForChild("Egg", 5)
		if egg and egg:IsA("BasePart") then
			TweenService:Create(
				egg,
				TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ CFrame = egg.CFrame * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, math.rad(40), 0) }
			):Play()
		end
	end
	folder.ChildAdded:Connect(bob)
	for _, child in folder:GetChildren() do
		task.spawn(bob, child)
	end
end

-- Egg picker -------------------------------------------------------------------

local function buildPicker(
	incubateRemote: RemoteEvent
): (incubatorIndex: number, keys: { string }) -> ()
	local gui = Instance.new("ScreenGui")
	gui.Name = "EggPicker"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 7
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.BackgroundColor3 = CARD_COLOR
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Visible = false
	frame.Parent = gui
	Instance.new("UICorner").Parent = frame
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(360, math.huge)
	limit.Parent = frame
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	Responsive.onChanged(function()
		frame.Size = UDim2.fromScale(if Responsive.formFactor() == "Phone" then 0.8 else 0.3, 0)
	end)
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	local function button(text: string, color: Color3, order: number): TextButton
		local clickable = Instance.new("TextButton")
		clickable.LayoutOrder = order
		clickable.Size = UDim2.new(1, 0, 0, 44)
		clickable.BackgroundColor3 = color
		clickable.TextColor3 = TEXT_COLOR
		clickable.Font = Enum.Font.FredokaOne
		clickable.Text = text
		clickable.Parent = frame
		Instance.new("UICorner").Parent = clickable
		Responsive.capText(clickable, 20)
		return clickable
	end

	return function(incubatorIndex: number, keys: { string })
		for _, child in frame:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local title = Instance.new("TextLabel")
		title.LayoutOrder = 0
		title.BackgroundTransparency = 1
		title.Size = UDim2.new(1, 0, 0, 30)
		title.Font = Enum.Font.FredokaOne
		title.TextColor3 = READY_COLOR
		title.Text = string.format("Which egg goes in Incubator %d?", incubatorIndex)
		title.Parent = frame
		Responsive.capText(title, 22)
		local snapshot = ProgressController.get()
		for order, key in keys do
			local product = StoreConfig.ByKey[key]
			local rarity = if product then product.Rarity else nil
			local info = if rarity then PetConfig.RarityInfo[rarity] else nil
			local count = if snapshot then snapshot.Bag[key] or 0 else 0
			local choice = button(
				string.format(
					"🥚 %s  x%d",
					if product then product.DisplayName or key else key,
					count
				),
				if info then info.Color:Lerp(Color3.new(0, 0, 0), 0.35) else MUTED_COLOR,
				order
			)
			choice.Activated:Connect(function()
				frame.Visible = false
				incubateRemote:FireServer(key, incubatorIndex)
			end)
		end
		button("Cancel", Color3.fromRGB(78, 84, 108), 100).Activated:Connect(function()
			frame.Visible = false
		end)
		frame.Visible = true
	end
end

-- Start ----------------------------------------------------------------------

function PetController.start(): ()
	local folder = Instance.new("Folder")
	folder.Name = "ClientPets"
	folder.Parent = Workspace
	petsFolder = folder

	local remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Pets")
	local equip = remotes:WaitForChild("Equip")
	local incubate = remotes:WaitForChild("Incubate")
	local chooseEgg = remotes:WaitForChild("ChooseEgg")
	local hatched = remotes:WaitForChild("Hatched")
	assert(
		equip:IsA("RemoteEvent")
			and incubate:IsA("RemoteEvent")
			and chooseEgg:IsA("RemoteEvent")
			and hatched:IsA("RemoteEvent"),
		"Pets remotes must be RemoteEvents"
	)
	equipRemote = equip

	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(removeFollower)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	-- One Heartbeat moves every pet (one BulkMoveTo); see stepFollowers.
	RunService.Heartbeat:Connect(stepFollowers)
	local feedback = ReplicatedStorage:WaitForChild("Remotes")
		:WaitForChild("Combat")
		:WaitForChild("CombatFeedback")
	assert(feedback:IsA("RemoteEvent"), "Combat.CombatFeedback must be a RemoteEvent")
	feedback.OnClientEvent:Connect(onCombatFeedback)

	local showPicker = buildPicker(incubate)
	chooseEgg.OnClientEvent:Connect(function(rawIndex: unknown, rawKeys: unknown)
		if typeof(rawIndex) ~= "number" or typeof(rawKeys) ~= "table" then
			return
		end
		local keys: { string } = {}
		for _, key in rawKeys :: { unknown } do
			if typeof(key) == "string" and StoreConfig.ByKey[key] and #keys < 3 then
				table.insert(keys, key)
			end
		end
		if #keys > 0 then
			showPicker(rawIndex, keys)
		end
	end)

	hatched.OnClientEvent:Connect(function(payload: unknown)
		if typeof(payload) ~= "table" then
			return
		end
		local data = payload :: { [string]: unknown }
		local petId, species, rarity = data.PetId, data.Species, data.Rarity
		if
			typeof(petId) ~= "string"
			or typeof(species) ~= "string"
			or typeof(rarity) ~= "string"
		then
			return
		end
		local lines: { string } = { string.upper(rarity) }
		local buffs = PetRules.parseBuffs(data.Buffs)
		for _, buff in buffs or ({} :: { PetRules.Buff }) do
			table.insert(lines, PetRules.buffText(buff))
		end
		local info = PetConfig.RarityInfo[rarity]
		local alreadyEquipped = data.Equipped == true
		if alreadyEquipped then
			table.insert(lines, "It's following you now!")
		end
		AnnouncementController.show({
			Title = "✨ EGG HATCHED!",
			Body = "Your " .. PetRules.title(species) .. " is ready!",
			Detail = table.concat(lines, "   "),
			Accent = if info then info.Color else READY_COLOR,
			Seconds = 10,
			ActionLabel = if alreadyEquipped then nil else "EQUIP",
			OnAction = if alreadyEquipped
				then nil
				else function()
					PetController.equip(petId)
				end,
		})
	end)

	task.spawn(watchWorldEggs)
	local displays = watchIncubators()
	while true do
		local camera = Workspace.CurrentCamera
		local eye = if camera then camera.CFrame.Position else Vector3.zero
		local now = Workspace:GetServerTimeNow()
		for _, display in displays do
			local pivot = display.Model:GetPivot().Position
			if (pivot - eye).Magnitude <= DISPLAY_DISTANCE then
				refreshDisplay(display, now)
			end
		end
		task.wait(DISPLAY_TICK)
	end
end

return PetController
