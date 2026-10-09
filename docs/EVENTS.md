# Events

Added 2026-10-08. Admins create **events** in the Admin Panel's **Events** tab. Events start and end
on their own, apply in **every server**, and survive server restarts. Players see what is running in
the **🎉 EVENTS** chip under the Menu button and in the Player Panel's **Events** tab, and get a short
notice when an event starts or ends.

Code: `Config/EventConfig` (choices and limits), `Shared/EventRules` (pure rules, unit-tested),
`Services/EventService` (storage, timing, effects), `Services/AdminService` (permission checks),
`Controllers/EventController` (chip and list), `Controllers/AnnouncementController` (notices),
`Controllers/AdminController` (Events tab).

## Event types
| Type | Admin picks | Effect while active |
|---|---|---|
| ⚡ **Experience Event** (`XpBoost`) | multiplier: 1.5x, 2x, 3x, 4x or 5x | Boss XP × multiplier. Applied in `RewardService` on top of the normal formula (score × `XpRewardMultiplier` × XP boost). Score, coins and the leaderboard's Score are unchanged. |
| 👹 **Outdoor Boss Event** (`BossSpawn`) | office boss (not the CEO), location, 1-4 bosses | Copies of that boss stand outside. They use the normal boss system (hits, damage, crits, stress, score, coins, XP, buff drops, respawn 5 s after a defeat). They're open to everyone, labelled "🎉 Name (Event)", don't count toward unlocks and vanish when the event ends. |
| 🎁 **Boss Drop Event** (`BossDrop`) | all bosses or one office boss; item; chance 1-100 % | Each player who qualifies for a defeat (≥ 10 % of the boss's HP, the normal reward rule) gets one server-side roll per active drop event. A hit puts the item in their **Bag** (a bundle goes in as its separate boosts), and the Victory Card says "EVENT DROP: …". A boss-specific event also covers that boss's outdoor event copies. |
| 💰 **Hammer Shop Sale** (`StoreDiscount`) | 5-90 % off; all hammers or chosen ones | The **coin** price of hammers in the Hammer Shop. The shop shows "Buy 80 (-20%)"; the server charges its own sale price. |
| 🥚 **Egg Hunt** (`EggHunt`, 2026-10-08) | egg tier (Common, Rare or Mythical); every 2 / 5 / 10 / 15 / 30 / 60 min; up to 1-5 eggs at once | An egg of that tier appears at a free outdoor egg spot every interval while fewer than the maximum of the hunt's eggs are out. It uses the normal world-egg code (one claim wins, into the Bag). There's no announcement per egg (the event's start notice says it), and unclaimed hunt eggs vanish when the hunt ends. The normal 2-hour eggs carry on alongside (docs/PETS.md). |

Drop items: 30-min XP / Damage / Crit Damage boosts (the bundles' tiers), Beginner Bundle, Stress
Reliever Package, and Common / Rare pet eggs, which makes it a "pet drop event" (docs/PETS.md)
(`EventConfig.DropItems`). The Mystery Hammer can't be dropped: it's a paid random item.

**Why sales are coin-only:** Robux prices are set on each Developer Product in the Creator Hub and
Roblox charges that price, so a game can't discount them at runtime. The Robux store keeps its prices
during a sale.

### Outdoor locations (`EventConfig.Locations`)
| Location | Slots (boss centres) |
|---|---|
| Main Walkway (outside) | x 0, z 58 / 72 / 86 / 100 |
| Garden Path | cross walk x -16 / -30 / -44 (z 88), and the west path (-97, 66) |
| Coffee Corner Path | cross walk x 16 / 30 / 44 (z 88), and the east path (97, 66) |
| Behind the Building | back loop, x -42 / -14 / 14 / 42 (z -63) |

Slots sit on walkways that are kept free of props, at least 14 studs apart and far from the office
bosses (spec-checked), so one swing reaches one boss. If two events use the same location, the older
event gets its slots first and the newer one gets the rest. A slot within 14 studs of a custom boss is
skipped. Either way, fewer bosses spawn than asked for rather than overlapping.

## Several events at once
Different kinds combine freely, for example 2x XP + a 20 % sale + an outdoor boss event. Events of
the same kind never multiply:
- **XP:** the highest active multiplier applies (2x and 3x → 3x, not 6x).
- **Sales:** each hammer gets the biggest discount that covers it.
- **Drops:** each active drop event rolls on its own, once per qualifying player per defeat.
- **Outdoor bosses:** events share slots as above.

At most 12 events can be running or scheduled at once (`EventConfig.MaxEvents`).

## Timing
- **Start now** for 30 minutes, 1 hour, 6 hours, 1 day, 3 days or 7 days, or
- **Schedule:** a start and end in the admin's local time (`YYYY-MM-DD HH:MM`), stored as UTC unix
  seconds. Rules: it can't start in the past, can start at most 90 days ahead, must end after it
  starts, and can last at most 14 days.

Each server checks for starts and ends in one loop: it wakes when the next start or end is due, and
at least every 5 seconds. A check sends nothing to players unless the set of active events changed.
When an event ends, its effects simply stop applying: XP, prices and drops go back to normal and its
bosses vanish. A fight in progress with an event boss ends without rewards. Nobody has to clean up.

**Admin actions** (Events tab; every one asks "…?" [Cancel] [Confirm] first, except Edit):
- **Edit:** loads the event into the form; **SAVE CHANGES** replaces its settings, name and end
  (and start, if it hasn't started). Its id and creator stay.
- **Start now:** a scheduled event starts at once and keeps its end time.
- **Stop / Cancel:** ends a running event now, or cancels a scheduled one.
- **Force remove:** like Stop, but if saving to the DataStore fails, the event still stops **in this
  server** at once (its bosses and hunt eggs go, drops, prices and XP are normal again), and the admin
  is told to retry so other servers follow.
- **Delete** (history): removes an ended event from the history.

The history keeps each event's name, type, what it did, start, actual end, planned end, how long it
ran, who created it, and **status**: Completed, Stopped, Cancelled (before it started) or Removed,
with who stopped it and when. Entries from before 2026-10-08 show Completed or Stopped.

## Storage
DataStore `Events`, key `Global` (`AdminConfig.EventStoreName` / `EventKey`):
```lua
{
  Events = { Record },        -- running and scheduled, at most 12
  History = { HistoryEntry }, -- ended or stopped, newest first, at most 20
}
Record = { Id, Name, Type, StartTime, EndTime, Config, CreatedBy, CreatedByName, CreatedAt }
HistoryEntry = { Id, Name, Type, StartTime, EndTime, Summary, CreatedByName, StoppedByName? }
Config = { Multiplier? } | { BossId, LocationId, Quantity } | { BossId, ItemKey, ChancePercent }
       | { Percent, HammerIds }   -- HammerIds empty = every hammer
```
- Changes use `UpdateAsync`, so two admins at once can't lose each other's events, and ended events
  are moved to the history at the same time. A MessagingService ping (topic `Events`) tells other
  servers to reload. They also reload every 5 minutes, and a restarted server loads the key on boot.
- Everything loaded is validated (`EventRules.parseStore`). Broken entries are dropped and the lists
  are bounded. If loading fails, the server keeps the events it already has.
- **Not player data:** player saves are unchanged by events. Drops go into the existing Bag.
- In Studio without "Studio Access to API Services", changes apply to that server only (a toast says
  so), so everything can still be tried out.

## Security
Every event action goes through `Admin.Events` (docs/REMOTE_CONTRACTS.md). The server re-checks
everything:
- sender is an admin (`Lib/AdminAuth`, cached on join); non-admins are rejected and logged;
- the payload is parsed by `EventRules.parseSpec`: known type, choices from the lists only, whole
  numbers in range, at most 11 hammer ids (known, paid ones only), valid times;
- a typed event name is Roblox-filtered for everyone and refused if the filter changes it. With no
  name, the server picks one ("2X EXPERIENCE");
- clients never send multipliers, chances, prices or positions that the server uses. Gameplay asks
  `EventService` (`xpMultiplier`, `dropsFor`, `hammerPrice`), which reads only the saved events;
- `Shop.BuyHammer`'s optional second argument (the price the player saw) can only make the server
  refuse a purchase, never lower the price.

Every accepted action prints an `[Admin] <name> (<id>) created event "…" (XpBoost: 2x XP from
bosses) from 2026-10-08 10:00 UTC to 2026-10-09 10:00 UTC` line. Each server also prints
`[Event] started/ended "…"` when an event begins or ends there.

## Players' view
- **Chip** "🎉 2 EVENTS" under the Menu button (top-left), only while something runs. Tap it for a
  short list: icon, name, "Ends in 01:24:32" and what it does. The list is at most half the screen
  and scrolls beyond that. Countdowns tick only while it's open.
- **Player Panel → Events:** the same, as cards with live countdowns.
- **Notices:** "🎉 EVENT STARTED! / 2X EXPERIENCE / 2x XP from bosses" and "EVENT ENDED / … has
  ended." in the notification card (top-centre, auto-hides after 6 s, OK to close, queued). Players
  who join mid-event get the list but no "started" notice.

## Adding an event type later
1. Add the type to `EventRules.EventType`, `EventRules.isType`, `EventConfig.Types` and
   `EventConfig.TypeInfo`.
2. Validate its settings in `EventRules.parseConfig`, and describe it in `EventRules.summary` and
   `defaultName`.
3. Add an effect query to `EventRules`, expose it from `EventService`, and call it at the one place
   in gameplay that needs it.
4. Add its fields to the Admin panel's Events tab (`eventSettings` and the create form), plus specs in
   `tests/Unit/Shared/EventRules.spec.luau`.

Ideas that fit this pattern (not built): Coin Rain (coin multiplier on defeats, highest wins), Damage
Rush / Critical Hit (a global bonus in `BuffService.statsFor`), Stress Relief (relief multiplier in
`StressService`), Golden Boss (a `BossSpawn` variant with a reward multiplier), and Happy Hour /
Weekend / Holiday events, which are scheduled or themed versions of the existing types.
