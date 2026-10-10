--!strict
--[[
	Pure rules for the tower elevator (docs/TOWER.md, Phase 3a; decisions
	D14-D16): the floors (ArenaConfig.Tower), who may ride to which floor and
	why not, where riders arrive, which floor a position is on and whether a
	position is at an elevator door. The server (TowerService) decides every
	ride; the client's floor panel uses the same rules only to display.

	  Ground, Senior   always open (Senior bosses are locked one by one)
	  Rooftop          always open (the Rooftop Lounge)
	  Executive        the CEO is unlocked for the player (ProgressionRules)
	  Department       Player Level >= GameConfig.PrincipalMinLevel
	An admin's boss-access bypass opens every floor.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local ProgressionRules = require(script.Parent.ProgressionRules)

export type Floor = {
	Id: string,
	Number: number,
	Name: string,
	Text: string,
	FloorY: number,
	DoorName: string,
}

export type Status = {
	Open: boolean,
	Reason: string, -- what's missing ("" when open)
	Progress: number, -- 0..1 towards opening (1 when open)
}

local TowerRules = {}

local TOWER = ArenaConfig.Tower
-- How far up from a floor still counts as on it (rooms are 14 tall).
local STOREY_HEIGHT = 14
-- Players stand with their root about 3 studs over the floor.
local ARRIVE_HEIGHT = 3

function TowerRules.floors(): { Floor }
	return TOWER.Floors :: { Floor }
end

function TowerRules.floor(id: string): Floor?
	for _, floor in TOWER.Floors do
		if floor.Id == id then
			return floor :: Floor
		end
	end
	return nil
end

local OPEN: Status = table.freeze({ Open = true, Reason = "", Progress = 1 })

--[[
	Whether a player may ride to floor `id`. `defeats`, `level` and
	`adminUnlocks` are the player's (saved data on the server, the snapshot
	on the client); `bypass` is an admin's boss-access bypass.
]]
function TowerRules.status(
	id: string,
	defeats: { [string]: number },
	level: number,
	adminUnlocks: { [string]: boolean }?,
	bypass: boolean
): Status
	if bypass or id == "Ground" or id == "Senior" or id == "Rooftop" then
		return OPEN
	end
	if id == "Executive" then
		local status = ProgressionRules.unlockStatus(
			ArenaConfig.Executive.CeoBossId,
			defeats,
			level,
			adminUnlocks
		)
		if status.Unlocked then
			return OPEN
		end
		if status.LevelNeeded > 0 then
			return {
				Open = false,
				Reason = string.format(
					"Reach Level %d (you're Level %d)",
					status.LevelNeeded,
					level
				),
				Progress = math.clamp(level / status.LevelNeeded, 0, 1),
			}
		end
		local others = 0
		local ceo = ArenaConfig.Executive.CeoBossId
		for _, boss in BossConfig.List do
			if boss.Id ~= ceo and not boss.PostCeo then
				others += 1
			end
		end
		return {
			Open = false,
			Reason = string.format("Defeat every boss once (%d to go)", status.DefeatsNeeded),
			Progress = if others > 0
				then math.clamp(1 - status.DefeatsNeeded / others, 0, 1)
				else 0,
		}
	end
	if id == "Department" then
		local needed = GameConfig.PrincipalMinLevel
		if level >= needed then
			return OPEN
		end
		return {
			Open = false,
			Reason = string.format("Reach Level %d (you're Level %d)", needed, level),
			Progress = math.clamp(level / needed, 0, 1),
		}
	end
	return { Open = false, Reason = "That floor doesn't exist.", Progress = 0 }
end

-- Where riders step out on floor `id`: in front of the door, facing into the floor.
function TowerRules.arrival(id: string): Vector3?
	local floor = TowerRules.floor(id)
	if floor == nil then
		return nil
	end
	return Vector3.new(TOWER.ArriveX, floor.FloorY + ARRIVE_HEIGHT, TOWER.DoorZ)
end

-- The elevator door of floor `id` (centre of the door part).
function TowerRules.door(id: string): Vector3?
	local floor = TowerRules.floor(id)
	if floor == nil then
		return nil
	end
	return Vector3.new(TOWER.DoorX, floor.FloorY + 4, TOWER.DoorZ)
end

-- The floor a position is on (inside the building), or nil.
function TowerRules.floorAt(position: Vector3): Floor?
	if math.abs(position.X) > ArenaConfig.BuildingHalfWidth then
		return nil
	end
	if position.Z < ArenaConfig.BuildingNorthZ or position.Z > ArenaConfig.BuildingSouthZ then
		return nil
	end
	local found: Floor? = nil
	for _, floor in TOWER.Floors do
		if position.Y >= floor.FloorY - 0.5 and position.Y < floor.FloorY + STOREY_HEIGHT + 1 then
			found = floor :: Floor
		end
	end
	return found
end

-- Whether `position` is within `distance` studs of any elevator door (a ride
-- must be asked for at a door).
function TowerRules.atDoor(position: Vector3, distance: number): boolean
	for _, floor in TOWER.Floors do
		local door = Vector3.new(TOWER.DoorX, floor.FloorY + 4, TOWER.DoorZ)
		if (position - door).Magnitude <= distance then
			return true
		end
	end
	return false
end

return TowerRules
