--!strict
--[[
	Pets, eggs and incubators (docs/PETS.md). Server authority for all of it:
	clients only ask (Pets.Equip, Pets.Incubate, the ProximityPrompts); species,
	buffs, ownership, timing and rewards are decided here.

	Eggs are store items in the player's Bag (StoreConfig Kind "Egg"): bought
	(PurchaseService), found outside (world eggs below) or dropped by bosses
	during an event. Pets live in the player's data (Pets, EquippedPetId).

	Incubation: an egg goes into one of the six incubators. In one step (no
	yield) the egg leaves the Bag, what will hatch is rolled (Shared/PetRules)
	and saved with the start and end time (data.Incubation). The timer is the
	saved end time, so walking away, leaving, rejoining or a server restart
	never pauses or resets it. When it ends the pet moves into the player's
	pets in one step (no yield), so it can't be duplicated: on time while the
	player is here, or as soon as their data loads if it ended while they were
	away. The incubator is only a display: when the owner leaves it frees up,
	and on rejoin their egg shows in a free incubator again (or only in the
	Player Panel if all are busy). One egg incubates per player at a time.

	World eggs: every PetConfig.WorldEggIntervalSeconds on the UTC clock a
	Common or Rare egg (PetConfig.WorldEggRarities) appears at a random safe
	spot (PetConfig.WorldEggSpawnPoints) while none is still out there, with an
	announcement (Notify.Announcement) that doesn't say where. The first
	player whose "Claim Egg" prompt reaches the server gets it; the egg is
	marked claimed before anything else happens. Admins can place one now
	(any rarity) through AdminService.

	The equipped pet is published as Player attributes (PetSpecies, PetRarity)
	so every client can draw it (PetController); its buffs are read from the
	saved pet by BuffService.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Attributes = require(ReplicatedStorage.Shared.Attributes)
local BagRules = require(ReplicatedStorage.Shared.BagRules)
local EventRules = require(ReplicatedStorage.Shared.EventRules)
local EventService = require(script.Parent.EventService)
local HistoryService = require(script.Parent.HistoryService)
local IncubatorBuilder = require(ServerScriptService.Lib.IncubatorBuilder)
local PetConfig = require(ReplicatedStorage.Config.PetConfig)
local PetRules = require(ReplicatedStorage.Shared.PetRules)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)
local RemoteController = require(ServerScriptService.Controllers.RemoteController)
local RemoteLimits = require(ServerScriptService.Config.RemoteLimits)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)
local Validate = require(ReplicatedStorage.Shared.Validate)

local PetRemotes = ReplicatedStorage.Remotes.Pets
local AnnouncementRemote = ReplicatedStorage.Remotes.Notify.Announcement
local ToastRemote = ReplicatedStorage.Remotes.Notify.Toast

local PetService = {}

-- How long a hatched pet shows in its incubator before it frees up.
local HATCH_SHOW_SECONDS = 5
-- A claim must come from within this many studs of the egg.
local CLAIM_REACH = 14
local WORLD_EGG_ANNOUNCE_SECONDS = 10

-- EventId: the egg hunt (EventService) that placed it; nil for scheduled /
-- admin eggs.
type WorldEgg = { Model: Model, Rarity: string, Claimed: boolean, Point: number, EventId: string? }

local built: IncubatorBuilder.Built? = nil
-- Incubator index -> the player whose egg it shows (nil = free).
local occupants: { [number]: Player? } = {}
-- Incubator index -> the hatch animation keeps it busy until this os.clock().
local busyUntil: { [number]: number } = {}
local shownAt: { [Player]: number } = {}
local worldEggs: { [string]: WorldEgg } = {}
local nextEggNumber = 0
local nextWorldEggAt = 0
local rollRandom = Random.new()

local function toast(player: Player, message: string): ()
	ToastRemote:FireClient(player, string.sub(message, 1, 120))
end

