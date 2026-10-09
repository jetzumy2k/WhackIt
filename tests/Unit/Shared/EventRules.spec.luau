--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaConfig = require(ReplicatedStorage.Config.ArenaConfig)
local BossConfig = require(ReplicatedStorage.Config.BossConfig)
local CustomBossRules = require(ReplicatedStorage.Shared.CustomBossRules)
local EventConfig = require(ReplicatedStorage.Config.EventConfig)
local EventRules = require(ReplicatedStorage.Shared.EventRules)
local HammerConfig = require(ReplicatedStorage.Config.HammerConfig)
local StoreConfig = require(ReplicatedStorage.Config.StoreConfig)

local NOW = 1_800_000_000
local HOUR = 3600

local function record(
	id: string,
	eventType: EventRules.EventType,
	config: EventRules.Config,
	startTime: number?,
	endTime: number?
): EventRules.Record
	return {
		Id = id,
		Name = id,
		Type = eventType,
		StartTime = startTime or NOW - HOUR,
		EndTime = endTime or NOW + HOUR,
		Config = config,
		CreatedBy = 1,
		CreatedByName = "Admin",
		CreatedAt = NOW - HOUR,
	}
end

local function paidHammer(): HammerConfig.HammerDefinition
	for _, hammer in HammerConfig.List do
		if hammer.Price >= 100 then
			return hammer
		end
	end
	error("no hammer costing 100+ coins")
end

-- Just the spec (parseSpec also returns a reason).
local function spec(raw: unknown): EventRules.Spec?
	local parsed = EventRules.parseSpec(raw, NOW)
	return parsed
end

