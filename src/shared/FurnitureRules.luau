--!strict
--[[
	Pure rules for personal offices (docs/OFFICES.md): where furniture may go,
	what a player may place, saved layouts and who may visit. The server
	decides with these (OfficeService); the client uses the same rules to
	colour its placement preview, so both always agree.

	Positions are room-local whole studs (Config/OfficeConfig): X and Z of the
	footprint's centre, rotation 0 / 90 / 180 / 270 degrees about Y. A 90 or
	270 turn swaps the footprint's width and depth.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)
local OfficeConfig = require(ReplicatedStorage.Config.OfficeConfig)

export type Entry = {
	Id: number, -- unique within the player's layout, never reused
	Item: string,
	X: number,
	Z: number,
	R: number,
}

export type Layout = { Entry }

-- Special items the player owns: key -> count (Basic items are unlimited).
export type Owned = { [string]: number }

export type Bounds = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }

local FurnitureRules = {}

local HALF = OfficeConfig.RoomSize / 2
-- Furthest a footprint edge may reach from the centre.
local LIMIT = HALF - OfficeConfig.WallMargin
-- A centre this far out can never be valid; requests beyond it are malformed.
FurnitureRules.MAX_COORDINATE = math.floor(HALF)

local function isWhole(value: unknown): boolean
	return typeof(value) == "number" and value == value and value == math.floor(value)
end

function FurnitureRules.isRotation(value: unknown): boolean
	return isWhole(value) and table.find(OfficeConfig.Rotations, value :: number) ~= nil
end

function FurnitureRules.footprint(
	item: FurnitureConfig.Item,
	x: number,
	z: number,
	r: number
): Bounds
	local turned = r == 90 or r == 270
	local width = if turned then item.Size.Z else item.Size.X
	local depth = if turned then item.Size.X else item.Size.Z
	return {
		MinX = x - width / 2,
		MaxX = x + width / 2,
		MinZ = z - depth / 2,
		MaxZ = z + depth / 2,
	}
end

-- Touching edges don't count as overlapping, so items can stand side by side.
local function overlaps(a: Bounds, b: Bounds): boolean
	return a.MinX < b.MaxX and b.MinX < a.MaxX and a.MinZ < b.MaxZ and b.MinZ < a.MaxZ
end

function FurnitureRules.isInsideRoom(bounds: Bounds): boolean
	return bounds.MinX >= -LIMIT
		and bounds.MaxX <= LIMIT
		and bounds.MinZ >= -LIMIT
		and bounds.MaxZ <= LIMIT
end

function FurnitureRules.blocksEntry(bounds: Bounds): boolean
	local zone = OfficeConfig.EntryZone
	return overlaps(
		bounds,
		{ MinX = zone.MinX, MaxX = zone.MaxX, MinZ = zone.MinZ, MaxZ = zone.MaxZ }
	)
end

function FurnitureRules.countPlaced(layout: Layout, key: string, ignoreId: number?): number
	local count = 0
	for _, entry in layout do
		if entry.Item == key and entry.Id ~= ignoreId then
			count += 1
		end
	end
	return count
end

-- How many more of `key` the player may place: math.huge for Basic items
-- and unlocked Level items, 0 for Level items above `level`. `level` nil =
-- don't check (loading a saved layout: earned furniture is kept).
function FurnitureRules.available(
	layout: Layout,
	owned: Owned,
	key: string,
	ignoreId: number?,
	level: number?
): number
	local item = FurnitureConfig.ByKey[key]
	if item == nil then
		return 0
	end
	if item.Tier == "Basic" then
		return math.huge
	end
	if item.Tier == "Level" then
		return if level == nil or level >= (item.MinLevel or 1) then math.huge else 0
	end
	return math.max(0, (owned[key] or 0) - FurnitureRules.countPlaced(layout, key, ignoreId))
end

--[[
	Can `key` stand at (x, z) turned `r`? `ignoreId` is the entry being moved
	(it doesn't block itself, count against the cap or use up ownership, and
	a placed Level item can always be moved). `level` is the player's level
	for placing Level items (nil = don't check). Returns true, or false and
	a short reason for the player.
]]
function FurnitureRules.check(
	layout: Layout,
	owned: Owned,
	key: string,
	x: number,
	z: number,
	r: number,
	ignoreId: number?,
	level: number?
): (boolean, string?)
	local item = FurnitureConfig.ByKey[key]
	if item == nil then
		return false, "That item doesn't exist."
	end
	if not (isWhole(x) and isWhole(z) and FurnitureRules.isRotation(r)) then
		return false, "Pick a spot on the floor."
	end
	if ignoreId == nil and #layout >= OfficeConfig.MaxItems then
		return false, string.format("Your office is full (%d items).", OfficeConfig.MaxItems)
	end
	if item.Tier == "Level" and ignoreId == nil and level and level < (item.MinLevel or 1) then
		return false,
			string.format("Reach Level %d to place the %s.", item.MinLevel or 1, item.Name)
	end
	if FurnitureRules.available(layout, owned, key, ignoreId) <= 0 then
		return false, string.format("You have no %s left to place.", item.Name)
	end
	local bounds = FurnitureRules.footprint(item, x, z, r)
	if not FurnitureRules.isInsideRoom(bounds) then
		return false, "Too close to the wall."
	end
	if FurnitureRules.blocksEntry(bounds) then
		return false, "Keep the door clear."
	end
	for _, entry in layout do
		local other = FurnitureConfig.ByKey[entry.Item]
		-- A rug may lie under other furniture, but not under another rug.
		local stacks = other ~= nil and (other.Floor == true) ~= (item.Floor == true)
		if entry.Id ~= ignoreId and other and not stacks then
			if overlaps(bounds, FurnitureRules.footprint(other, entry.X, entry.Z, entry.R)) then
				return false, "That overlaps the " .. other.Name .. "."
			end
		end
	end
	return true, nil
end

function FurnitureRules.find(layout: Layout, id: number): (Entry?, number?)
	for index, entry in layout do
		if entry.Id == id then
			return entry, index
		end
	end
	return nil, nil
end

-- The starting layout every office gets (FurnitureConfig.DefaultLayout).
function FurnitureRules.defaultLayout(): Layout
	local layout: Layout = {}
	for index, seed in FurnitureConfig.DefaultLayout do
		table.insert(layout, { Id = index, Item = seed.Item, X = seed.X, Z = seed.Z, R = seed.R })
	end
	return layout
end

-- Saved Special furniture: known Special keys with whole counts, bounded.
function FurnitureRules.sanitizeOwned(raw: unknown): Owned
	local owned: Owned = {}
	if typeof(raw) ~= "table" then
		return owned
	end
	for key, count in raw :: { [unknown]: unknown } do
		local item = if typeof(key) == "string" then FurnitureConfig.ByKey[key] else nil
		if item and item.Tier == "Special" and typeof(count) == "number" and count == count then
			local whole = math.clamp(math.floor(count), 0, FurnitureConfig.MaxOwnedSpecial)
			if whole > 0 then
				owned[item.Key] = whole
			end
		end
	end
	return owned
end

-- Adds `amount` of a Special item (admin rewards, later drops), capped at
-- MaxOwnedSpecial. False for unknown or Basic items or a bad amount.
function FurnitureRules.grantSpecial(owned: Owned, key: string, amount: number): boolean
	local item = FurnitureConfig.ByKey[key]
	if item == nil or item.Tier ~= "Special" or not isWhole(amount) or amount < 1 then
		return false
	end
	owned[key] = math.min(FurnitureConfig.MaxOwnedSpecial, (owned[key] or 0) + amount)
	return true
end

--[[
	A saved layout, checked entry by entry in saved order: an entry that is
	broken, unknown, out of the room, in the door, overlapping an earlier one,
	beyond the cap, a duplicate id or not owned is dropped; the rest are kept
	exactly. Also returns the next free id. Never errors.
]]
function FurnitureRules.parseLayout(raw: unknown, owned: Owned): (Layout, number)
	local layout: Layout = {}
	local nextId = 1
	if typeof(raw) ~= "table" then
		return layout, nextId
	end
	local seen: { [number]: boolean } = {}
	for _, value in raw :: { unknown } do
		if typeof(value) ~= "table" then
			continue
		end
		local data = value :: { [string]: unknown }
		local id, key = data.Id, data.Item
		if
			not isWhole(id)
			or (id :: number) < 1
			or seen[id :: number]
			or typeof(key) ~= "string"
		then
			continue
		end
		local x, z, r = data.X, data.Z, data.R
		if not (isWhole(x) and isWhole(z) and FurnitureRules.isRotation(r)) then
			continue
		end
		if
			FurnitureRules.check(
				layout,
				owned,
				key :: string,
				x :: number,
				z :: number,
				r :: number
			)
		then
			local entry: Entry = {
				Id = id :: number,
				Item = key :: string,
				X = x :: number,
				Z = z :: number,
				R = r :: number,
			}
			table.insert(layout, entry)
			seen[entry.Id] = true
			nextId = math.max(nextId, entry.Id + 1)
		end
	end
	return layout, nextId
end

-- The Office Wing -------------------------------------------------------------

-- Floor centre of room `index` (1-based): rooms stand in a row along +X.
function FurnitureRules.slotOrigin(index: number): Vector3
	return OfficeConfig.WingOrigin + Vector3.new((index - 1) * OfficeConfig.SlotSpacing, 0, 0)
end

-- The room a world position is inside (between its walls, floor to ceiling),
-- or nil. `slotCount` is how many rooms the server built.
function FurnitureRules.slotAt(position: Vector3, slotCount: number): number?
	local offset = position - OfficeConfig.WingOrigin
	local index = math.floor(offset.X / OfficeConfig.SlotSpacing + 0.5) + 1
	if index < 1 or index > slotCount then
		return nil
	end
	local localX = offset.X - (index - 1) * OfficeConfig.SlotSpacing
	if math.abs(localX) > HALF or math.abs(offset.Z) > HALF then
		return nil
	end
	if offset.Y < -2 or offset.Y > OfficeConfig.WallHeight then
		return nil
	end
	return index
end

-- Privacy ---------------------------------------------------------------------

function FurnitureRules.isPrivacy(value: unknown): boolean
	return typeof(value) == "string" and table.find(OfficeConfig.PrivacyModes, value :: any) ~= nil
end

-- May someone enter an office with this privacy? The owner always may.
function FurnitureRules.canVisit(privacy: string, isOwner: boolean, isFriend: boolean): boolean
	if isOwner or privacy == "Public" then
		return true
	end
	return privacy == "Friends" and isFriend
end

return FurnitureRules