local function countPets(data: PlayerDataService.PlayerData): number
	local count = 0
	for _ in data.Pets do
		count += 1
	end
	return count
end

local function rarityLabel(rarity: string): string
	return rarity .. " Egg"
end

-- Equipped pet -> Player attributes, so every client can draw it.
local function publishPet(player: Player, data: PlayerDataService.PlayerData): ()
	local pet = if data.EquippedPetId ~= "" then data.Pets[data.EquippedPetId] else nil
	player:SetAttribute(Attributes.PetSpecies, if pet then pet.Species else nil)
	player:SetAttribute(Attributes.PetRarity, if pet then pet.Rarity else nil)
end

-- Incubators -----------------------------------------------------------------

local function incubatorModel(index: number): Model?
	local current = built
	return if current then current.Incubators[index] else nil
end

-- Shows `player`'s egg in incubator `index`, or an empty incubator when nil.
local function display(index: number, player: Player?, rarity: string?, endsAt: number?): ()
	local model = incubatorModel(index)
	if model == nil then
		return
	end
	model:SetAttribute(Attributes.OwnerUserId, if player then player.UserId else 0)
	model:SetAttribute(Attributes.OwnerName, if player then player.DisplayName else "")
	model:SetAttribute(Attributes.EggRarity, rarity or "")
	model:SetAttribute(Attributes.EndsAt, endsAt or 0)
	model:SetAttribute(Attributes.HatchedSpecies, "")
	local egg = model:FindFirstChild("Egg")
	if egg and egg:IsA("BasePart") then
		egg.Transparency = if player then 0 else 1
		local info = if rarity then PetConfig.RarityInfo[rarity] else nil
		if info then
			egg.Color = info.Color
		end
	end
	local console = model:FindFirstChild("Console")
	local prompt = if console then console:FindFirstChild(IncubatorBuilder.PROMPT_NAME) else nil
	if prompt and prompt:IsA("ProximityPrompt") then
		-- A busy incubator offers nothing: nobody can touch another player's egg.
		prompt.Enabled = player == nil
	end
end

local function isFree(index: number): boolean
	return occupants[index] == nil and os.clock() >= (busyUntil[index] or 0)
end

-- Puts the player's egg on show, preferring `preferred`. Returns the index.
local function occupy(player: Player, incubation: PetRules.Incubation, preferred: number?): number?
	local chosen: number? = nil
	if preferred and incubatorModel(preferred) and isFree(preferred) then
		chosen = preferred
	else
		for index in PetConfig.Incubators do
			if isFree(index) then
				chosen = index
				break
			end
		end
	end
	if chosen == nil then
		return nil
	end
	occupants[chosen] = player
	shownAt[player] = chosen
	ProgressService.setIncubatorShown(player.UserId, chosen)
	display(chosen, player, incubation.Rarity, incubation.EndsAt)
	return chosen
end

local function release(player: Player): ()
	local index = shownAt[player]
	shownAt[player] = nil
	ProgressService.setIncubatorShown(player.UserId, nil)
	if index and occupants[index] == player then
		occupants[index] = nil
		display(index, nil, nil, nil)
	end
end

local hatch: (player: Player) -> ()

local function scheduleHatch(player: Player, endsAt: number): ()
	task.delay(math.max(0, endsAt - os.time()) + 0.05, hatch, player)
end

local function petHistory(player: Player, action: string, text: string): ()
	HistoryService.record(player.UserId, "Pet", action, text)
end

local function equip(player: Player, data: PlayerDataService.PlayerData, petId: string): ()
	data.EquippedPetId = petId
	publishPet(player, data)
end

