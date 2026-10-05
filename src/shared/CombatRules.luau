--!strict
-- Pure combat formulas shared by server logic and tests. The server is the only
-- caller that applies results; clients may use them for display previews only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)

local CombatRules = {}

-- Everything that shapes one hit, gathered by the server (BuffService).
export type HitStats = {
	HammerDamage: number,
	FlatBonus: number, -- e.g. the Zen buff's +10
	DamageBonus: number, -- fraction, e.g. 0.05 for a +5 % damage boost
	CritChance: number, -- 0..1
	CritDamage: number, -- extra damage on a crit as a fraction (0.5 = +50 %)
}

-- Stats with no bonuses: base crit chance and damage only.
function CombatRules.baseStats(hammerDamage: number): HitStats
	return {
		HammerDamage = hammerDamage,
		FlatBonus = 0,
		DamageBonus = 0,
		CritChance = GameConfig.BaseCritChance,
		CritDamage = GameConfig.BaseCritDamage,
	}
end

-- One hit's damage. `critRoll` is a uniform 0..1 number from the server's
-- random generator (passed in so the formula stays pure and testable).
-- Rounded to a whole number so HP stays integral (e.g. 10 x 1.2 is
-- 12.000000000000002 in floating point), and never below MinHitDamage.
function CombatRules.hitDamage(
	stats: HitStats,
	boss: BossConfig.BossDefinition,
	critRoll: number
): (number, boolean)
	local isCrit = critRoll < stats.CritChance
	local raw = (stats.HammerDamage + stats.FlatBonus)
		* (1 + stats.DamageBonus)
		* boss.DamageTakenMultiplier
	if isCrit then
		raw *= 1 + stats.CritDamage
	end
	return math.max(GameConfig.MinHitDamage, math.floor(raw + 0.5)), isCrit
end

-- Damage of a plain, non-critical hit with a regular hammer (no bonuses).
function CombatRules.computeHitDamage(
	hammer: HammerConfig.HammerDefinition,
	boss: BossConfig.BossDefinition
): number
	local damage = CombatRules.hitDamage(CombatRules.baseStats(hammer.Damage), boss, 1)
	return damage
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
