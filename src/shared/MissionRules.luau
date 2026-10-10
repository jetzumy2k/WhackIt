--!strict
--[[
	Pure rules for team boss missions (Config/MissionConfig,
	docs/MISSIONS.md): boss health by team size, the bosses of a wave,
	where they stand, who counts for the reward, the daily cap and the saved
	record. The server (MissionService) runs missions; clients only display.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local MissionConfig = require(ReplicatedStorage.Config.MissionConfig)

export type Record = {
	DayKey: string, -- the UTC day DayRewarded belongs to ("" = none yet)
	DayRewarded: number, -- rewarded missions that day
	Cleared: number, -- all-time missions cleared with a reward or without
}

local MissionRules = {}

local MAX_COUNTER = 2 ^ 40
-- Starts with CustomBossConfig.IdPrefix ("custom_"), like event bosses, so
-- ProgressionRules treats them as always open (no unlock needed).
MissionRules.ID_PREFIX = "custom_mission_"

-- Health per boss of a wave for a team of `teamSize`.
function MissionRules.bossHealth(wave: MissionConfig.Wave, teamSize: number): number
	local size = math.clamp(math.floor(teamSize), 1, MissionConfig.TeamMax)
	local scale = 1 + MissionConfig.HealthPerPlayer * (size - MissionConfig.TeamHealthBase)
	return math.max(1, math.floor(wave.Health * math.max(0.4, scale) + 0.5))
end

-- The boss id for boss `index` of wave `waveIndex` in room `room`, run `run`.
function MissionRules.bossId(room: number, run: number, waveIndex: number, index: number): string
	return string.format("%sr%d_%d_w%d_%d", MissionRules.ID_PREFIX, room, run, waveIndex, index)
end

-- A boss definition for one boss of a wave (Custom + Mission: no unlocks, no
-- defeat counts, the normal office drop chance).
function MissionRules.bossDefinition(
	id: string,
	wave: MissionConfig.Wave,
	teamSize: number
): BossConfig.BossDefinition?
	local look = BossConfig.ById[wave.Look]
	if look == nil then
		return nil
	end
	return table.freeze({
		Id = id,
		DisplayName = wave.Name,
		Description = look.Description,
		MaxHealth = MissionRules.bossHealth(wave, teamSize),
		DamageTakenMultiplier = 1,
		ScoreReward = MissionConfig.BossScore,
		CoinReward = MissionConfig.BossCoins,
		UnlockDefeats = 0,
		Custom = true,
		Mission = true,
		LookId = look.Id,
	})
end

-- Where `count` bosses stand in a room, relative to its centre on the floor:
-- spread across the far half, at least 14 studs apart (one swing, one boss).
function MissionRules.bossOffsets(count: number): { Vector3 }
	local offsets: { Vector3 } = {}
	local spacing = 16
	local width = (count - 1) * spacing
	for index = 1, count do
		table.insert(offsets, Vector3.new(-width / 2 + (index - 1) * spacing, 0, -14))
	end
	return offsets
end

-- The centre of room `index` (1-based), on its floor.
function MissionRules.roomCenter(index: number): Vector3
	local rooms = MissionConfig.Rooms
	return rooms.Origin + Vector3.new((index - 1) * rooms.Spacing, 0, 0)
end

--[[
	Who counts for the mission reward, from accepted hits on the mission's
	bosses: at least MinHits and MinHitShare of the team's average. Hits, not
	damage, so levels don't decide it.
]]
function MissionRules.counted(
	hits: { [number]: number },
	members: { number }
): { [number]: boolean }
	local total = 0
	for _, userId in members do
		total += hits[userId] or 0
	end
	local average = if #members > 0 then total / #members else 0
	local needed = math.max(MissionConfig.MinHits, MissionConfig.MinHitShare * average)
	local result: { [number]: boolean } = {}
	for _, userId in members do
		if (hits[userId] or 0) >= needed then
			result[userId] = true
		end
	end
	return result
end

-- Saved record --------------------------------------------------------------------

function MissionRules.defaultRecord(): Record
	return { DayKey = "", DayRewarded = 0, Cleared = 0 }
end

local function counter(value: unknown): number
	if typeof(value) ~= "number" or value ~= value or value == math.huge then
		return 0
	end
	return math.clamp(math.floor(value), 0, MAX_COUNTER)
end

function MissionRules.sanitizeRecord(raw: unknown): Record
	local record = MissionRules.defaultRecord()
	if typeof(raw) ~= "table" then
		return record
	end
	local data = raw :: { [string]: unknown }
	record.Cleared = counter(data.Cleared)
	local dayKey = data.DayKey
	if typeof(dayKey) == "string" and string.match(dayKey, "^%d%d%d%d%-%d%d%-%d%d$") then
		record.DayKey = dayKey
		record.DayRewarded = counter(data.DayRewarded)
	end
	return record
end

-- Whether a cleared mission still pays its reward today (moves the record
-- to `dayKey` first).
function MissionRules.canEarn(record: Record, dayKey: string): boolean
	if record.DayKey ~= dayKey then
		record.DayKey = dayKey
		record.DayRewarded = 0
	end
	return record.DayRewarded < MissionConfig.DailyRewarded
end

return MissionRules
