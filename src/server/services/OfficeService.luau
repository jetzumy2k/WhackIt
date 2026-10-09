--!strict
--[[
	Personal offices (docs/OFFICES.md, docs/REMOTE_CONTRACTS.md "Office").

	  * The Office Wing has one room per player place in the server
	    (Players.MaxPlayers, at most OfficeConfig.MaxSlots), built at start
	    (Lib/OfficeWingBuilder). A player whose data loads gets the first free
	    room, filled from their saved layout; leaving clears and frees it.
	  * Office.Go (own office or another player's) and Office.Return teleport
	    the player (MovementGuardService.noteTeleport first). The door's
	    "Back to lobby" prompt returns too.
	  * Office.Place / Move / Remove edit the layout. The server checks the
	    item, position, rotation, ownership, the 60-item cap and that the
	    player stands in their own room (Shared/FurnitureRules), then saves and
	    redraws the room. The client only ever names an item key and numbers.
	  * Office.SetPrivacy: Public, Friends or Private. Visits are checked when
	    they start, and a guard (every OfficeConfig.GuardInterval) sends anyone
	    who may no longer be in a room (privacy changed, owner left) to the
	    lobby. Friendship is asked from Roblox once per pair and cached.
	  * Office.Directory (server -> all): who has an office and its privacy,
	    re-sent when anyone's office or privacy changes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)
local FurnitureModel = require(ReplicatedStorage.Shared.FurnitureModel)
local FurnitureRules = require(ReplicatedStorage.Shared.FurnitureRules)
local LevelRewardRules = require(ReplicatedStorage.Shared.LevelRewardRules)
local LevelRules = require(ReplicatedStorage.Shared.LevelRules)
local MovementGuardService = require(script.Parent.MovementGuardService)
local OfficeConfig = require(ReplicatedStorage.Config.OfficeConfig)
local OfficeWingBuilder = require(ServerScriptService.Lib.OfficeWingBuilder)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressService = require(script.Parent.ProgressService)
local RemoteController = require(ServerScriptService.Controllers.RemoteController)
local RemoteLimits = require(ServerScriptService.Config.RemoteLimits)
local Validate = require(ReplicatedStorage.Shared.Validate)

local OfficeRemotes = ReplicatedStorage.Remotes.Office
local ToastRemote = ReplicatedStorage.Remotes.Notify.Toast

export type DirectoryEntry = {
	UserId: number,
	Name: string,
	Username: string,
	Privacy: string,
	Slot: number,
}

local OfficeService = {}

-- Placed furniture carries its layout entry id, so the client can select it.
OfficeService.ITEM_ID_ATTRIBUTE = "OfficeItemId"
OfficeService.OWNER_ATTRIBUTE = "OfficeOwner"

local PROMPT_DISTANCE = 10
local MAX_USER_ID = 2 ^ 53

local rooms: { OfficeWingBuilder.Room } = {}
local ownerOf: { [number]: Player } = {} -- slot -> owner
local slotOf: { [Player]: number } = {}
-- "smallerId:largerId" -> are they Roblox friends (asked once per pair).
local friends: { [string]: boolean } = {}
local templates: { [string]: Model } = {}
-- Players the guard is already sending to the lobby (a teleport may wait
-- for streaming), so one slow trip isn't started again every tick.
local evicting: { [Player]: boolean } = {}

local function toast(player: Player, text: string): ()
	ToastRemote:FireClient(player, text)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function roomAt(player: Player): number?
	local root = rootOf(player)
	return if root then FurnitureRules.slotAt(root.Position, #rooms) else nil
end

-- Friendship --------------------------------------------------------------------

local function pairKey(a: Player, b: Player): string
	local low, high = math.min(a.UserId, b.UserId), math.max(a.UserId, b.UserId)
	return low .. ":" .. high
end

-- Asks Roblox (yields) the first time, then answers from the cache.
local function areFriends(a: Player, b: Player): boolean
	local key = pairKey(a, b)
	local known = friends[key]
	if known ~= nil then
		return known
	end
	local ok, result = pcall(function(): boolean
		return a:IsFriendsWithAsync(b.UserId)
	end)
	-- A failed lookup counts as "not friends" for now and is asked again later.
	if ok then
		friends[key] = result == true
	end
	return ok and result == true
end

-- Whether `visitor` may be in room `index`. With `canYield` false, an
-- unknown friendship is looked up in the background and allowed meanwhile.
local function mayBeIn(visitor: Player, index: number, canYield: boolean): boolean
	local owner: Player? = ownerOf[index]
	if owner == nil then
		return false -- vacant room
	end
	local data = PlayerDataService.get(owner)
	local privacy = if data then data.OfficePrivacy else "Private"
	if visitor == owner or privacy == "Public" then
		return true
	end
	if privacy ~= "Friends" then
		return false
	end
	if canYield then
		return areFriends(visitor, owner)
	end
	local known = friends[pairKey(visitor, owner)]
	if known == nil then
		task.spawn(areFriends, visitor, owner)
		return true
	end
	return known
end

-- Teleports -----------------------------------------------------------------------

local function teleport(player: Player, target: CFrame): ()
	local character = player.Character
	if character == nil then
		return
	end
	-- With instance streaming on, load the destination first (no-op otherwise).
	pcall(function()
		player:RequestStreamAroundAsync(target.Position, 5)
	end)
	if player.Character ~= character or character.Parent == nil then
		return -- respawned or left while loading
	end
	MovementGuardService.noteTeleport(player)
	character:PivotTo(target)
end

local function arrival(index: number): CFrame
	local position = rooms[index].Floor * OfficeConfig.Arrival
	return CFrame.lookAt(position, position + Vector3.new(0, 0, -1))
end

local function lobby(): CFrame
	local position = ArenaConfig.SpawnPosition + Vector3.new(0, 3, 0)
	return CFrame.lookAt(position, position + Vector3.new(0, 0, 1))
end

-- Rooms and the directory ------------------------------------------------------

local function template(key: string): Model?
	local cached = templates[key]
	if cached then
		return cached
	end
	local item = FurnitureConfig.ByKey[key]
	if item == nil then
		return nil
	end
	local built = FurnitureModel.build(item)
	templates[key] = built
	return built
end

local function render(player: Player): ()
	local index = slotOf[player]
	local data = PlayerDataService.get(player)
	if index == nil or data == nil then
		return
	end
	local room = rooms[index]
	room.Furniture:ClearAllChildren()
	for _, entry in data.OfficeLayout do
		local source = template(entry.Item)
		if source then
			local clone = source:Clone()
			clone:SetAttribute(OfficeService.ITEM_ID_ATTRIBUTE, entry.Id)
			clone:PivotTo(FurnitureModel.placement(room.Floor, entry.X, entry.Z, entry.R))
			clone.Parent = room.Furniture
		end
	end
end

-- Paints the player's room in their office theme (a level reward, shown
-- only while their level unlocks it; the default look otherwise).
function OfficeService.applyTheme(player: Player): ()
	local index = slotOf[player]
	local data = PlayerDataService.get(player)
	if index == nil or data == nil then
		return
	end
	local id =
		LevelRewardRules.effective("Office", data.Cosmetics.Office, LevelRules.levelFor(data.Xp))
	local theme = if id ~= "" then LevelRewardRules.cosmetic("Office", id) else nil
	OfficeWingBuilder.paint(
		rooms[index],
		if theme then theme.Color else OfficeWingBuilder.DEFAULT_WALL,
		if theme and theme.Floor then theme.Floor else OfficeWingBuilder.DEFAULT_FLOOR
	)
end

function OfficeService.directory(): { [string]: any }
	local offices: { DirectoryEntry } = {}
	for index, owner in ownerOf do
		local data = PlayerDataService.get(owner)
		table.insert(offices, {
			UserId = owner.UserId,
			Name = owner.DisplayName,
			Username = owner.Name,
			Privacy = if data then data.OfficePrivacy else "Private",
			Slot = index,
		})
	end
	table.sort(offices, function(a, b)
		return a.Name:lower() < b.Name:lower()
	end)
	return { SlotCount = #rooms, Offices = offices }
end

local function broadcast(): ()
	OfficeRemotes.Directory:FireAllClients(OfficeService.directory())
end

local function assign(player: Player): ()
	if slotOf[player] or player.Parent ~= Players then
		return
	end
	for index in rooms do
		local current: Player? = ownerOf[index]
		if current == nil then
			ownerOf[index] = player
			slotOf[player] = index
			local room = rooms[index]
			room.Nameplate.Text = player.DisplayName .. "'s Office"
			room.Model:SetAttribute(OfficeService.OWNER_ATTRIBUTE, player.UserId)
			render(player)
			OfficeService.applyTheme(player)
			broadcast()
			return
		end
	end
	warn(string.format("[Office] no free room for %s (%d rooms)", player.Name, #rooms))
	toast(player, "No office is free in this server right now.")
end

local function release(player: Player): ()
	local index = slotOf[player]
	slotOf[player] = nil
	evicting[player] = nil
	for key in friends do
		local low, high = string.match(key, "^(%d+):(%d+)$")
		if tonumber(low) == player.UserId or tonumber(high) == player.UserId then
			friends[key] = nil
		end
	end
	if index == nil then
		return
	end
	ownerOf[index] = nil
	local room = rooms[index]
	room.Furniture:ClearAllChildren()
	room.Nameplate.Text = "Vacant Office"
	OfficeWingBuilder.paint(room, OfficeWingBuilder.DEFAULT_WALL, OfficeWingBuilder.DEFAULT_FLOOR)
	room.Model:SetAttribute(OfficeService.OWNER_ATTRIBUTE, nil)
	broadcast()
end

-- Remote handlers -----------------------------------------------------------------

local function onGo(player: Player, rawTarget: unknown): ()
	local target = player
	if rawTarget ~= nil then
		local userId = Validate.integer(rawTarget, 1, MAX_USER_ID)
		if userId == nil then
			return RemoteController.reject(player, "Office.Go", "bad userId")
		end
		target = Players:GetPlayerByUserId(userId) or player
		if target.UserId ~= userId then
			return toast(player, "That player has left the server.")
		end
	end
	local index = slotOf[target]
	if index == nil then
		return toast(player, "That office isn't ready yet.")
	end
	if not mayBeIn(player, index, true) then
		local data = PlayerDataService.get(target)
		local friendsOnly = data ~= nil and data.OfficePrivacy == "Friends"
		return toast(
			player,
			string.format(
				"%s's office is %s.",
				target.DisplayName,
				if friendsOnly then "for friends only" else "private"
			)
		)
	end
	teleport(player, arrival(index))
end

local function onReturn(player: Player): ()
	if roomAt(player) then
		teleport(player, lobby())
	end
end

-- The player's data, if they stand in their own room; otherwise a toast.
local function editableData(player: Player): PlayerDataService.PlayerData?
	local data = PlayerDataService.get(player)
	if data == nil then
		return nil
	end
	local index = slotOf[player]
	if index == nil or roomAt(player) ~= index then
		toast(player, "Go to your office to change its furniture.")
		return nil
	end
	return data
end

local function readSpot(
	player: Player,
	remoteName: string,
	rawX: unknown,
	rawZ: unknown,
	rawR: unknown
): (number?, number?, number?)
	local limit = FurnitureRules.MAX_COORDINATE
	local x = Validate.integer(rawX, -limit, limit)
	local z = Validate.integer(rawZ, -limit, limit)
	local r = if FurnitureRules.isRotation(rawR) then rawR :: number else nil
	if x == nil or z == nil or r == nil then
		RemoteController.reject(player, remoteName, "bad position or rotation")
		return nil, nil, nil
	end
	return x, z, r
end

local function changed(player: Player): ()
	render(player)
	ProgressService.sync(player)
end

local function onPlace(
	player: Player,
	rawKey: unknown,
	rawX: unknown,
	rawZ: unknown,
	rawR: unknown
): ()
	local key = Validate.id(rawKey, RemoteLimits.MaxIdLength)
	if key == nil or FurnitureConfig.ByKey[key] == nil then
		return RemoteController.reject(player, "Office.Place", "unknown item")
	end
	local x, z, r = readSpot(player, "Office.Place", rawX, rawZ, rawR)
	if x == nil or z == nil or r == nil then
		return
	end
	local data = editableData(player)
	if data == nil then
		return
	end
	local ok, reason = FurnitureRules.check(
		data.OfficeLayout,
		data.Furniture,
		key,
		x,
		z,
		r,
		nil,
		LevelRules.levelFor(data.Xp)
	)
	if not ok then
		toast(player, reason or "You can't put that there.")
		return ProgressService.sync(player)
	end
	table.insert(data.OfficeLayout, { Id = data.NextOfficeItemId, Item = key, X = x, Z = z, R = r })
	data.NextOfficeItemId += 1
	changed(player)
end

local function readId(player: Player, remoteName: string, raw: unknown): number?
	local id = Validate.integer(raw, 1, 2 ^ 31)
	if id == nil then
		RemoteController.reject(player, remoteName, "bad item id")
	end
	return id
end

local function onMove(
	player: Player,
	rawId: unknown,
	rawX: unknown,
	rawZ: unknown,
	rawR: unknown
): ()
	local id = readId(player, "Office.Move", rawId)
	local x, z, r = readSpot(player, "Office.Move", rawX, rawZ, rawR)
	if id == nil or x == nil or z == nil or r == nil then
		return
	end
	local data = editableData(player)
	if data == nil then
		return
	end
	local entry = FurnitureRules.find(data.OfficeLayout, id)
	if entry == nil then
		return ProgressService.sync(player) -- already removed: just redraw
	end
	local ok, reason =
		FurnitureRules.check(data.OfficeLayout, data.Furniture, entry.Item, x, z, r, id)
	if not ok then
		toast(player, reason or "You can't put that there.")
		return ProgressService.sync(player)
	end
	entry.X, entry.Z, entry.R = x, z, r
	changed(player)
end

local function onRemove(player: Player, rawId: unknown): ()
	local id = readId(player, "Office.RemoveItem", rawId)
	if id == nil then
		return
	end
	local data = editableData(player)
	if data == nil then
		return
	end
	local _, index = FurnitureRules.find(data.OfficeLayout, id)
	if index then
		table.remove(data.OfficeLayout, index)
	end
	changed(player)
end

local function onSetPrivacy(player: Player, raw: unknown): ()
	if not FurnitureRules.isPrivacy(raw) then
		return RemoteController.reject(player, "Office.SetPrivacy", "unknown privacy")
	end
	local data = PlayerDataService.get(player)
	if data == nil then
		return
	end
	data.OfficePrivacy = raw :: string
	ProgressService.sync(player)
	broadcast()
end

-- Admin rewards (AdminService): adds Special furniture to the player's
-- inventory. Returns false if the item isn't Special or data isn't loaded.
function OfficeService.grantSpecial(player: Player, key: string, amount: number): (boolean, string)
	local data = PlayerDataService.get(player)
	if data == nil then
		return false, "That player's data is still loading."
	end
	if not FurnitureRules.grantSpecial(data.Furniture, key, amount) then
		return false, "That isn't a special furniture item."
	end
	return true, ""
end

-- Guard -----------------------------------------------------------------------------

local function guardTick(): ()
	for _, player in Players:GetPlayers() do
		local index = roomAt(player)
		if index and not evicting[player] and not mayBeIn(player, index, false) then
			evicting[player] = true
			task.spawn(function()
				teleport(player, lobby())
				toast(player, "That office is closed to visitors now.")
				evicting[player] = nil
			end)
		end
	end
end

local function addDoorPrompt(room: OfficeWingBuilder.Room): ()
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "Office door"
	prompt.ActionText = "Back to lobby"
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = room.Door
	prompt.Triggered:Connect(function(player: Player)
		teleport(player, lobby())
	end)
end

function OfficeService.init(): ()
	RemoteController.bind(OfficeRemotes.Place, {
		name = "Office.Place",
		maxArgs = 4,
		rateLimit = RemoteLimits.Office,
	}, onPlace)
	RemoteController.bind(OfficeRemotes.Move, {
		name = "Office.Move",
		maxArgs = 4,
		rateLimit = RemoteLimits.Office,
	}, onMove)
	RemoteController.bind(OfficeRemotes.RemoveItem, {
		name = "Office.RemoveItem",
		maxArgs = 1,
		rateLimit = RemoteLimits.Office,
	}, onRemove)
	RemoteController.bind(OfficeRemotes.SetPrivacy, {
		name = "Office.SetPrivacy",
		maxArgs = 1,
		rateLimit = RemoteLimits.OfficeTravel,
	}, onSetPrivacy)
	RemoteController.bind(OfficeRemotes.Go, {
		name = "Office.Go",
		maxArgs = 1,
		rateLimit = RemoteLimits.OfficeTravel,
	}, onGo)
	RemoteController.bind(OfficeRemotes.Return, {
		name = "Office.Return",
		maxArgs = 0,
		rateLimit = RemoteLimits.OfficeTravel,
	}, onReturn)
	Players.PlayerRemoving:Connect(release)
end

function OfficeService.start(): ()
	local wing = Instance.new("Folder")
	wing.Name = "OfficeWing"
	local count = math.clamp(Players.MaxPlayers, 1, OfficeConfig.MaxSlots)
	for index = 1, count do
		local room = OfficeWingBuilder.buildRoom(index, wing)
		room.Model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		addDoorPrompt(room)
		rooms[index] = room
	end
	wing.Parent = Workspace

	PlayerDataService.onLoaded(function(player: Player)
		assign(player)
		-- The newcomer needs the directory even if nothing else changed.
		OfficeRemotes.Directory:FireClient(player, OfficeService.directory())
	end)

	while true do
		task.wait(OfficeConfig.GuardInterval)
		guardTick()
	end
end

return OfficeService
