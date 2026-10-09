--!strict
--[[
	Pure rules for the boss office doors (docs/GAMEPLAY_RULES.md "Office
	doors"): what a door shows for this player, and whether a position is
	inside an office (so a door never closes on someone inside). The unlock
	itself comes from the one existing rule, Shared/ProgressionRules, via the
	server's Profile.Sync (ProgressController); this only turns it into a
	door state. The server separately refuses hits on locked bosses
	(CombatService), so a door is presentation and a convenience, never the
	security.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ArenaConfig"))
local BossConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BossConfig"))
local ProgressionRules =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ProgressionRules"))

export type DoorState = {
	Open: boolean,
	State: string, -- "Locked" | "Available" | "Beaten"
	Text: string, -- the small sign over the door
}

local OfficeDoors = {}

-- What a door shows: closed with the requirement, or open.
function OfficeDoors.state(status: ProgressionRules.UnlockStatus?, defeats: number): DoorState
	if status == nil then
		-- Progress not loaded yet: closed, without a requirement to show.
		return { Open = false, State = "Locked", Text = "🔒 LOCKED" }
	end
	if status.Unlocked then
		if defeats > 0 then
			return { Open = true, State = "Beaten", Text = string.format("✓ BEATEN x%d", defeats) }
		end
		return { Open = true, State = "Available", Text = "✓ AVAILABLE" }
	end
	if status.LevelNeeded > 0 then
		return {
			Open = false,
			State = "Locked",
			Text = string.format("🔒 Requires Level %d", status.LevelNeeded),
		}
	end
	local previous = if status.PreviousBossId then BossConfig.ById[status.PreviousBossId] else nil
	if previous then
		return {
			Open = false,
			State = "Locked",
			Text = string.format("🔒 Beat %s x%d", previous.DisplayName, status.DefeatsNeeded),
		}
	end
	return { Open = false, State = "Locked", Text = "🔒 LOCKED" }
end

-- True when `position` is inside the office, or right in its doorway.
function OfficeDoors.isInside(office: ArenaConfig.Office, position: Vector3): boolean
	local size = ArenaConfig.OfficeSize
	local offset = position - office.Center
	return math.abs(offset.X) <= size.X / 2
		and offset.Z >= -size.Z / 2
		and offset.Z <= size.Z / 2 + 2 -- the doorway and a step in front of it
		and offset.Y >= -1
		and offset.Y <= size.Y
end

return OfficeDoors
