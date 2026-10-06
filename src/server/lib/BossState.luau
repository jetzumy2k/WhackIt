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
	-- UserIds already rewarded for this boss life (rewards are granted once).
	Rewarded: { [number]: boolean },
	LastHitterUserId: number?, -- who landed the defeating hit
	-- UserIds that hit this boss life with admin-set damage: they get no reward.
	AdminBoosted: { [number]: boolean },
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
		Rewarded = {},
		LastHitterUserId = nil,
		AdminBoosted = {},
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
		state.LastHitterUserId = userId
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

-- Marks that `userId` hit this boss life with admin-set damage.
function BossState.markAdminBoosted(state: BossState, userId: number): ()
	state.AdminBoosted[userId] = true
end

-- Records that `userId` is being rewarded for this defeated boss. Returns false
-- if the boss isn't defeated or the player was already rewarded, so a reward
-- can never be granted twice for the same boss life.
function BossState.markRewarded(state: BossState, userId: number): boolean
	if not state.Defeated or state.Rewarded[userId] then
		return false
	end
	state.Rewarded[userId] = true
	return true
end

return BossState
