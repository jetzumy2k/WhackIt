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

## Schema v6 (current)
```lua
type PlayerData = {
    SchemaVersion: number,        -- 6
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
    MysteryHammers: {[id]: {Damage: number, CritDamagePercent: number}}, -- "mystery_<n>", rolled at purchase
    NextMysteryNumber: number,    -- next Mystery Hammer id number
    -- v5 (docs/ADMIN.md)
    AdminUnlocks: {[string]: true}, -- bosses an admin unlocked for this player (known BossConfig ids only)
    -- v6 (docs/STORE.md "Bag and gifts")
    Bag: {[productKey]: number},  -- unused store items: StoreConfig keys only, whole counts 1..100,000
    ClaimedGifts: {string},       -- last 200 gift ids put in the Bag, so an inbox gift lands once
    PendingGift: {RecipientUserId: number, ProductKey: string}?, -- the gift being bought right now
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

Sanitizing v4: unknown buff kinds are dropped and buff values clamped. Purchase ids must be strings.
Mystery Hammers are paid for, so out-of-range stats are **clamped, never deleted**. An equipped
Mystery Hammer must be one the player owns.

Who writes what (server only): `SessionService.addScore` → `Score`; `SessionService.addCoins` /
`trySpendCoins` → `Coins`; `SessionService.setEquippedHammer` → `EquippedHammerId`; `StressService.relieve`
→ `Stress`, `ZenLevel`, `ZenArmed` (Zen and idle regen); `CombatService` → `TotalHits`; `RewardService` → `TotalBossesDefeated`, `BossDefeats`;
`ShopService` → `OwnedHammers`; `SessionService.addXp` → `Xp`; `BuffService` → `Buffs`;
`PurchaseService` → `ProcessedPurchases`, `MysteryHammers`, `NextMysteryNumber`;
`AdminService` → `Xp` (Set Level, via `SessionService.setXp`) and `AdminUnlocks`.

Sanitizing v5: `AdminUnlocks` keeps only known boss ids with value `true`.
Sanitizing v6: `Bag` keeps known product keys with counts of at least 1 (rounded down);
`PendingGift` is dropped unless it names a giftable product and a whole, positive UserId.

Writers for v6: `PurchaseService` → `Bag` (bought items), `PendingGift` (cleared after a gift);
`StoreService` → `PendingGift`; `BagService` → `Bag` (Use / Open); `GiftService` → `Bag`,
`ClaimedGifts`; `RewardService` → `Bag` (custom-boss drops).

Gift inboxes are **not** player data: DataStore `GiftInbox`, key `Inbox_<UserId>`, a list of
`{ GiftId, ProductKey, FromUserId, FromName }` validated by `Shared/BagRules.parseInbox`.

Admin-created bosses are **not** player data: they live in their own DataStore `CustomBosses`
(key `Global`), validated on every load by `Shared/CustomBossRules.parseList` (docs/ADMIN.md).
Each record also has `RespawnMode` (`"Continuous"` or `"Once"`) and `Defeated` (true only for a
beaten `"Once"` boss); records saved before 2026-10-07 have neither and load as `"Continuous"`, not
defeated.

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

## Leaderboard store
| Setting | Value |
|---|---|
| OrderedDataStore | `ScoreLeaderboard` (`DataConfig.LeaderboardStoreName`) |
| Key / value | `<UserId>` → lifetime Score (integer) |
| Writes | from the server's saved data, every `LeaderboardWriteInterval` (120 s) if changed, and on leave |
| Reads | top `LeaderboardSize` (10), every `LeaderboardReadInterval` (60 s) per server |

For a right-to-erasure request also remove the player's leaderboard entry (Command Bar, API access on):
```lua
print(game:GetService("DataStoreService"):GetOrderedDataStore("ScoreLeaderboard"):RemoveAsync("123456"))
```
Player Level is derived from Score and is not stored.
