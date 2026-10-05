--!strict
--[[
	Saved player data: shape, defaults, migrations and validation. Pure (no
	DataStore), so every path is unit-tested; PlayerDataService applies it to
	each loaded profile before the game uses it. See docs/DATA_SCHEMA.md.

	Loaded data is never trusted: an older bug, a manual DataStore edit or a
	newer server version could have written anything. prepare() upgrades old
	versions, fills missing fields, repairs invalid values in place, and refuses
	data written by a NEWER schema rather than risk misreading it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)

export type PlayerData = {
	SchemaVersion: number,
	Score: number,
	Stress: number,
	TotalHits: number,
	TotalBossesDefeated: number,
	EquippedHammerId: string,
}

-- Raw saved table before validation.
export type RawData = { [string]: unknown }

-- Upgrades data from version (n - 1) to version n, in place.
export type Migration = (data: RawData) -> ()

local PlayerDataSchema = {}

PlayerDataSchema.CURRENT_VERSION = 1

-- Upper bound for counters; far beyond legitimate play, small enough to stay
-- an exact integer and to keep leaderboard values sane.
local MAX_COUNTER = 2 ^ 50

-- MIGRATIONS[n] upgrades version n - 1 to n. Data saved before versioning
-- existed has no SchemaVersion and counts as version 0.
PlayerDataSchema.MIGRATIONS = table.freeze({
	[1] = function(data: RawData)
		-- v0 -> v1: first versioned schema; fields are filled by prepare().
		data.SchemaVersion = 1
	end,
}) :: { [number]: Migration }

function PlayerDataSchema.template(): PlayerData
	return {
		SchemaVersion = PlayerDataSchema.CURRENT_VERSION,
		Score = GameConfig.StartingScore,
		Stress = GameConfig.StartingStress,
		TotalHits = 0,
		TotalBossesDefeated = 0,
		EquippedHammerId = GameConfig.DefaultHammerId,
	}
end

local function isFiniteNumber(value: unknown): boolean
	return typeof(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

local function counter(value: unknown, fallback: number): number
	if not isFiniteNumber(value) then
		return fallback
	end
	return math.clamp(math.floor(value :: number), 0, MAX_COUNTER)
end

-- Runs migrations from the stored version up to `targetVersion`.
-- Returns false (and changes nothing) for data newer than `targetVersion`.
function PlayerDataSchema.migrate(
	data: RawData,
	migrations: { [number]: Migration },
	targetVersion: number
): (boolean, string?)
	local version = data.SchemaVersion
	local current = if isFiniteNumber(version) then math.floor(version :: number) else 0
	if current > targetVersion then
		return false,
			string.format("data schema v%d is newer than this server's v%d", current, targetVersion)
	end
	for nextVersion = current + 1, targetVersion do
		local migration = migrations[nextVersion]
		if migration == nil then
			return false, string.format("no migration to schema v%d", nextVersion)
		end
		migration(data)
		data.SchemaVersion = nextVersion
	end
	return true, nil
end

-- Fills missing fields and repairs invalid values in place.
function PlayerDataSchema.sanitize(data: RawData): ()
	local defaults = PlayerDataSchema.template()

	data.Score = counter(data.Score, defaults.Score)
	data.TotalHits = counter(data.TotalHits, defaults.TotalHits)
	data.TotalBossesDefeated = counter(data.TotalBossesDefeated, defaults.TotalBossesDefeated)

	local stress = data.Stress
	data.Stress = if isFiniteNumber(stress)
		then math.clamp(stress :: number, 0, GameConfig.MaxStress)
		else defaults.Stress

	local hammerId = data.EquippedHammerId
	if typeof(hammerId) ~= "string" or HammerConfig.ById[hammerId] == nil then
		data.EquippedHammerId = defaults.EquippedHammerId
	end
end

-- Migrate, then sanitize. On success the table matches PlayerData exactly
-- (extra keys from future versions are left untouched).
function PlayerDataSchema.prepare(data: RawData): (boolean, string?)
	local ok, reason = PlayerDataSchema.migrate(
		data,
		PlayerDataSchema.MIGRATIONS,
		PlayerDataSchema.CURRENT_VERSION
	)
	if not ok then
		return false, reason
	end
	PlayerDataSchema.sanitize(data)
	return true, nil
end

return PlayerDataSchema
