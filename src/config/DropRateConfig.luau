--!strict
-- Buff drop chances for office boss defeats (docs/GAMEPLAY_RULES.md "Buff drop").
-- Chances are probabilities: 0.30 = 30 %. Each qualifying player's roll picks
-- a chance at random between Min and Max of the range in effect, then drops a
-- random 30-minute store boost with that chance.
--
-- The Lucky range only applies during the Lucky window: the first
-- LuckyLastsMinutes of every LuckyEveryMinutes, counted in UTC from midnight
-- (so with the defaults: 00:00-00:10, 02:00-02:10, ... UTC), the same in every
-- server. The rest of the time the Normal range applies.
--
-- Admins can change these in the Admin panel (Drops tab, saved for every
-- server); Default is what "Reset to defaults" brings back.

local DropRateConfig = table.freeze({
	Default = table.freeze({
		NormalMin = 0.0005,
		NormalMax = 0.10,
		LuckyMin = 0.10,
		LuckyMax = 0.30,
		LuckyEveryMinutes = 120,
		LuckyLastsMinutes = 10,
	}),

	-- Limits the server enforces on admin input.
	MinEveryMinutes = 10,
	MaxEveryMinutes = 24 * 60,
	MinLastsMinutes = 1,
})

return DropRateConfig
