--!strict
--[[
	Admin events (docs/EVENTS.md). The server enforces every limit here
	(Shared/EventRules); the Admin panel shows them as choices and hints.

	Event types:
	  XpBoost        boss XP x Multiplier (the highest active one applies)
	  BossSpawn      extra event bosses at an outdoor location
	  BossDrop       qualifying defeats may drop an item into the Bag
	  StoreDiscount  Hammer Shop coin prices cut by Percent (highest applies)
]]

export type TypeInfo = {
	Label: string, -- admin panel and player list
	Icon: string,
	Blurb: string, -- one line for players when it starts
}

export type Location = {
	Id: string,
	Label: string,
	-- Boss body centres, at least MinBossSpacing apart (spec-checked), on
	-- walkways that are kept free of props (ArenaConfig.Campus).
	Slots: { Vector3 },
}

-- Outdoor ground is at Y = -1 and a boss body is 8 tall: centre Y = 3.
local GROUND_CENTRE_Y = 3

local EventConfig = table.freeze({
	-- Shared/EventRules.EventType lists the same names.
	Types = table.freeze({ "XpBoost", "BossSpawn", "BossDrop", "StoreDiscount", "EggHunt" }),
	TypeInfo = table.freeze({
		XpBoost = table.freeze({
			Label = "Experience Event",
			Icon = "⚡",
			Blurb = "Bosses give more XP!",
		}),
		BossSpawn = table.freeze({
			Label = "Outdoor Boss Event",
			Icon = "👹",
			Blurb = "Event bosses have appeared outside!",
		}),
		BossDrop = table.freeze({
			Label = "Boss Drop Event",
			Icon = "🎁",
			Blurb = "Bosses can drop bonus items!",
		}),
		StoreDiscount = table.freeze({
			Label = "Hammer Shop Sale",
			Icon = "💰",
			Blurb = "Hammers cost fewer coins!",
		}),
		EggHunt = table.freeze({
			Label = "Egg Hunt",
			Icon = "🥚",
			Blurb = "Eggs are appearing outside!",
		}),
	} :: { [string]: TypeInfo }),

	NameMaxLength = 40,

	-- Timing: a preset length starting now, or a start and end time.
	Durations = table.freeze({
		table.freeze({ Label = "30 minutes", Seconds = 30 * 60 }),
		table.freeze({ Label = "1 hour", Seconds = 60 * 60 }),
		table.freeze({ Label = "6 hours", Seconds = 6 * 60 * 60 }),
		table.freeze({ Label = "1 day", Seconds = 24 * 60 * 60 }),
		table.freeze({ Label = "3 days", Seconds = 3 * 24 * 60 * 60 }),
		table.freeze({ Label = "7 days", Seconds = 7 * 24 * 60 * 60 }),
	}),
	MaxDurationSeconds = 14 * 24 * 60 * 60,
	-- How far ahead an event may be scheduled.
	MaxStartAheadSeconds = 90 * 24 * 60 * 60,
	-- A "start now" request may be this many seconds old (clock drift, lag).
	StartGraceSeconds = 120,

	-- Events running or scheduled at once (all types), and ended ones kept.
	MaxEvents = 12,
	MaxHistory = 20,

	-- XpBoost: multipliers an admin can pick. Several at once: the highest wins.
	XpMultipliers = table.freeze({ 1.5, 2, 3, 4, 5 }),

	-- BossSpawn: which office boss to copy (stats, rewards, look; the CEO is
	-- left out like for custom bosses), where, and how many.
	BossLookIds = table.freeze({
		"deadline_boss",
		"meeting_master",
		"reply_all_boss",
		"production_bug",
		"monday_monster",
		"senior_deadline_boss",
		"senior_meeting_master",
		"senior_reply_all_boss",
		"senior_production_bug",
		"senior_monday_monster",
	}),
	MaxBossQuantity = 4,
	MinBossSpacing = 14, -- as CustomBossConfig.MinSpacing: one swing reaches one boss
	Locations = table.freeze({
		table.freeze({
			Id = "MainWalkway",
			Label = "Main Walkway (outside)",
			Slots = table.freeze({
				Vector3.new(0, GROUND_CENTRE_Y, 58),
				Vector3.new(0, GROUND_CENTRE_Y, 72),
				Vector3.new(0, GROUND_CENTRE_Y, 86),
				Vector3.new(0, GROUND_CENTRE_Y, 100),
			}),
		}),
		table.freeze({
			Id = "GardenPath",
			Label = "Garden Path",
			Slots = table.freeze({
				Vector3.new(-16, GROUND_CENTRE_Y, 88),
				Vector3.new(-30, GROUND_CENTRE_Y, 88),
				Vector3.new(-44, GROUND_CENTRE_Y, 88),
				Vector3.new(-97, GROUND_CENTRE_Y, 66),
			}),
		}),
		table.freeze({
			Id = "CoffeePath",
			Label = "Coffee Corner Path",
			Slots = table.freeze({
				Vector3.new(16, GROUND_CENTRE_Y, 88),
				Vector3.new(30, GROUND_CENTRE_Y, 88),
				Vector3.new(44, GROUND_CENTRE_Y, 88),
				Vector3.new(97, GROUND_CENTRE_Y, 66),
			}),
		}),
		table.freeze({
			Id = "BackLoop",
			Label = "Behind the Building",
			Slots = table.freeze({
				Vector3.new(-42, GROUND_CENTRE_Y, -63),
				Vector3.new(-14, GROUND_CENTRE_Y, -63),
				Vector3.new(14, GROUND_CENTRE_Y, -63),
				Vector3.new(42, GROUND_CENTRE_Y, -63),
			}),
		}),
	} :: { Location }),
	-- Event boss ids start with the custom-boss prefix so they are open to
	-- everyone and drawn like custom bosses (Shared/CustomBossRules).
	BossIdPrefix = "custom_event_",

	-- BossDrop: items that can drop (StoreConfig keys; bundles drop as their
	-- contents), and the chance range in whole percent.
	DropItems = table.freeze({
		"xp_10_30m",
		"dmg_5_30m",
		"crit_5_30m",
		"beginner_bundle",
		"stress_reliever_package",
		-- Pet eggs (docs/PETS.md): a "pet drop" event. Never the Mythical egg.
		"egg_common",
		"egg_rare",
	}),
	MinDropChancePercent = 1,
	MaxDropChancePercent = 100,

	-- StoreDiscount: whole percent off Hammer Shop coin prices. Robux prices
	-- are set in the Creator Hub and can't be discounted by the game.
	MinDiscountPercent = 5,
	MaxDiscountPercent = 90,

	-- EggHunt (docs/PETS.md "Egg hunts"): an egg of the chosen tier appears
	-- outside every IntervalMinutes (at the world egg spots, PetConfig) while
	-- fewer than MaxEggs of the hunt's eggs are out. Unclaimed ones vanish
	-- when the hunt ends.
	EggHuntIntervals = table.freeze({ 2, 5, 10, 15, 30, 60 }),
	MaxEggHuntEggs = 5,
})

return EventConfig
