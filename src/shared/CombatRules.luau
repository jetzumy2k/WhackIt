--!strict
-- Pure combat formulas shared by server logic and tests. The server is the only
-- caller that applies results; clients may use them for display previews only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)

local CombatRules = {}

-- Rounded to a whole number so HP stays integral (e.g. 10 x 1.2 is 12.000000000000002
-- in floating point), and never below MinHitDamage.
function CombatRules.computeHitDamage(
	hammer: HammerConfig.HammerDefinition,
	boss: BossConfig.BossDefinition
): number
	local raw = hammer.Damage * boss.DamageTakenMultiplier
	return math.max(GameConfig.MinHitDamage, math.floor(raw + 0.5))
end

-- `lastHitAt` is nil before a player's first hit. The server passes
-- GameConfig.HitCooldownGrace to forgive network jitter; the client passes 0 so
-- it never sends hits the server would drop.
function CombatRules.isOffCooldown(now: number, lastHitAt: number?, graceSeconds: number): boolean
	if lastHitAt == nil then
		return true
	end
	return now - lastHitAt >= GameConfig.HitCooldown - graceSeconds
end

-- The server passes GameConfig.HitReachGrace to forgive the player having moved
-- slightly by the time the request arrives; the client passes 0 (as with the cooldown).
function CombatRules.isInReach(
	playerPosition: Vector3,
	bossPosition: Vector3,
	graceStuds: number
): boolean
	return (playerPosition - bossPosition).Magnitude <= GameConfig.HitReach + graceStuds
end

return CombatRules
