--!strict
--[[
	Pure state for one spawned boss: health, per-player damage contribution and
	the one-way transition to defeated. No Instances, so it is fully unit-tested.

	Luau runs each remote handler to completion without interleaving, so as long
	as callers don't yield between reading and applying, two simultaneous hits
	can never both defeat the same boss.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Config.BossConfig)

export type BossState = {
	InstanceId: string,
	Definition: BossConfig.BossDefinition,
	Health: number,
	Defeated: boolean,
	-- UserId -> damage actually applied (overkill is not credited).
	Contributions: { [number]: number },
}

export type HitResult = {
	Applied: number,
	Health: number,
	Defeated: boolean, -- true only on the hit that defeats the boss
}

local BossState = {}

function BossState.new(definition: BossConfig.BossDefinition, instanceId: string): BossState
	return {
		InstanceId = instanceId,
		Definition = definition,
		Health = definition.MaxHealth,
		Defeated = false,
		Contributions = {},
	}
end

-- Returns nil when the hit changes nothing: boss already defeated or damage <= 0.
function BossState.applyDamage(state: BossState, userId: number, damage: number): HitResult?
	if state.Defeated or damage <= 0 then
		return nil
	end

	local applied = math.min(damage, state.Health)
	state.Health -= applied
	state.Contributions[userId] = (state.Contributions[userId] or 0) + applied

	local defeatedNow = state.Health <= 0
	if defeatedNow then
		state.Defeated = true
	end

	return {
		Applied = applied,
		Health = state.Health,
		Defeated = defeatedNow,
	}
end

-- Players whose contribution is at least minShare of MaxHealth, in ascending
-- UserId order so reward handling is deterministic.
function BossState.qualifyingUserIds(state: BossState, minShare: number): { number }
	local threshold = state.Definition.MaxHealth * minShare
	local userIds: { number } = {}
	for userId, damage in state.Contributions do
		if damage >= threshold then
			table.insert(userIds, userId)
		end
	end
	table.sort(userIds)
	return userIds
end

return BossState
