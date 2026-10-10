# Event of the Day

Added 2026-10-10 (major update Phase 5a, `docs/MAJOR_GAME_UPDATE.md` §9; decisions D10, D12, D13 in
`docs/UPDATE_IMPLEMENTATION_PLAN.md`). Every UTC day one event runs in every server. Players earn
points from what they already do and get paid at three tiers. Admin events (2x XP, Egg Hunts, sales,
outdoor bosses, docs/EVENTS.md) are separate and stay as they are; both can run at once.

Code: `Config/DailyEventConfig` (the rotation, points, tiers), `Shared/DailyEventRules` (schedule,
points, tiers, saved-state checks; unit-tested), `Services/DailyEventService` (counting, paying),
`Services/ActivityService` (the activity feed it shares with quests), `Controllers/QuestController`
(the 🌟 Today tab and cards).

## The rotation (`DailyEventConfig.Rotation`, provisional)
Day *n* (days since 1970-01-01 UTC) runs `Rotation[n % 5 + 1]`, so the order repeats every 5 days and
every server agrees without storing anything.

| Event | Points |
|---|---|
| 🎉 Boss Celebration | 3 per boss defeated, 4 per Zen |
| 🧘 Zen Challenge | 10 per Zen, 1 per boss defeated |
| 🏓 Pickleball Day | 15 per pickleball match, +10 for a win, 1 per boss defeated |
| 💰 Coin Rush | 1 per 20 coins from bosses, 1 per boss defeated |
| 🛋️ Office Makeover | 4 per piece of furniture placed, 6 per office visited, 1 per boss defeated |

Every event can be finished alone (each counts at least one solo activity; spec-checked). What counts is
the same as for quests (docs/QUESTS.md "What counts"): rewarded defeats and their coins, rewarded Zen,
rewarded (not friendly) pickleball matches, furniture placed, another player's office reached, pets
hatched.

## Tiers (the same every day, provisional)
| Tier | Points | Reward |
|---|---|---|
| 1 | 30 | 100 coins, 250 XP |
| 2 | 80 | 250 coins, 600 XP |
| 3 | 150 | 500 coins, 1,200 XP, an office supply (winners' pool) |

Roughly: tier 1 is 10 bosses on Boss Celebration or 2 pickleball matches on Pickleball Day; tier 3 is a
long but normal session.

## Rules
- A tier is **paid the moment it's reached** (no claim button), with a "🎉 TIER 2 OF 3!" card. It's
  marked paid in the session-locked saved data first, so it pays once, also across rejoins.
- Points start over at **00:00 UTC**. Nothing carries over and nothing is lost: tiers were already paid.
  Missing a day costs nothing.
- Late joins and server restarts: the event comes from the date, and points are saved with the profile.

## What players see
- On join, a card: "🎉 TODAY: BOSS CELEBRATION", what the day is about, how points are earned, and
  **SEE GOALS**.
- 📋 Quests → **🌟 Today** (the first tab): the event, how points are earned, the time left, your
  points with a bar to the next tier, and the three tiers (✅ when paid).

## Security
No client → server remote. Points come only from the activity feed (server results); the server
pays from `DailyEventConfig`. `DailyEvent.Rewarded` (server → one client) is display only.

## Saved data (schema v14, docs/DATA_SCHEMA.md)
`DailyEvent = { DayKey, Points, Tiers }`.

## Performance
No per-frame work. Each activity adds a number; one `Profile.Sync` per player per frame at most. One
wait per server until midnight to start the new day.