-- Moves a finished egg's pet into the player's pets. Idempotent: does
-- nothing without a finished incubation, and never yields between reading
-- and clearing it, so a pet can only be created once.
function hatch(player: Player): ()
	local data = PlayerDataService.get(player)
	local incubation = if data then data.Incubation else nil
	if data == nil or incubation == nil or player.Parent ~= Players then
		return
	end
	if os.time() < incubation.EndsAt then
		scheduleHatch(player, incubation.EndsAt) -- woke early (clock rounding)
		return
	end
	local petId = PetRules.petId(data.NextPetNumber)
	data.NextPetNumber += 1
	local draft = incubation.Pet
	data.Pets[petId] = {
		Species = draft.Species,
		Rarity = draft.Rarity,
		Buffs = draft.Buffs,
		CreatedAt = os.time(),
	}
	data.Incubation = nil
	local autoEquipped = data.EquippedPetId == ""
	if autoEquipped then
		equip(player, data, petId)
	end

	-- The incubator plays the hatch, then frees up.
	local index = shownAt[player]
	shownAt[player] = nil
	ProgressService.setIncubatorShown(player.UserId, nil)
	if index and occupants[index] == player then
		occupants[index] = nil
		busyUntil[index] = os.clock() + HATCH_SHOW_SECONDS
		local model = incubatorModel(index)
		if model then
			model:SetAttribute(Attributes.HatchedSpecies, draft.Species)
		end
		task.delay(HATCH_SHOW_SECONDS, function()
			if occupants[index] == nil then
				display(index, nil, nil, nil)
			end
		end)
	end

	print(
		string.format(
			"[Pet] %s (%d) hatched %s %s",
			player.Name,
			player.UserId,
			draft.Rarity,
			draft.Species
		)
	)
	petHistory(
		player,
		"Hatch",
		string.format("Hatched %s (%s) %s", PetRules.title(draft.Species), draft.Rarity, petId)
	)
	PetRemotes.Hatched:FireClient(player, {
		PetId = petId,
		Species = draft.Species,
		Rarity = draft.Rarity,
		Buffs = draft.Buffs,
		Equipped = autoEquipped,
	})
	ProgressService.sync(player)
end

-- The player's root position, or nil.
local function rootPosition(player: Player): Vector3?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function nearestFreeIncubator(player: Player): number?
	local position = rootPosition(player)
	if position == nil then
		return nil
	end
	local best: number? = nil
	local bestDistance = PetConfig.IncubatorReach
	for index, ground in PetConfig.Incubators do
		local distance = (ground - position).Magnitude
		if isFree(index) and distance <= bestDistance then
			best, bestDistance = index, distance
		end
	end
	return best
end

-- Starts incubating one `eggKey` from the Bag in incubator `index` (or the
-- nearest free one within reach). Never yields.
local function startIncubation(player: Player, eggKey: string, index: number?): ()
	local data = PlayerDataService.get(player)
	if data == nil then
		return
	end
	local rarity = PetRules.eggRarity(eggKey)
	if rarity == nil then
		return
	end
	if (data.Bag[eggKey] or 0) < 1 then
		ProgressService.sync(player) -- the UI was out of date
		return
	end
	if data.Incubation then
		return toast(
			player,
			string.format(
				"Your %s is still incubating. One egg at a time!",
				rarityLabel(data.Incubation.Rarity)
			)
		)
	end
	if countPets(data) >= PetConfig.MaxPets then
		return toast(
			player,
			string.format("You have the most pets you can keep (%d).", PetConfig.MaxPets)
		)
	end

	local chosen = index
	if chosen then
		local position = rootPosition(player)
		local ground = PetConfig.Incubators[chosen]
		if position == nil or (ground - position).Magnitude > PetConfig.IncubatorReach then
			return toast(player, "Walk up to the incubator first.")
		end
		if not isFree(chosen) then
			return toast(player, "That incubator is busy. Try another one!")
		end
	else
		chosen = nearestFreeIncubator(player)
		if chosen == nil then
			return toast(
				player,
				"Take your egg to a free Incubator at the Pet Incubation Center (outside, east of the plaza)."
			)
		end
	end

	local draft = PetRules.roll(rarity, rollRandom)
	if draft == nil or not BagRules.take(data.Bag, eggKey) then
		return
	end
	local now = os.time()
	local incubation: PetRules.Incubation = {
		EggKey = eggKey,
		Rarity = rarity,
		StartedAt = now,
		EndsAt = now + PetConfig.IncubationSeconds,
		IncubatorIndex = chosen :: number,
		Pet = draft,
	}
	data.Incubation = incubation
	HistoryService.record(
		player.UserId,
		"Egg",
		"Incubate",
		rarityLabel(rarity) .. " put in an incubator"
	)
	occupy(player, incubation, chosen)
	scheduleHatch(player, incubation.EndsAt)
	ProgressService.sync(player)
	toast(
		player,
		string.format(
			"Your %s is incubating! It hatches in %d s, even if you walk away.",
			rarityLabel(rarity),
			PetConfig.IncubationSeconds
		)
	)
