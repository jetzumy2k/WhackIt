--!strict
--[[
	Pure rules for admin-created bosses (docs/ADMIN.md): validating what the
	admin panel sends, validating what comes back from the DataStore, turning a
	saved record into a BossDefinition, and picking the random store boost a
	custom boss drops. No Instances or services, so every path is unit-tested.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local CustomBossConfig = require(ReplicatedStorage.Config.CustomBossConfig)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)
local Validate = require(script.Parent.Validate)

-- "Continuous" respawns after every defeat; "Once" is gone after its first.
export type RespawnMode = "Continuous" | "Once"

-- What the admin asks for. The position is never sent: the server uses where
-- the admin is standing.
export type Spec = {
	Name: string,
	LookId: string,
	MaxHealth: number,
	ScoreReward: number,
	CoinReward: number,
	RespawnMode: RespawnMode,
}

-- One saved custom boss (DataStore), shared by every server.
export type Record = {
	Id: string,
	Name: string, -- already text-filtered for everyone
	LookId: string,
	MaxHealth: number,
	ScoreReward: number,
	CoinReward: number,
	X: number,
	Y: number, -- centre of the boss body
	Z: number,
	CreatedBy: number,
	RespawnMode: RespawnMode,
	Defeated: boolean, -- a "Once" boss that has been beaten (in any server)
}

-- A random store boost dropped by a custom boss; Key is the store product
-- (always the BuffDropSeconds length) that goes into the player's Bag.
export type Drop = { Kind: string, Percent: number, Key: string }

local CustomBossRules = {}

-- Keeps coordinates inside a sane box around the map.
local MAX_COORDINATE = 100000

function CustomBossRules.isCustomId(bossId: string): boolean
	local prefix = CustomBossConfig.IdPrefix
	return string.sub(bossId, 1, #prefix) == prefix
end

function CustomBossRules.isLookId(value: string): boolean
	return table.find(CustomBossConfig.LookIds, value) ~= nil
end

function CustomBossRules.parseRespawnMode(raw: unknown): RespawnMode?
	if raw == "Continuous" then
		return "Continuous"
	elseif raw == "Once" then
		return "Once"
	end
	return nil
end

-- Trims spaces and collapses runs of whitespace, so "  Bob   Boss " -> "Bob Boss".
function CustomBossRules.cleanName(raw: string): string
	local collapsed = string.gsub(raw, "%s+", " ")
	return (string.match(collapsed, "^%s*(.-)%s*$") or "")
end

-- Returns the validated spec, or nil and a reason the admin can read.
function CustomBossRules.parseSpec(raw: unknown): (Spec?, string?)
	if typeof(raw) ~= "table" then
		return nil, "bad request"
	end
	local data = raw :: { [string]: unknown }

	local rawName = Validate.string(data.Name, CustomBossConfig.NameMaxLength * 2)
	local name = if rawName then CustomBossRules.cleanName(rawName) else ""
	if
		#name == 0
		or utf8.len(name) == nil
		or (utf8.len(name) :: number) > CustomBossConfig.NameMaxLength
	then
		return nil,
			string.format("Name must be 1 to %d characters.", CustomBossConfig.NameMaxLength)
	end

	local lookId = Validate.id(data.LookId, 64)
	if lookId == nil or not CustomBossRules.isLookId(lookId) then
		return nil, "Pick a look from the list."
	end

	local health =
		Validate.integer(data.MaxHealth, CustomBossConfig.MinHealth, CustomBossConfig.MaxHealth)
	if health == nil then
		return nil,
			string.format(
				"HP must be a whole number from %d to %d.",
				CustomBossConfig.MinHealth,
				CustomBossConfig.MaxHealth
			)
	end

	local score = Validate.integer(data.ScoreReward, 0, CustomBossConfig.MaxScoreReward)
	if score == nil then
		return nil, string.format("Score reward must be 0 to %d.", CustomBossConfig.MaxScoreReward)
	end

	local coins = Validate.integer(data.CoinReward, 0, CustomBossConfig.MaxCoinReward)
	if coins == nil then
		return nil, string.format("Coin reward must be 0 to %d.", CustomBossConfig.MaxCoinReward)
	end

	local respawnMode = CustomBossRules.parseRespawnMode(data.RespawnMode)
	if respawnMode == nil then
		return nil, "Pick a respawn option."
	end

	local spec: Spec = {
		Name = name,
		LookId = lookId,
		MaxHealth = health,
		ScoreReward = score,
		CoinReward = coins,
		RespawnMode = respawnMode :: RespawnMode,
	}
	return spec, nil
end

-- Validates one saved record (the DataStore is not trusted either).
function CustomBossRules.parseRecord(raw: unknown): Record?
	if typeof(raw) ~= "table" then
		return nil
	end
	local data = raw :: { [string]: unknown }
	local id = Validate.id(data.Id, 64)
	if id == nil or not CustomBossRules.isCustomId(id) then
		return nil
	end
	-- Name was filtered before saving; only its shape is checked here.
	local name = Validate.string(data.Name, CustomBossConfig.NameMaxLength * 4)
	local spec = CustomBossRules.parseSpec({
		Name = name,
		LookId = data.LookId,
		MaxHealth = data.MaxHealth,
		ScoreReward = data.ScoreReward,
		CoinReward = data.CoinReward,
		-- Records saved before respawn modes existed have neither field.
		RespawnMode = if data.RespawnMode == nil
			then CustomBossConfig.DefaultRespawnMode
			else data.RespawnMode,
	})
	local defeated = if data.Defeated == nil then false else Validate.boolean(data.Defeated)
	local x = Validate.number(data.X, -MAX_COORDINATE, MAX_COORDINATE)
	local y = Validate.number(data.Y, -MAX_COORDINATE, MAX_COORDINATE)
	local z = Validate.number(data.Z, -MAX_COORDINATE, MAX_COORDINATE)
	local createdBy = Validate.integer(data.CreatedBy, 0, 2 ^ 53)
	if
		name == nil
		or spec == nil
		or x == nil
		or y == nil
		or z == nil
		or createdBy == nil
		or defeated == nil
	then
		return nil
	end
	return {
		Id = id,
		Name = name,
		LookId = spec.LookId,
		MaxHealth = spec.MaxHealth,
		ScoreReward = spec.ScoreReward,
		CoinReward = spec.CoinReward,
		X = x,
		Y = y,
		Z = z,
		CreatedBy = createdBy,
		RespawnMode = spec.RespawnMode,
		-- Only a "Once" boss can be spent.
		Defeated = defeated and spec.RespawnMode == "Once",
	}
end

-- Validates a saved list: drops bad entries and duplicates, keeps at most MaxBosses.
function CustomBossRules.parseList(raw: unknown): { Record }
	local records: { Record } = {}
	if typeof(raw) ~= "table" then
		return records
	end
	local seen: { [string]: boolean } = {}
	for _, entry in raw :: { unknown } do
		local record = CustomBossRules.parseRecord(entry)
		if record and not seen[record.Id] and #records < CustomBossConfig.MaxBosses then
			seen[record.Id] = true
			table.insert(records, record)
		end
	end
	return records
end

-- The fight a custom boss offers. Custom bosses are open to everyone and
-- take normal damage.
function CustomBossRules.definitionFor(record: Record): BossConfig.BossDefinition
	return table.freeze({
		Id = record.Id,
		DisplayName = record.Name,
		Description = "A boss placed by an admin.",
		MaxHealth = record.MaxHealth,
		DamageTakenMultiplier = 1,
		ScoreReward = record.ScoreReward,
		CoinReward = record.CoinReward,
		UnlockDefeats = 0,
		Custom = true,
		LookId = record.LookId,
	})
end

-- True when `position` keeps MinSpacing from every point in `others`.
function CustomBossRules.hasSpace(position: Vector3, others: { Vector3 }): boolean
	for _, other in others do
		if (other - position).Magnitude < CustomBossConfig.MinSpacing then
			return false
		end
	end
	return true
end

-- The boosts a custom boss can drop: every boost the store sells, at its
-- strength (the drop always lasts BuffDropSeconds). Products that are live
-- (have a Developer Product id) are preferred, so drops match the store.
function CustomBossRules.dropOptions(products: { StoreConfig.Product }): { Drop }
	-- Strengths on sale (any length has a Developer Product id).
	local live: { [string]: boolean } = {}
	local anyLive = false
	for _, product in products do
		if product.Kind ~= "MysteryHammer" and product.ProductId ~= 0 then
			live[product.Kind .. ":" .. product.Percent] = true
			anyLive = true
		end
	end
	local options: { Drop } = {}
	for _, product in products do
		if
			product.Kind ~= "MysteryHammer"
			and product.Seconds == CustomBossConfig.BuffDropSeconds
			and (not anyLive or live[product.Kind .. ":" .. product.Percent])
		then
			table.insert(
				options,
				{ Kind = product.Kind :: string, Percent = product.Percent, Key = product.Key }
			)
		end
	end
	return options
end

-- Picks one drop for a roll in [0, 1).
function CustomBossRules.pickDrop(options: { Drop }, roll: number): Drop?
	if #options == 0 then
		return nil
	end
	local index = math.clamp(math.floor(roll * #options) + 1, 1, #options)
	return options[index]
end

return CustomBossRules
