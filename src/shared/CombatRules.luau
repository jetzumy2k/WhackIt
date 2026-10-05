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

return CombatRules
