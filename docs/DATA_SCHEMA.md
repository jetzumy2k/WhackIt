# Player Data Schema

Saved with [ProfileStore](https://github.com/MadStudioRoblox/ProfileStore) (`lm-loleris/profilestore@1.0.3`,
Apache-2.0, server-only Wally dependency) through `PlayerDataService`. Shape, defaults, migrations and
validation live in `src/server/lib/PlayerDataSchema.luau`; storage settings in
`src/server/config/DataConfig.luau`.

## Storage
| Setting | Value | Notes |
|---|---|---|
| DataStore name | `PlayerData` | **Permanent.** Changing it starts every player over. |
| Key | `Player_<UserId>` | One profile per Roblox account; UserId is also attached via `AddUserId` for erasure requests |
| Session locking | ProfileStore | One server owns a profile at a time, so progress can't be duplicated by joining two servers |
| Auto-save | ProfileStore | Periodic, plus on leave (`EndSession`) and server shutdown |

## Schema v19 (current)
```lua
type PlayerData = {
    SchemaVersion: number,        -- 11
    Score: number,                -- lifetime score (integer, 0..2^50); shown in leaderstats
    Stress: number,               -- Stress Meter, 0..GameConfig.MaxStress, carries over between sessions
    TotalHits: number,            -- accepted hammer hits (integer, 0..2^50)
    TotalBossesDefeated: number,  -- defeats the player was rewarded for (integer, 0..2^50)
    EquippedHammerId: string,     -- must exist in HammerConfig and be owned
    -- v2
    Coins: number,                -- spendable currency (integer, 0..2^50); never lowers Score
    OwnedHammers: {[string]: true}, -- bought hammers by id; free (Price 0) hammers are always owned
    BossDefeats: {[string]: number}, -- rewarded defeats per boss id; drives boss unlocks
    -- v3
    ZenLevel: number,             -- times the player reached Zen (integer, 0..2^50); boosts boss coins
    ZenArmed: boolean,            -- next Zen pays out; re-armed once stress climbs back to ZenRearmStress
    -- v4 (docs/STORE.md)
    Xp: number,                   -- drives Player Level; boosted by XP buffs (Score never is)
    Buffs: {[kind]: {Percent: number, SecondsLeft: number}}, -- "Xp" | "Damage" | "CritDamage"; play time left
    ProcessedPurchases: {string}, -- last 200 Robux PurchaseIds, so a receipt is granted only once
    MysteryHammers: {[id]: {Damage: number, BonusDamagePercent: number, CritDamagePercent: number}},
                                  -- "mystery_<n>"; Damage is the fixed base (35), the two % are rolled once
                                  -- when opened (BonusDamagePercent since v7)
    NextMysteryNumber: number,    -- next Mystery Hammer id number
    -- v5 (docs/ADMIN.md)
    AdminUnlocks: {[string]: true}, -- bosses an admin unlocked for this player (known BossConfig ids only)
    -- v6 (docs/STORE.md "Bag and gifts")
    Bag: {[productKey]: number},  -- unused store items: StoreConfig keys only, whole counts 1..100,000
    ClaimedGifts: {string},       -- last 200 gift ids put in the Bag, so an inbox gift lands once
    PendingGift: {RecipientUserId: number, ProductKey: string}?, -- the gift being bought right now
    -- v8 (docs/PETS.md)
    Pets: {[petId]: {Species: string, Rarity: string, Buffs: {{Kind: string, Percent: number}}, CreatedAt: number}},
                                  -- "pet_<n>"; buffs fixed when the egg went in, never rerolled
    NextPetNumber: number,        -- next pet id number (never reused)
    EquippedPetId: string,        -- "" = no pet out; must be an owned pet
    Incubation: {EggKey, Rarity, StartedAt, EndsAt, IncubatorIndex, Pet}?, -- egg incubating now (unix
                                  -- seconds) and the pet it will hatch (never sent to the client early)
    -- v9 (docs/UI.md "Settings")
    Settings: {[key]: boolean},   -- on/off player settings (Config/SettingsConfig), e.g. ReducedMotion
    -- v10 (docs/GAMEPLAY_RULES.md "Level rewards")
    LevelRewardsClaimed: number,  -- highest level whose level-up coins were paid (1..MaxLevel)
    Cosmetics: {Trail: string, Glow: string, Office: string}, -- picked level-reward looks
                                  -- ("" = default); Office since v11 (no migration: sanitize fills it)
    -- v11 (docs/OFFICES.md)
    Furniture: {[itemKey]: number}, -- Special furniture owned (Basic furniture is unlimited)
    OfficeLayout: {{Id, Item, X, Z, R}}, -- placed furniture, room-local whole studs, R 0/90/180/270
    NextOfficeItemId: number,     -- next layout id (never reused)
    OfficePrivacy: string,        -- "Public" | "Friends" | "Private"
    -- v12 (docs/PICKLEBALL.md)
    Recreation: {                 -- Shared/PickleballRules.Record
        Rating: number,           -- Elo, this season (starts at 1000, 100..4000)
        SeasonId: number,         -- the season the rating and Wins/Losses belong to
        Wins: number, Losses: number,           -- this season
        TotalWins: number, TotalLosses: number, -- all time
        DayKey: string,           -- UTC date "YYYY-MM-DD" the day counters belong to ("" = none)
        DayMatches: number,       -- rewarded matches that day (cap 10)
        DayOpponents: {[opponentsKey]: number}, -- rewarded matches per opponent set that day (cap 3)
    },
    ProcessedMatches: {string},   -- last 50 rewarded match ids (a match pays once)
    SeasonClaims: {number},       -- seasons whose prizes were handed out (last 24)
    Quests: {                     -- v13, docs/QUESTS.md (Shared/QuestRules.State)
        DayKey: string,           -- UTC date the daily quests belong to ("" = draw on next use)
        Daily: {{Id: string, Progress: number, Claimed: boolean}}, -- up to 3
        Rerolls: number,          -- rerolls used that day (0..1)
        DailyBonus: boolean,      -- that day's all-dailies bonus claimed
        WeekKey: string,          -- "W<weeks since Monday 1970-01-05>" ("" = draw on next use)
        Weekly: {{Id: string, Progress: number, Claimed: boolean}}, -- up to 3
        TutorialStep: number,     -- 1..#Tutorial+1 (past the end = done)
        TutorialProgress: number,
    },
    DailyEvent: {                 -- v14, docs/DAILY_EVENTS.md (Shared/DailyEventRules.State)
        DayKey: string,           -- UTC date the points belong to ("" = none yet)
        Points: number,           -- 0..100000 (may have fractions, e.g. from coins)
        Tiers: number,            -- tiers already paid that day (0..3)
    },
    Missions: {                   -- v15, docs/MISSIONS.md (Shared/MissionRules.Record)
        DayKey: string,           -- UTC date DayRewarded belongs to ("" = none yet)
        DayRewarded: number,      -- rewarded team missions that day (cap 3)
        Cleared: number,          -- all-time missions cleared
    },
    Showcase: {                   -- v16, docs/SHOWCASE.md (Shared/ShowcaseRules.State)
        Published: boolean,       -- the player's office is in the Showcase (mirror of the snapshot)
        PublishedAt: number,      -- unix seconds of the last publish (0 = never); the cooldown
        Liked: { number },        -- owners' UserIds liked, oldest first (at most 300)
        Hidden: { number },       -- owners' UserIds hidden by reporting (at most 100)
    },
    Contest: {                    -- v17, docs/CONTESTS.md (Shared/ContestRules.State)
        Entered: { number },      -- contest weeks entered (at most 6, oldest first)
        LastEnteredAt: number,    -- unix seconds of the last entry or update (the cooldown)
        Claimed: { number },      -- weeks whose prize was paid (at most 24)
        VoteWeek: number,         -- the week Voted belongs to (-1 = none)
        Voted: { number },        -- owners voted for that week (at most 500)
        VoteDay: number,          -- UTC day number VotesToday belongs to
        VotesToday: number,       -- entries dealt to vote on that day (0..30)
    },
    PetArena: {                   -- v18, docs/PET_ARENA.md (Shared/PetArenaRules.Record)
        DayKey: string,           -- UTC date the day counters belong to
        DayWins: number,          -- rewarded trainer wins that day (0..10)
        DayFirst: { string },     -- trainers beaten that day (first win pays double)
        Cleared: number,          -- highest trainer beaten ever (0..5)
        PlayerDay: number,        -- rewarded player battles that day (0..5)
        Opponents: { [string]: number }, -- that day's rewarded battles per opponent UserId (0..2)
        TotalWins: number,
    },
    Capsule: {                    -- v19, docs/CAPSULE.md (Shared/CapsuleRules.State)
        DayKey: string,           -- UTC date Spins belongs to
        Spins: number,            -- spins that day (0..10)
        TotalSpins: number,
    },
}
```
New players start from `PlayerDataSchema.template()`: `StartingScore`, `StartingStress`, `StartingCoins`,
zero counters, `DefaultHammerId`, nothing bought, no defeats.

