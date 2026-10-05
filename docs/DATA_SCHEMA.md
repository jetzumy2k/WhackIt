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

## Schema v1 (current)
```lua
type PlayerData = {
    SchemaVersion: number,        -- 1
    Score: number,                -- lifetime score (integer, 0..2^50); shown in leaderstats
    Stress: number,               -- Stress Meter, 0..GameConfig.MaxStress, carries over between sessions
    TotalHits: number,            -- accepted hammer hits (integer, 0..2^50)
    TotalBossesDefeated: number,  -- defeats the player was rewarded for (integer, 0..2^50)
    EquippedHammerId: string,     -- must exist in HammerConfig
}
```
New players start from `PlayerDataSchema.template()`: `StartingScore`, `StartingStress`, zero counters,
`DefaultHammerId`.

Who writes what (server only): `SessionService.addScore` → `Score`; `StressService.relieve` → `Stress`;
`CombatService` → `TotalHits` (each accepted hit) and `TotalBossesDefeated` (each rewarded defeat).

## Load rules (`PlayerDataService`)
1. `StartSessionAsync` retries until it succeeds or the player leaves.
2. **Load failed → kick** with a friendly "please rejoin" message. The player never plays on defaults,
   so defaults can never be saved over real progress.
3. **Migrate** from the stored `SchemaVersion` (missing = v0) up to the current version.
4. **Data from a newer schema → refuse**: the profile is released untouched and the player is kicked
   ("saved by a newer version… rejoin"). This protects data during rolling updates.
5. **Validate and repair** (`sanitize`): non-finite or negative counters → defaults, fractions rounded
   down, huge values capped, stress clamped, unknown hammer → default. Unknown extra fields are kept.
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
   `true` means the profile was deleted.
3. Record the request date and UserId (not the player's name) in your compliance log.

## Studio testing
- With **Studio Access to API Services off**, ProfileStore uses an in-memory mock: everything works but
  nothing is saved between Play sessions.
- To test real saving, turn it on. That reads and writes the **live** DataStore for your own account, so
  only do it on a test place or with your own test account.