end

-- Egg keys the player has in their Bag, rarest first.
local function eggsInBag(data: PlayerDataService.PlayerData): { string }
	local keys: { string } = {}
	for index = #PetConfig.Rarities, 1, -1 do
		local key = PetConfig.EggKeys[PetConfig.Rarities[index]]
		if key and (data.Bag[key] or 0) > 0 then
			table.insert(keys, key)
		end
	end
	return keys
end

local function onIncubatorPrompt(player: Player, index: number): ()
	local data = PlayerDataService.get(player)
	if data == nil then
		return
	end
	local eggs = eggsInBag(data)
	if #eggs == 0 then
		return toast(player, "You have no eggs. Buy one in the Store or find one outside!")
	end
	if #eggs == 1 or data.Incubation ~= nil then
		return startIncubation(player, eggs[1], index)
	end
	-- Several kinds: let the player pick (they answer with Pets.Incubate).
	PetRemotes.ChooseEgg:FireClient(player, index, eggs)
end

local function onIncubate(player: Player, rawKey: unknown, rawIndex: unknown): ()
	local key = Validate.id(rawKey, RemoteLimits.MaxIdLength)
	local product = if key then StoreConfig.ByKey[key] else nil
	if key == nil or product == nil or product.Kind ~= "Egg" then
		return RemoteController.reject(player, "Pets.Incubate", "not an egg")
	end
	local index: number? = nil
	if rawIndex ~= nil then
		index = Validate.integer(rawIndex, 1, #PetConfig.Incubators)
		if index == nil then
			return RemoteController.reject(player, "Pets.Incubate", "bad incubator")
		end
	end
	startIncubation(player, key, index)
end

-- Gives a player a new pet of `speciesId` (an admin's reward): its buffs are
-- rolled now like a hatched pet's. Never yields. Returns (ok, message).
function PetService.grantPet(player: Player, speciesId: string): (boolean, string)
	local data = PlayerDataService.get(player)
	local species = PetConfig.ById[speciesId]
	if data == nil or species == nil then
		return false, "Unknown pet or player data not loaded."
	end
	if countPets(data) >= PetConfig.MaxPets then
		return false,
			string.format(
				"%s already has the most pets (%d).",
				player.DisplayName,
				PetConfig.MaxPets
			)
	end
	local draft = PetRules.draftFor(species, rollRandom)
	local petId = PetRules.petId(data.NextPetNumber)
	data.NextPetNumber += 1
	data.Pets[petId] = {
		Species = draft.Species,
		Rarity = draft.Rarity,
		Buffs = draft.Buffs,
		CreatedAt = os.time(),
	}
	if data.EquippedPetId == "" then
		equip(player, data, petId)
	end
	ProgressService.sync(player)
	return true, string.format("%s %s", PetRules.title(species.Id), petId)
end

-- Uses an egg from the Bag (BagService): the nearest free incubator in reach.
function PetService.incubateFromBag(player: Player, eggKey: string): ()
	startIncubation(player, eggKey, nil)
end

-- Equip ----------------------------------------------------------------------

local function onEquip(player: Player, rawId: unknown): ()
	local data = PlayerDataService.get(player)
	if data == nil then
		return
	end
	if rawId == "" then
		equip(player, data, "")
		ProgressService.sync(player)
		petHistory(player, "Unequip", "Put the pet away")
		return toast(player, "Your pet is resting.")
	end
	local petId = Validate.id(rawId, RemoteLimits.MaxIdLength)
	if petId == nil or not PetRules.isPetId(petId) then
		return RemoteController.reject(player, "Pets.Equip", "bad pet id")
	end
	local pet = data.Pets[petId]
	if pet == nil then
		ProgressService.sync(player) -- not theirs (or the UI was out of date)
		return
	end
	if data.EquippedPetId ~= petId then
		-- The previous pet stays owned; only one follows and gives buffs.
		equip(player, data, petId)
		toast(player, PetRules.title(pet.Species) .. " is following you!")
		petHistory(player, "Equip", "Equipped " .. PetRules.title(pet.Species) .. " " .. petId)
	end
	ProgressService.sync(player)
end

-- World eggs -----------------------------------------------------------------

-- Eggs out from the schedule and admins (`eventId` nil), or from one hunt.
local function worldEggCount(eventId: string?): number
	local count = 0
	for _, entry in worldEggs do
		if entry.EventId == eventId then
			count += 1
		end
	end
	return count
end

local function claimWorldEgg(player: Player, eggId: string): ()
	local entry = worldEggs[eggId]
	if entry == nil or entry.Claimed then
		return
	end
	local data = PlayerDataService.get(player)
	if data == nil then
		return toast(player, "Your progress is still loading. Try again in a moment.")
	end
	local position = rootPosition(player)
	local eggPosition = entry.Model:GetPivot().Position
	if position == nil or (position - eggPosition).Magnitude > CLAIM_REACH then
		return
	end
	local key = PetConfig.EggKeys[entry.Rarity]
	if key == nil then
		return
	end
	-- Claimed first, in the same step as the grant: only one player gets it.
	entry.Claimed = true
	worldEggs[eggId] = nil
	entry.Model:Destroy()
	BagRules.add(data.Bag, key, 1)
	HistoryService.record(
		player.UserId,
		"Egg",
		"Found",
		"Found a " .. rarityLabel(entry.Rarity) .. " outside"
	)
	ProgressService.sync(player)
	print(
		string.format(
			"[Pet] %s (%d) claimed a %s world egg",
			player.Name,
			player.UserId,
			entry.Rarity
		)
	)
	toast(
		player,
		string.format(
			"You found a %s! It's in your Bag: take it to an Incubator.",
			rarityLabel(entry.Rarity)
		)
	)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			toast(
				other,
				string.format("%s found the %s!", player.DisplayName, rarityLabel(entry.Rarity))
			)
		end
	end
end

-- Where an egg rests at a spawn spot: just above the real ground there.
-- The terrain's surface isn't exactly where the config says (smooth terrain
-- rounds to its 4-stud grid), so a fixed height could leave the egg inside
-- the ground with only its prompt showing.
local function restingPosition(point: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = {}
	for _, name in { "PetCenter", "Bosses", "ClientPets" } do
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
	params.FilterDescendantsInstances = skip
	params.IgnoreWater = true
	local hit = Workspace:Raycast(point + Vector3.new(0, 30, 0), Vector3.new(0, -60, 0), params)
	local groundY = if hit then hit.Position.Y else point.Y - 1
	return Vector3.new(
		point.X,
		groundY + PetConfig.WorldEggSize.Y / 2 + PetConfig.WorldEggHover,
		point.Z
	)
end

local function buildWorldEgg(
	eggId: string,
	rarity: string,
	position: Vector3,
	parent: Instance
): Model
	local model = Instance.new("Model")
	model.Name = "WorldEgg"
	model:SetAttribute(Attributes.WorldEggRarity, rarity)
	local info = PetConfig.RarityInfo[rarity]
	local color = if info then info.Color else Color3.new(1, 1, 1)
	local egg = Instance.new("Part")
	egg.Name = "Egg"
	egg.Anchored = true
	egg.CanCollide = false
	egg.CanTouch = false
	egg.Size = PetConfig.WorldEggSize
	egg.CFrame = CFrame.new(restingPosition(position))
	egg.Material = Enum.Material.SmoothPlastic
	egg.Color = color
	egg.Parent = model
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = egg
	-- A soft outline so it stands out from grass and paths (hidden by walls,
	-- so it doesn't give the spot away from afar). No lights.
	local outline = Instance.new("Highlight")
	outline.FillColor = color
	outline.FillTransparency = 0.7
	outline.OutlineColor = Color3.new(1, 1, 1)
	outline.OutlineTransparency = 0.15
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Adornee = egg
	outline.Parent = model
	-- A few sparkles on every egg, a few more for rarer ones.
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Rate = if rarity == "Mythical" then 6 elseif rarity == "Rare" then 4 else 3
	sparkles.Lifetime = NumberRange.new(0.8, 1.2)
	sparkles.Speed = NumberRange.new(0.5, 1)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Size = NumberSequence.new(0.3, 0)
	sparkles.LightEmission = 0.4
	sparkles.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	sparkles.Parent = egg
	-- A small 🥚 marker above it, only once you're fairly close.
	local marker = Instance.new("BillboardGui")
	marker.Name = "Marker"
	marker.Size = UDim2.fromScale(2.2, 2.2) -- studs
	marker.StudsOffset = Vector3.new(0, PetConfig.WorldEggSize.Y / 2 + 1.6, 0)
	marker.MaxDistance = PetConfig.WorldEggMarkerDistance
	marker.LightInfluence = 0
	marker.Parent = egg
	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(1, 1)
	icon.TextScaled = true
	icon.Text = "🥚"
	icon.Parent = marker
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Claim Egg"
	prompt.ObjectText = rarityLabel(rarity)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = egg
	prompt.Triggered:Connect(function(player: Player)
		claimWorldEgg(player, eggId)
	end)
	model.PrimaryPart = egg
	model.Parent = parent
	return model
end

-- Places a world egg of `rarity` at a free safe spot and tells everyone in
-- this server (not where). An egg hunt's eggs (`eventId`) are announced once
-- by the hunt's own start notice, not one by one. Returns (ok, message).
function PetService.spawnWorldEgg(rarity: string, eventId: string?): (boolean, string)
	local current = built
	if current == nil or PetConfig.EggKeys[rarity] == nil then
		return false, "Egg spawning isn't ready."
	end
	if eventId == nil and worldEggCount(nil) >= PetConfig.MaxWorldEggs then
		return false, string.format("There are already %d eggs out there.", PetConfig.MaxWorldEggs)
	end
	local taken: { [number]: boolean } = {}
	for _, entry in worldEggs do
		taken[entry.Point] = true
	end
	local free: { number } = {}
	for index in PetConfig.WorldEggSpawnPoints do
		if not taken[index] then
			table.insert(free, index)
		end
	end
	if #free == 0 then
		return false, "No free egg spot."
	end
	local point = free[rollRandom:NextInteger(1, #free)]
	nextEggNumber += 1
	local eggId = "egg" .. nextEggNumber
	local model =
		buildWorldEgg(eggId, rarity, PetConfig.WorldEggSpawnPoints[point], current.WorldEggs)
	worldEggs[eggId] =
		{ Model = model, Rarity = rarity, Claimed = false, Point = point, EventId = eventId }
	print(string.format("[Pet] a %s world egg appeared at spot %d", rarity, point))
	if eventId then
		return true, "Hunt egg placed."
	end
	AnnouncementRemote:FireAllClients({
		Title = "🥚 NEW EGG FOUND!",
		Text = string.format(
			"A %s has appeared somewhere outside the office! Find it and take it to an Incubator!",
			rarityLabel(rarity)
		),
		Seconds = WORLD_EGG_ANNOUNCE_SECONDS,
	})
	return true, string.format("A %s appeared at a random spot outside.", rarityLabel(rarity))
end

-- When the next scheduled world egg is due (unix seconds), and how many are out.
function PetService.worldEggStatus(): (number, number)
	return nextWorldEggAt, worldEggCount(nil)
end

-- Egg hunts (docs/PETS.md "Egg hunts"): one thread per running hunt, waking
-- once per interval; it stops when the hunt ends, and the hunt's unclaimed
-- eggs are removed then.
local huntRunners: { [string]: string } = {} -- event id -> settings it runs with

local function runHunt(hunt: EventRules.EggHunt, signature: string): ()
	while huntRunners[hunt.EventId] == signature do
		if worldEggCount(hunt.EventId) < hunt.MaxEggs then
			PetService.spawnWorldEgg(hunt.Rarity, hunt.EventId)
		end
		task.wait(hunt.IntervalSeconds)
	end
end

local function syncHunts(): ()
	local running: { [string]: boolean } = {}
	for _, hunt in EventService.eggHunts() do
		running[hunt.EventId] = true
		local signature = string.format("%s|%d|%d", hunt.Rarity, hunt.IntervalSeconds, hunt.MaxEggs)
		if huntRunners[hunt.EventId] ~= signature then
			huntRunners[hunt.EventId] = signature -- (re)start with the new settings
			task.spawn(runHunt, hunt, signature)
		end
	end
	for eventId in huntRunners do
		if not running[eventId] then
			huntRunners[eventId] = nil
			for eggId, entry in worldEggs do
				if entry.EventId == eventId and not entry.Claimed then
					worldEggs[eggId] = nil
					entry.Model:Destroy()
				end
			end
		end
	end
end

local function nextBoundary(now: number): number
	local interval = PetConfig.WorldEggIntervalSeconds
	return (math.floor(now / interval) + 1) * interval
end

-- Players --------------------------------------------------------------------

local function onLoaded(player: Player, data: PlayerDataService.PlayerData): ()
	publishPet(player, data)
	local incubation = data.Incubation
	if incubation == nil then
		return
	end
	if os.time() >= incubation.EndsAt then
		hatch(player) -- finished while they were away (or the server restarted)
	else
		occupy(player, incubation, incubation.IncubatorIndex)
		scheduleHatch(player, incubation.EndsAt)
		ProgressService.sync(player)
	end
end

function PetService.init(): ()
	local current = IncubatorBuilder.build(Workspace)
	built = current
	for index, model in current.Incubators do
		display(index, nil, nil, nil)
		local console = model:FindFirstChild("Console")
		local prompt = if console then console:FindFirstChild(IncubatorBuilder.PROMPT_NAME) else nil
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Triggered:Connect(function(player: Player)
				onIncubatorPrompt(player, index)
			end)
		end
	end

	RemoteController.bind(PetRemotes.Equip, {
		name = "Pets.Equip",
		maxArgs = 1,
		rateLimit = RemoteLimits.Shop,
	}, onEquip)
	RemoteController.bind(PetRemotes.Incubate, {
		name = "Pets.Incubate",
		maxArgs = 2,
		rateLimit = RemoteLimits.Shop,
	}, onIncubate)

	Players.PlayerRemoving:Connect(release)
	PlayerDataService.onLoaded(onLoaded)
	EventService.onChanged(syncHunts)
end

function PetService.start(): ()
	syncHunts()
	-- One wait per interval: the next egg is due on the UTC clock, so every
	-- server agrees and a restarted server just waits for the next one.
	while true do
		nextWorldEggAt = nextBoundary(os.time())
		task.wait(math.max(1, nextWorldEggAt - os.time()))
		if worldEggCount(nil) == 0 then
			PetService.spawnWorldEgg(PetRules.pickWorldEggRarity(rollRandom:NextNumber()))
		end
	end
end

return PetService