### Migrations
| To | What it does |
|---|---|
| v1 | First versioned schema (data without `SchemaVersion` counts as v0) |
| v2 | `Coins = 0`, `OwnedHammers = {}`, `BossDefeats = { deadline_boss = TotalBossesDefeated }` (only the Deadline Boss existed in v1, so unlock progress carries over) |
| v3 | `ZenLevel = 0`, `ZenArmed = true` |
| v4 | `Xp = Score` (Player Level is unchanged), `Buffs = {}`, `ProcessedPurchases = {}`, `MysteryHammers = {}`, `NextMysteryNumber = 1` |
| v5 | `AdminUnlocks = {}` |
| v6 | `Bag = {}`, `ClaimedGifts = {}` (earlier purchases were already used) |
| v8 | Pets (2026-10-08): `Pets = {}`, `NextPetNumber = 1`, `EquippedPetId = ""`, `Incubation = nil`. Eggs are ordinary Bag items (`egg_common`, `egg_rare`, `egg_mythical`). |
| v10 | Level rework (2026-10-09): **no level is lost.** XP is raised to `max(Xp, LevelRules.scoreForLevel(min(oldLevel, 100)))`, where `oldLevel` is the old curve's `floor(sqrt(Xp / 600)) + 1` (`LevelRules.legacyLevelFor`); players at Level 10 or below keep their XP exactly. `LevelRewardsClaimed = that level` (no back-dated coins); `Cosmetics = {}`. XP only ever goes up, so the XP leaderboard keeps every player's order among themselves. |
| v11 | Offices (2026-10-09): `Furniture = {}`, `OfficePrivacy = "Public"`; no `OfficeLayout` yet, so sanitize gives the starting furniture (`FurnitureConfig.DefaultLayout`: desk, chair, plant). |
| v12 | Pickleball (2026-10-10): `Recreation` left empty (sanitize gives the starting record: rating 1000, no matches), `ProcessedMatches = {}`, `SeasonClaims = {}`. |
| v19 | Lucky Capsule Machine (2026-10-10): `Capsule` left empty, so sanitize gives no spins. |
| v18 | Pet Arena (2026-10-10): `PetArena` left empty, so sanitize gives no trainers beaten and no battles today. |
| v17 | Design contests (2026-10-10): `Contest` left empty, so sanitize gives nothing entered, voted or paid. |
| v16 | Office Showcase (2026-10-10): `Showcase` left empty, so sanitize gives nothing shared, liked or hidden. |
| v15 | Team missions (2026-10-10): `Missions` left empty, so sanitize gives no day, 0 rewarded, 0 cleared. |
| v14 | Event of the Day (2026-10-10): `DailyEvent` left empty, so sanitize gives no day, 0 points, 0 tiers. |
| v13 | Quests (2026-10-10): `Quests` left empty, so sanitize gives the tutorial's first step and no daily or weekly quests; `QuestService` draws them on first use. |
| v9 | Settings (2026-10-09): `Settings = {}`; sanitize fills every known setting with its default (`ReducedMotion = false`). |
| v7 | Mystery Hammers (2026-10-08): each saved hammer without `BonusDamagePercent` gets `StoreConfig.Mystery.LegacyBonusDamagePercent` (15); `sanitize` then sets `Damage` to the fixed base (35). Old hammers rolled 20-35 damage, so every one ends up at least as strong. The crit roll is kept. The bump also stops older servers, which would drop the new field, from loading and saving this data. |