return function()
	describe("EventRules.parseSpec", function()
		it("accepts a 2x XP event for 1 day starting now, with a default name", function()
			local parsed = spec({
				Type = "XpBoost",
				DurationSeconds = 24 * HOUR,
				Config = { Multiplier = 2 },
			}) :: EventRules.Spec
			expect(parsed).never.to.equal(nil)
			expect(parsed.StartTime).to.equal(NOW)
			expect(parsed.EndTime).to.equal(NOW + 24 * HOUR)
			expect(parsed.Config.Multiplier).to.equal(2)
			expect(parsed.Name).to.equal("2X EXPERIENCE")
			expect(parsed.CustomName).to.equal(false)
		end)

		it("cleans a typed name and marks it for the text filter", function()
			local parsed = spec({
				Type = "XpBoost",
				Name = "  Weekend \n XP   Boost ",
				DurationSeconds = HOUR,
				Config = { Multiplier = 3 },
			}) :: EventRules.Spec
			expect(parsed.Name).to.equal("Weekend XP Boost")
			expect(parsed.CustomName).to.equal(true)
		end)

		it("refuses multipliers, durations and types that aren't on the lists", function()
			expect(spec({ Type = "XpBoost", DurationSeconds = HOUR, Config = { Multiplier = 10 } })).to.equal(
				nil
			)
			expect(spec({ Type = "XpBoost", DurationSeconds = 123, Config = { Multiplier = 2 } })).to.equal(
				nil
			)
			expect(spec({ Type = "GodMode", DurationSeconds = HOUR, Config = {} })).to.equal(nil)
			expect(
				spec({ Type = "XpBoost", DurationSeconds = HOUR, Config = { Multiplier = 0 / 0 } })
			).to.equal(nil)
			expect(spec("XpBoost")).to.equal(nil)
		end)

		it("checks scheduled start and end times", function()
			local function scheduled(startsAt: number, endsAt: number): EventRules.Spec?
				return spec({
					Type = "XpBoost",
					StartsAt = startsAt,
					EndsAt = endsAt,
					Config = { Multiplier = 2 },
				})
			end
			expect(scheduled(NOW + HOUR, NOW + 2 * HOUR)).never.to.equal(nil)
			expect(scheduled(NOW - 10 * HOUR, NOW + HOUR)).to.equal(nil) -- starts in the past
			expect(scheduled(NOW + HOUR, NOW + HOUR)).to.equal(nil) -- ends when it starts
			expect(scheduled(NOW + 2 * HOUR, NOW + HOUR)).to.equal(nil) -- ends before it starts
			expect(scheduled(NOW, NOW + EventConfig.MaxDurationSeconds + 1)).to.equal(nil) -- too long
			expect(
				scheduled(
					NOW + EventConfig.MaxStartAheadSeconds + 1,
					NOW + EventConfig.MaxStartAheadSeconds + HOUR
				)
			).to.equal(nil) -- too far ahead
			expect(scheduled(NOW + 0.5, NOW + HOUR)).to.equal(nil) -- not whole seconds
		end)

		it("validates outdoor boss events", function()
			local ok = spec({
				Type = "BossSpawn",
				DurationSeconds = 30 * 60,
				Config = { BossId = "production_bug", LocationId = "GardenPath", Quantity = 2 },
			})
			expect(ok).never.to.equal(nil)
			expect(spec({
				Type = "BossSpawn",
				DurationSeconds = 30 * 60,
				Config = { BossId = "the_ceo", LocationId = "GardenPath", Quantity = 1 },
			})).to.equal(nil)
			expect(spec({
				Type = "BossSpawn",
				DurationSeconds = 30 * 60,
				Config = { BossId = "production_bug", LocationId = "Moon", Quantity = 1 },
			})).to.equal(nil)
			expect(spec({
				Type = "BossSpawn",
				DurationSeconds = 30 * 60,
				Config = {
					BossId = "production_bug",
					LocationId = "GardenPath",
					Quantity = EventConfig.MaxBossQuantity + 1,
				},
			})).to.equal(nil)
		end)

		it("validates drop events: all bosses or one boss, listed items, whole % chance", function()
			local all = spec({
				Type = "BossDrop",
				DurationSeconds = HOUR,
				Config = {
					BossId = EventRules.ALL_BOSSES,
					ItemKey = "beginner_bundle",
					ChancePercent = 10,
				},
			}) :: EventRules.Spec
			expect(all.Config.BossId).to.equal(EventRules.ALL_BOSSES)
			expect(spec({
				Type = "BossDrop",
				DurationSeconds = HOUR,
				Config = { BossId = "deadline_boss", ItemKey = "xp_10_30m", ChancePercent = 100 },
			})).never.to.equal(nil)
			for _, bad in
				{
					{ BossId = "nobody", ItemKey = "xp_10_30m", ChancePercent = 10 },
					{ BossId = "*", ItemKey = "mystery_hammer", ChancePercent = 10 },
					{ BossId = "*", ItemKey = "xp_10_30m", ChancePercent = 0 },
					{ BossId = "*", ItemKey = "xp_10_30m", ChancePercent = 101 },
					{ BossId = "*", ItemKey = "xp_10_30m", ChancePercent = 12.5 },
				}
			do
				expect(spec({ Type = "BossDrop", DurationSeconds = HOUR, Config = bad })).to.equal(
					nil
				)
			end
		end)

		it("validates sales: 5-90 %, real paid hammers only, de-duplicated", function()
			local hammer = paidHammer()
			local parsed = spec({
				Type = "StoreDiscount",
				DurationSeconds = HOUR,
				Config = { Percent = 20, HammerIds = { hammer.Id, hammer.Id } },
			}) :: EventRules.Spec
			expect(parsed.Config.Percent).to.equal(20)
			expect(#(parsed.Config.HammerIds :: { string })).to.equal(1)
			local badSales: { { [string]: unknown } } = {
				{ Percent = 95 },
				{ Percent = -10 },
				{ Percent = 100 },
				{ Percent = 20, HammerIds = { "fake_hammer" } },
				{ Percent = 20, HammerIds = { "squeaky_hammer" } }, -- free hammer
				{ Percent = 20, HammerIds = "all" },
			}
			for _, bad in badSales do
				expect(spec({ Type = "StoreDiscount", DurationSeconds = HOUR, Config = bad })).to.equal(
					nil
				)
			end
		end)
	end)

	describe("EventRules active events and timing", function()
		it("treats an event as active from its start until (not including) its end", function()
			local event = record("a", "XpBoost", { Multiplier = 2 }, NOW, NOW + HOUR)
			expect(EventRules.isActive(event, NOW - 1)).to.equal(false)
			expect(EventRules.isActive(event, NOW)).to.equal(true)
			expect(EventRules.isActive(event, NOW + HOUR - 1)).to.equal(true)
			expect(EventRules.isActive(event, NOW + HOUR)).to.equal(false)
		end)

		it("finds the next start or end", function()
			local events = {
				record("a", "XpBoost", { Multiplier = 2 }, NOW - HOUR, NOW + 50),
				record("b", "XpBoost", { Multiplier = 2 }, NOW + 20, NOW + HOUR),
			}
			expect(EventRules.secondsUntilChange(events, NOW)).to.equal(20)
			expect(EventRules.secondsUntilChange({}, NOW)).to.equal(nil)
		end)

		it("moves ended events into the history, newest first and bounded", function()
			local store: EventRules.Store = {
				Events = {
					record("old", "XpBoost", { Multiplier = 2 }, NOW - 2 * HOUR, NOW - HOUR),
					record("live", "XpBoost", { Multiplier = 2 }),
				},
				History = {},
			}
			expect(EventRules.prune(store, NOW)).to.equal(true)
			expect(#store.Events).to.equal(1)
			expect(store.Events[1].Id).to.equal("live")
			expect(store.History[1].Id).to.equal("old")
			expect(store.History[1].StoppedByName).to.equal(nil)
			expect(EventRules.prune(store, NOW)).to.equal(false)
		end)

		it("records who stopped an event and when", function()
			local entry =
				EventRules.toHistory(record("x", "XpBoost", { Multiplier = 2 }), NOW, "Mod")
			expect(entry.EndTime).to.equal(NOW)
			expect(entry.StoppedByName).to.equal("Mod")
		end)
	end)

	describe("EventRules effects", function()
		it("uses the highest XP multiplier instead of stacking them", function()
			local active = {
				record("a", "XpBoost", { Multiplier = 2 }),
				record("b", "XpBoost", { Multiplier = 3 }),
			}
			expect(EventRules.xpMultiplier(active)).to.equal(3)
			expect(EventRules.xpMultiplier({})).to.equal(1)
		end)

		it("offers drops for all bosses, a named boss, or its outdoor event copy", function()
			local active = {
				record(
					"all",
					"BossDrop",
					{ BossId = "*", ItemKey = "xp_10_30m", ChancePercent = 10 }
				),
				record(
					"bug",
					"BossDrop",
					{ BossId = "production_bug", ItemKey = "beginner_bundle", ChancePercent = 50 }
				),
				record("xp", "XpBoost", { Multiplier = 2 }),
			}
			local office = EventRules.dropsFor(active, "deadline_boss", nil)
			expect(#office).to.equal(1)
			expect(office[1].Chance).to.equal(0.1)
			expect(#EventRules.dropsFor(active, "production_bug", nil)).to.equal(2)
			expect(#EventRules.dropsFor(active, "custom_event_ev1_1", "production_bug")).to.equal(2)
			-- An admin's custom boss only gets "all bosses" drops.
			expect(#EventRules.dropsFor(active, "custom_123_4567", nil)).to.equal(1)
		end)

		it("gives each hammer the biggest sale that covers it", function()
			local hammer = paidHammer()
			local active = {
				record("all", "StoreDiscount", { Percent = 10, HammerIds = {} }),
				record("one", "StoreDiscount", { Percent = 30, HammerIds = { hammer.Id } }),
			}
			expect(EventRules.discountPercent(active, hammer.Id)).to.equal(30)
			expect(EventRules.discountPercent(active, "some_other_hammer")).to.equal(10)
			expect(EventRules.discountPercent({}, hammer.Id)).to.equal(0)
		end)

		it("discounts prices safely", function()
			expect(EventRules.discountedPrice(100, 20)).to.equal(80)
			expect(EventRules.discountedPrice(75, 90)).to.equal(7)
			expect(EventRules.discountedPrice(1, 90)).to.equal(1) -- never free
			expect(EventRules.discountedPrice(0, 50)).to.equal(0) -- free stays free
			expect(EventRules.discountedPrice(100, 150)).to.equal(10) -- capped at 90 %
			expect(EventRules.discountedPrice(100, -20)).to.equal(100) -- never more expensive
		end)
	end)

	describe("EventRules outdoor bosses", function()
		local function spawnEvent(
			id: string,
			locationId: string,
			quantity: number,
			startTime: number
		): EventRules.Record
			return record(
				id,
				"BossSpawn",
				{ BossId = "production_bug", LocationId = locationId, Quantity = quantity },
				startTime,
				NOW + HOUR
			)
		end

		it("places the requested number of bosses with event ids", function()
			local spawns = EventRules.bossSpawns({ spawnEvent("e1", "GardenPath", 3, NOW) }, {})
			expect(#spawns).to.equal(3)
			for _, entry in spawns do
				expect(EventRules.isEventBossId(entry.Id)).to.equal(true)
				-- Open to everyone, drawn like custom bosses.
				expect(CustomBossRules.isCustomId(entry.Id)).to.equal(true)
				expect(entry.EventId).to.equal("e1")
			end
		end)

		it("shares a location's slots between events, oldest first, without overlaps", function()
			local active = EventRules.active({
				spawnEvent("late", "MainWalkway", 4, NOW - 10),
				spawnEvent("early", "MainWalkway", 3, NOW - 100),
			}, NOW)
			local spawns = EventRules.bossSpawns(active, {})
			expect(#spawns).to.equal(
				#(EventRules.location("MainWalkway") :: EventConfig.Location).Slots
			)
			local early = 0
			for index, entry in spawns do
				if entry.EventId == "early" then
					early += 1
				end
				for other = index + 1, #spawns do
					local distance = (entry.Position - spawns[other].Position).Magnitude
					expect(distance >= EventConfig.MinBossSpacing).to.equal(true)
				end
			end
			expect(early).to.equal(3)
		end)

		it("skips slots too close to another boss", function()
			local location = EventRules.location("BackLoop") :: EventConfig.Location
			local spawns = EventRules.bossSpawns(
				{ spawnEvent("e", "BackLoop", 4, NOW) },
				{ location.Slots[1] }
			)
			expect(#spawns).to.equal(3)
		end)

		it("builds an event boss from its office boss, marked as an event boss", function()
			local spawn = EventRules.bossSpawns({ spawnEvent("e", "GardenPath", 1, NOW) }, {})[1]
			local definition = EventRules.bossDefinition(spawn) :: BossConfig.BossDefinition
			local base = BossConfig.ById.production_bug
			expect(definition.Id).to.equal(spawn.Id)
			expect(definition.MaxHealth).to.equal(base.MaxHealth)
			expect(definition.ScoreReward).to.equal(base.ScoreReward)
			expect(definition.CoinReward).to.equal(base.CoinReward)
			expect(definition.DamageTakenMultiplier).to.equal(base.DamageTakenMultiplier)
			expect(definition.Custom).to.equal(true)
			expect(definition.Event).to.equal(true)
			expect(definition.LookId).to.equal("production_bug")
		end)
	end)

	describe("EventRules saved data", function()
		it("keeps valid events and drops broken or duplicate ones", function()
			local good = record("ev1", "XpBoost", { Multiplier = 2 })
			local saved: { unknown } = {
				good,
				good,
				{ Id = "bad", Type = "XpBoost", Config = { Multiplier = 99 } },
				"nonsense",
			}
			local store = EventRules.parseStore({ Events = saved, History = { { Id = "h" } } })
			expect(#store.Events).to.equal(1)
			expect(store.Events[1].Id).to.equal("ev1")
			expect(#store.History).to.equal(0)
			expect(#EventRules.parseStore(nil).Events).to.equal(0)
		end)

		it("bounds the number of saved events", function()
			local many = {}
			for index = 1, EventConfig.MaxEvents + 5 do
				table.insert(many, record("ev" .. index, "XpBoost", { Multiplier = 2 }))
			end
			expect(#EventRules.parseStore({ Events = many }).Events).to.equal(EventConfig.MaxEvents)
		end)

		it("round-trips a public view for clients", function()
			local view = EventRules.publicView(
				record("ev", "StoreDiscount", { Percent = 25, HammerIds = {} })
			)
			local parsed = EventRules.parsePublic(view) :: EventRules.PublicEvent
			expect(parsed.Percent).to.equal(25)
			expect(EventRules.publicDiscount({ parsed }, "any_hammer", NOW)).to.equal(25)
			expect(EventRules.parsePublic({ Id = "x" })).to.equal(nil)
		end)
	end)

	describe("EventRules text", function()
		it("formats countdowns", function()
			expect(EventRules.countdown(5 * HOUR + 2 * 60 + 3)).to.equal("05:02:03")
			expect(EventRules.countdown(2 * 86400 + 60)).to.equal("2d 00:01:00")
			expect(EventRules.countdown(-5)).to.equal("00:00:00")
		end)

		it("summarises every event type", function()
			expect(EventRules.summary({ Type = "XpBoost", Config = { Multiplier = 2 } })).to.equal(
				"2x XP from bosses"
			)
			expect(EventRules.summary({
				Type = "StoreDiscount",
				Config = { Percent = 20, HammerIds = {} },
			})).to.equal("20% off every hammer in the Hammer Shop")
			for _, eventType in EventConfig.Types do
				expect(EventConfig.TypeInfo[eventType]).never.to.equal(nil)
			end
		end)
	end)

	describe("EventConfig", function()
		it(
			"keeps every outdoor slot inside the grounds, spaced apart and far from office bosses",
			function()
				local campus = ArenaConfig.Campus
				local all: { Vector3 } = {}
				for _, location in EventConfig.Locations do
					expect(#location.Slots >= EventConfig.MaxBossQuantity).to.equal(true)
					for _, slot in location.Slots do
						expect(slot.X > campus.Boundary.MinX and slot.X < campus.Boundary.MaxX).to.equal(
							true
						)
						expect(slot.Z > campus.Boundary.MinZ and slot.Z < campus.Boundary.MaxZ).to.equal(
							true
						)
						table.insert(all, slot)
					end
				end
				for index, slot in all do
					for other = index + 1, #all do
						expect((slot - all[other]).Magnitude >= EventConfig.MinBossSpacing).to.equal(
							true
						)
					end
					for _, office in ArenaConfig.BossSpawns do
						expect((slot - office.Position).Magnitude >= EventConfig.MinBossSpacing).to.equal(
							true
						)
					end
				end
			end
		)

		it("only offers real boss looks and real drop items", function()
			for _, bossId in EventConfig.BossLookIds do
				expect(BossConfig.ById[bossId]).never.to.equal(nil)
			end
			for _, key in EventConfig.DropItems do
				expect(StoreConfig.ByKey[key]).never.to.equal(nil)
				expect(StoreConfig.ByKey[key].Kind).never.to.equal("MysteryHammer")
			end
			expect(EventConfig.MaxDiscountPercent < 100).to.equal(true)
			expect(EventConfig.MinDiscountPercent > 0).to.equal(true)
		end)
	end)
	describe("EventRules egg hunts and history status (2026-10-08)", function()
		it("validates an egg hunt: tier, interval from the list, eggs at once", function()
			local hunt = spec({
				Type = "EggHunt",
				DurationSeconds = 2 * HOUR,
				Config = { EggRarity = "Rare", IntervalMinutes = 5, MaxEggs = 5 },
			}) :: EventRules.Spec
			expect(hunt).never.to.equal(nil)
			expect(hunt.Name).to.equal("RARE EGG HUNT")
			expect(hunt.Config.MaxEggs).to.equal(5)
			local bad: { { [string]: unknown } } = {
				{ EggRarity = "Golden", IntervalMinutes = 5, MaxEggs = 1 },
				{ EggRarity = "Rare", IntervalMinutes = 7, MaxEggs = 1 },
				{
					EggRarity = "Rare",
					IntervalMinutes = 5,
					MaxEggs = EventConfig.MaxEggHuntEggs + 1,
				},
				{ EggRarity = "Rare", IntervalMinutes = 5, MaxEggs = 0 },
			}
			for _, config in bad do
				expect(spec({ Type = "EggHunt", DurationSeconds = HOUR, Config = config })).to.equal(
					nil
				)
			end
		end)

		it("lists running egg hunts with their timing", function()
			local hunts = EventRules.eggHunts({
				record(
					"h",
					"EggHunt",
					{ EggRarity = "Mythical", IntervalMinutes = 10, MaxEggs = 2 }
				),
				record("x", "XpBoost", { Multiplier = 2 }),
			})
			expect(#hunts).to.equal(1)
			expect(hunts[1].Rarity).to.equal("Mythical")
			expect(hunts[1].IntervalSeconds).to.equal(600)
			expect(EventRules.summary({
				Type = "EggHunt",
				Config = { EggRarity = "Rare", IntervalMinutes = 5, MaxEggs = 3 },
			})).to.equal("A Rare Egg outside every 5 min (up to 3 at once)")
		end)

		it("records why an event ended", function()
			local event = record("e", "XpBoost", { Multiplier = 2 }, NOW, NOW + HOUR)
			expect(EventRules.toHistory(event, NOW + HOUR, nil).Status).to.equal("Completed")
			expect(EventRules.toHistory(event, NOW + 60, "Mod").Status).to.equal("Stopped")
			expect(EventRules.toHistory(event, NOW - 60, "Mod").Status).to.equal("Cancelled")
			expect(EventRules.toHistory(event, NOW + 60, "Mod", true).Status).to.equal("Removed")
			expect(EventRules.toHistory(event, NOW + 60, "Mod").PlannedEndTime).to.equal(NOW + HOUR)
		end)

		it("keeps the new history fields through a save", function()
			local entry =
				EventRules.toHistory(record("e", "XpBoost", { Multiplier = 2 }), NOW, "Mod", true)
			local parsed = EventRules.parseHistoryEntry(entry) :: EventRules.HistoryEntry
			expect(parsed.Status).to.equal("Removed")
			expect(parsed.PlannedEndTime).to.equal(NOW + HOUR)
		end)
	end)
end