Sanitizing v4: unknown buff kinds are dropped and buff values clamped. Purchase ids must be strings.
Mystery Hammers are paid for, so out-of-range stats are **clamped, never deleted** (`HammerRules.clampRoll`:
base damage fixed at 35, bonus 15-25 %, crit 5-10 %; a missing or broken bonus gets the legacy 15 %).
An equipped Mystery Hammer must be one the player owns.

Who writes what (server only): `SessionService.addScore` → `Score`; `SessionService.addCoins` /
`trySpendCoins` → `Coins`; `SessionService.setEquippedHammer` → `EquippedHammerId`; `StressService.relieve`
→ `Stress`, `ZenLevel`, `ZenArmed` (Zen and idle regen); `CombatService` → `TotalHits`; `RewardService` → `TotalBossesDefeated`, `BossDefeats`;
`ShopService` → `OwnedHammers`; `SessionService.addXp` → `Xp`; `BuffService` → `Buffs`;
`PurchaseService` → `ProcessedPurchases`, `MysteryHammers`, `NextMysteryNumber`;
`AdminService` → `Xp` (Set Level, via `SessionService.setXp`) and `AdminUnlocks`.

Sanitizing v5: `AdminUnlocks` keeps only known boss ids with value `true`.
Sanitizing v6: `Bag` keeps known product keys with counts of at least 1 (rounded down);
`PendingGift` is dropped unless it names a giftable product and a whole, positive UserId.

Writers for v6: `PurchaseService` → `Bag` (bought items; a bundle as its separate boosts),
`PendingGift` (cleared after a gift); `StoreService` → `PendingGift`; `BagService` → `Bag` (Use /
Open), `MysteryHammers` (opened); `GiftService` → `Bag`, `ClaimedGifts`; `RewardService` → `Bag`
(boss drops and event drops).

Gift inboxes are **not** player data: DataStore `GiftInbox`, key `Inbox_<UserId>`, a list of
`{ GiftId, ProductKey, FromUserId, FromName }` validated by `Shared/BagRules.parseInbox`.

Admin-created bosses are **not** player data: they live in their own DataStore `CustomBosses`
(key `Global`), validated on every load by `Shared/CustomBossRules.parseList` (docs/ADMIN.md).
Each record also has `RespawnMode` (`"Continuous"` or `"Once"`) and `Defeated` (true only for a
beaten `"Once"` boss); records saved before 2026-10-07 have neither and load as `"Continuous"`, not
defeated.

Sanitizing v8: every pet with a known rarity and at least one valid buff is kept (buffs clamped to
0-25 %, at most 2, a species no longer in the config kept as is); `EquippedPetId` must name an owned
pet; `NextPetNumber` is raised past every used id; a broken `Incubation` is dropped and **its egg goes
back into the Bag**. Writers: `PetService` → `Pets`, `NextPetNumber`, `EquippedPetId`, `Incubation`,
`Bag` (eggs into incubators, world eggs claimed).

Sanitizing v9: `Settings` is rebuilt by `SettingsRules.sanitize`: every setting in `Config/SettingsConfig`
is present (its default when missing or not a boolean); settings this server doesn't know are **kept**
if their key is id-like (≤ 32 characters) and their value a boolean, at most 32 of them, so a newer
server's setting survives a rolling update. **Adding a setting needs no migration.** Writer:
`SettingsService` → `Settings` (via `Settings.Set`).

Sanitizing v10: `LevelRewardsClaimed` a whole number clamped to 1..`MaxLevel`; `Cosmetics` keeps known
trail / glow ids (even ones the level no longer unlocks: they just show the default look until it does,
`LevelRewardRules.sanitizeCosmetics`). Writers: `SessionService.addXp` / `setXp` → `LevelRewardsClaimed`;
`LevelRewardService` → `Cosmetics`.
Sanitizing v11: `Furniture` keeps known **Special** keys with whole counts 1..1,000
(`FurnitureRules.sanitizeOwned`). `OfficeLayout`: missing → the starting layout; otherwise every entry
is re-checked in saved order (`FurnitureRules.parseLayout`) and dropped if broken, unknown, out of the
room, in the door, overlapping an earlier one, beyond 60, a duplicate id or not owned; the rest are kept
exactly (an emptied office stays empty). `NextOfficeItemId` is at least one past every kept id.
An unknown `OfficePrivacy` → Public. Writers: `OfficeService` → `OfficeLayout`, `NextOfficeItemId`,
`OfficePrivacy`, `Furniture` (admin rewards via `grantSpecial`).
Sanitizing v12: `Recreation` field by field (`PickleballRules.sanitizeRecord`): the rating a whole number
clamped to 100..4,000 (broken → 1,000), counters whole and ≥ 0; a broken `DayKey` drops the day's
counters; `DayOpponents` keeps at most 32 keys of digits and dashes. A new season or UTC day is applied
when the record is used (`RecreationService`), not on load. `ProcessedMatches`: strings of 1-64
characters, the newest 50. `SeasonClaims`: whole numbers ≥ 0, the newest 24. Writers:
`RecreationService` → all three, `Furniture` (office-supply drops) and `Coins` (fees, refunds, rewards
through `SessionService`). A player who leaves mid-match is recorded just before their data is saved
for the last time (`PlayerDataService.beforeRelease`).

Sanitizing v13 (`QuestRules.sanitize`): quest ids must exist in `QuestConfig` with the right kind
(unknown, duplicate or wrong-kind entries are dropped), progress whole and clamped to 0..target, at most
3 per list; a broken `DayKey` / `WeekKey` or an empty list means "draw again"; `Rerolls` 0..1;
`TutorialStep` 1..#Tutorial+1. Writers: `QuestService` only (progress from other services' results,
claims, rerolls), plus `Coins`, `Xp` and `Furniture` for rewards.

Sanitizing v14 (`DailyEventRules.sanitize`): a broken `DayKey` resets the whole entry; `Points` clamped
to 0..100,000, `Tiers` whole and clamped to 0..3. Writer: `DailyEventService` only (plus `Coins`, `Xp`
and `Furniture` for tier rewards).

Sanitizing v15 (`MissionRules.sanitizeRecord`): counters whole and ≥ 0; a broken `DayKey` drops the
day's count. Writer: `MissionService` only (plus `Coins`, `Xp`, `Furniture` and `Bag` for rewards).

Sanitizing v17 (`ContestRules.sanitizeState`): weeks whole and ≥ 0, owner ids whole and non-zero,
duplicates dropped, lists cut to their caps, `VotesToday` clamped to 0..30. Writer: `ContestService` only
(plus `Coins`, `Xp` and `Furniture` for prizes). Contest entries and results are not player data:
DataStore `DesignContest` and OrderedDataStores `Contest_*` (docs/CONTESTS.md).

Sanitizing v16 (`ShowcaseRules.sanitizeState`): ids whole and non-zero, duplicates dropped, the lists cut
to their caps (oldest first). Writer: `ShowcaseService` only.

The Office Showcase itself is **not** player data: DataStore `OfficeShowcase` (keys `Office_<UserId>`:
the snapshot, likes, visits and moderation; `Featured`: the admin-picked list) and OrderedDataStores
`Showcase_Newest`, `Showcase_Top_<weekId>` and `Showcase_Review`, keyed by UserId (docs/SHOWCASE.md).

Player history and the admin audit log are **not** player data either: DataStore `PlayerHistory`,
keys `Player_<UserId>` (last 200 entries) and `Admin_<YYYYMMDD>` (up to 500 per UTC day), written
in batches by `Services/HistoryService` (docs/ADMIN.md "History tab"). They did not change the profile
schema (v8 at the time).

Events are **not** player data: DataStore `Events`, key `Global`, validated by
`Shared/EventRules.parseStore` on every load (docs/EVENTS.md).

Office boss drop rates are **not** player data either: DataStore `DropRates`, key `Global`, one
`DropRateRules.Settings` table validated by `Shared/DropRateRules.parse` on every load. No saved value
means the `Config/DropRateConfig` defaults; an invalid one is ignored (current settings kept).

## Load rules (`PlayerDataService`)
1. `StartSessionAsync` retries until it succeeds or the player leaves.
2. **Load failed → kick** with a friendly "please rejoin" message. The player never plays on defaults,
   so defaults can never be saved over real progress.
3. **Migrate** from the stored `SchemaVersion` (missing = v0) up to the current version.
4. **Data from a newer schema → refuse**: the profile is released untouched and the player is kicked
   ("saved by a newer version… rejoin"). This protects data during rolling updates.
5. **Validate and repair** (`sanitize`): non-finite or negative counters (incl. coins) → defaults,
   fractions rounded down, huge values capped, stress clamped; `OwnedHammers` / `BossDefeats` rebuilt
   keeping only known ids with valid values; an equipped hammer that isn't owned → default. Unknown
   extra fields are kept.
6. Only then do sessions, score, stress and hits become available. Hits from a player whose data hasn't
   loaded are ignored.
7. If another server takes over the profile, the player is kicked from this one.

## Changing the schema
1. Bump `CURRENT_VERSION` and add `MIGRATIONS[newVersion]`, which upgrades data in place from the
   previous version.
2. Update `PlayerData`, `template()` and `sanitize()`.
3. Add specs in `tests/Unit/Server/PlayerDataSchema.spec.luau` for the migration and the new fields.
4. Never remove or rename a field in place; add the new one and migrate.

## Right to erasure (Roblox data-deletion requests)
When Roblox sends a "Right to Erasure" request for a UserId:
1. In Studio, open the live place with **Game Settings → Security → Enable Studio Access to API Services**.
2. In the **Command Bar** run (replace `123456` with the UserId):
   ```lua
   local PS = require(game.ServerScriptService.ServerPackages.ProfileStore)
   print(PS.New("PlayerData"):RemoveAsync("Player_123456"))
   ```
   `true` means the profile was deleted. Also remove the leaderboard entry (see **Leaderboard store** below).
3. Record the request date and UserId (not the player's name) in your compliance log.

## Studio testing
- With **Studio Access to API Services off**, ProfileStore uses an in-memory mock: everything works but
  nothing is saved between Play sessions.
- To test real saving, turn it on. That reads and writes the **live** DataStore for your own account, so
  only do it on a test place or with your own test account.

## Leaderboard stores
| OrderedDataStore | Key / value | Since |
|---|---|---|
| `ScoreLeaderboard` (`DataConfig.LeaderboardStoreName`) | `<UserId>` → lifetime Score | Phase 7 |
| `XpLeaderboard` (`DataConfig.XpLeaderboardStoreName`) | `<UserId>` → XP (the board shows it as Level) | 2026-10-07 |
| `CoinsLeaderboard` (`DataConfig.CoinsLeaderboardStoreName`) | `<UserId>` → current coins | 2026-10-07 |

| Setting | Value |
|---|---|
| Writes | from the server's saved data, every `LeaderboardWriteInterval` (120 s), each store only if its value changed, and on leave |
| Reads | top `LeaderboardSize` (10) of each store, every `LeaderboardReadInterval` (60 s) per server: 3 sorted reads a minute |

These are copies for ranking only; the player's saved data (`PlayerData`) stays the source of truth,
and no saved data format changed. The two new stores start empty (no migration needed).

For a right-to-erasure request also remove the player's leaderboard entries (Command Bar, API access on):
```lua
local DSS = game:GetService("DataStoreService")
for _, name in { "ScoreLeaderboard", "XpLeaderboard", "CoinsLeaderboard" } do
	print(name, DSS:GetOrderedDataStore(name):RemoveAsync("123456"))
end
```
Player Level is derived from XP and is not stored in `PlayerData`.

## Pickleball season stores (Phase 4b, `RecreationRankService`)
| Store | Key / value | Notes |
|---|---|---|
| OrderedDataStore `RecRating_<seasonId>` (`DataConfig.RecRatingStorePrefix`) | `<UserId>` → that season's rating | Only players with `SeasonBoard.MinMatches` (5) rated matches in the season. Written on change at most every 120 s, on leave and at shutdown; top 10 read every 60 s |
| DataStore `RecSeasons` (`DataConfig.RecSeasonsStoreName`) | `Season_<seasonId>` → `{ SeasonId, FrozenAt, Top = { { UserId, Rating } } }` | A finished season's final top 10, frozen once (`UpdateAsync`, only if missing) 15 min after the season ends. Prizes are paid from it |

Prizes are paid once per season per player: the season id goes into `SeasonClaims` (v12, no migration)
in the same step as the coins and the item. For a right-to-erasure request also remove the player from
the season boards (`RecRating_<id>` for the seasons they played: `RemoveAsync("<UserId>")`) and their
entry from any `RecSeasons` record (`UpdateAsync`, filter `Top`).
