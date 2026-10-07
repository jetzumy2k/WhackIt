# Remote Contracts

Every RemoteEvent between client and server. The client only **requests**; the server
validates and decides every result (damage, HP, score, rewards, defeat).

## Rules for all client -> server remotes
Bind through `RemoteController.bind` (`src/server/controllers/RemoteController.luau`).
It applies, in order, before the handler runs:

1. **Sender present:** requests from players who already left are dropped silently.
2. **Argument cap:** more arguments than `maxArgs` (trailing `nil`s count) → reject.
3. **Rate limit:** per-player token bucket from `RemoteLimits` (server-only config) → reject.
4. **Error containment:** handler errors are caught and logged; the connection survives.

Inside the handler, every argument is `unknown` and must pass `Shared/Validate`
(`string`, `id`, `number`, `integer`, `boolean`: these reject wrong types, NaN, ±inf,
out-of-range values, over-long strings and malformed UTF-8). On failure call
`RemoteController.reject(player, remoteName, reason)` and return. Rejections are
logged at most once per player every 5 s (`RemoteLimits.RejectLog`).

Payloads are scalar arguments, not tables, so there is no table size/depth to police.
A remote that ever needs a table payload must add explicit key, size and depth checks.

Abuse thresholds live in `ServerScriptService.Config.RemoteLimits`, not `ReplicatedStorage`,
so clients can't read them.

---

## `Combat.RequestHammerHit`: client -> server
| | |
|---|---|
| Purpose | "I swung at this boss." |
| Arguments | `bossInstanceId: string`, the server-issued id of a spawned boss (`Types.BossInstanceId`). **Not** a `BossConfig` id, and never damage, HP or position. |
| `maxArgs` | 1 |
| Validation | `Validate.id(bossInstanceId, RemoteLimits.MaxIdLength)`: 1–64 chars of `[A-Za-z0-9_-]` |
| Rate limit | `RemoteLimits.RequestHammerHit`: burst 10, refill 8/s (flood guard only) |
| Server checks (`CombatService`) | player has a session and loaded data; not flagged by `MovementGuardService`; the boss is **unlocked for this player** (`ProgressionRules.isBossUnlocked`, including the Senior bosses' Player Level requirement); at least `HitCooldown − HitCooldownGrace` since the player's last **accepted** hit (`CombatRules.isOffCooldown`); boss instance exists and is not defeated; live character **holding a hammer Tool** (tagged `HammerId`) whose root is within `GameConfig.HitReach + HitReachGrace` of the boss (`CombatRules.isInReach`; the client checks the exact `HitReach`, the grace absorbs movement during network lag). The Tool only gates the swing: damage comes from the session's `EquippedHammerId`, so editing the Tool changes nothing. The handler never yields, so checks and the state change are atomic. |
| Effect | damage = `CombatRules.computeHitDamage(equipped hammer, boss)`; HP reduced (overkill not credited); damage credited to the player's contribution; stress relieved by `StressRules.reliefForHit(applied)`. On the defeating hit: rewards (see `BossDefeated`) and respawn after `BossRespawnDelay` with a **new** instance id. |
| Response | `Combat.CombatFeedback` on success. Nothing on rejection (no oracle for probing). |
| Failure | invalid payload / rate limited → `reject` + drop. Cooldown or reach failures are normal play → drop without logging. |

## `Combat.CombatFeedback`: server -> client
| | |
|---|---|
| Purpose | Presentation only: HP bar update, hit effects, defeat effects. Clients must not derive rewards from it. |
| Payload | `Types.CombatFeedback`: `{ BossInstanceId, Health, MaxHealth, Damage, HitterUserId, Defeated, Crit }` (crits are rolled by the server) |
| Recipients | all clients (`FireAllClients`). With few bosses this is cheapest; revisit per-proximity sending if boss count grows. |
| Client handling | treat as untrusted for logic, display only; ignore unknown `BossInstanceId` |

## `Combat.BossDefeated`: server -> client
| | |
|---|---|
| Purpose | Victory Card for each player who damaged the defeated boss. |
| Payload | `Types.BossDefeated`: `{ BossInstanceId, BossId, Rewarded, ScoreAwarded, CoinsAwarded, StressRelieved, UnlockedBossIds, SharePercent, LastHit, BossName, BuffDropText?, AdminDamage }`. `BuffDropText` is set when the boss dropped a store boost for this player (custom bosses always, office bosses by the current drop rates, `DropRateService`); `AdminDamage` means the player hit this boss with admin-set damage and got nothing. `Rewarded` means the player qualified (≥ 10 %); every contributor gets score/coins |
| Recipients | every contributor still in the server, once per defeat |
| Rewards | granted by `RewardService` **before** sending, only to players whose contribution ≥ `MinRewardDamageShare × MaxHealth`: `ScoreReward`, `CoinReward`, `DefeatStressRelief`, and +1 to that boss's defeat count (which can unlock the next boss, listed in `UnlockedBossIds`). Granted at most once per player per boss life (`BossState.markRewarded`). Non-qualifiers get `Rewarded = false`. |
| Client handling | display only |

## `Mood.ZenAchieved`: server -> all clients
| | |
|---|---|
| Purpose | Announce a Zen moment (a player's stress reached 0 while armed) |
| Payload | `Types.ZenAchieved`: `{ UserId, DisplayName, ZenLevel, BonusCoins }` |
| When | inside `StressService.relieve`, after the bonus coins and Zen Level are granted on the server |
| Client handling | display only: your own Zen → big card; anyone else's → toast |

## `Profile.Saved`: server -> one client
| | |
|---|---|
| Purpose | Show "Progress saved" briefly after ProfileStore saves the player's data |
| Payload | none |
| When | ProfileStore `OnAfterSave` for that player |

## `Notify.Toast`: server -> one client
| | |
|---|---|
| Purpose | Short message for the player (e.g. why the Executive Elevator won't go up) |
| Payload | `string` (≤ 120 characters; longer messages are ignored by the client) |

## Executive Elevator (ProximityPrompt, not a RemoteEvent)
`ProximityPrompt.Triggered` gives the server the real player, so there is no client payload to
validate. "Ride up" checks `ProgressionRules.isBossUnlocked("the_ceo", …)` on the server before moving
the player (and spiking stress); "Ride down" always works. `ExecutiveService` also returns anyone found
on the Executive Floor without access.

## `Shop.BuyHammer`: client -> server
| | |
|---|---|
| Purpose | Buy a hammer with coins |
| Arguments | `hammerId: string`; `maxArgs` 1 |
| Validation | `Validate.id` + must exist in `HammerConfig` → otherwise `reject` |
| Rate limit | `RemoteLimits.Shop`: burst 5, refill 2/s |
| Server checks | data loaded; `ProgressionRules.checkPurchase` = `Ok` (exists, not already owned, enough coins); `SessionService.trySpendCoins` never lets coins go negative. The handler never yields, so double-clicks can't buy twice |
| Effect | coins − price, hammer added to `OwnedHammers`, and it's equipped |
| Response | `Profile.Sync` after every request, success or not |

## `Shop.EquipHammer`: client -> server
| | |
|---|---|
| Purpose | Hold a different owned hammer |
| Arguments | `hammerId: string`; `maxArgs` 1; same validation and rate limit as `BuyHammer` |
| Server checks | data loaded; `ProgressionRules.ownsHammer` |
| Effect | `EquippedHammerId` saved; the held Tool is swapped (`HammerService.reequip`). Damage follows the saved id |
| Response | `Profile.Sync` |

## `Store.RequestPurchase`: client -> server
| | |
|---|---|
| Purpose | Ask for Roblox's purchase prompt for one store product |
| Payload | `productKey: string` (a `StoreConfig` key, max `RemoteLimits.MaxIdLength`) |
| Server checks | known key; product has a Developer Product id; store open (`StoreService.isOpen`); Mystery Hammer only if PolicyService allows paid random items for this player. Rate limit `RemoteLimits.Shop` |
| Result | `MarketplaceService:PromptProductPurchase`. **Delivery is only by `ProcessReceipt`** (`PurchaseService`, see `docs/STORE.md`), never by this remote. A refusal re-sends `Store.State` |

## `Store.RequestGift`: client -> server
| | |
|---|---|
| Purpose | Buy a boost for a Roblox friend (docs/STORE.md "Bag and gifts") |
| Payload | `productKey: string, recipientUserId: number` |
| Server checks | known key; not the Mystery Hammer (rejected); recipient a whole positive number and not the buyer; store open and product on sale; `Player:IsFriendsWithAsync(recipient)` must be true (otherwise rejected and logged); buyer's data loaded. Rate limit `RemoteLimits.Shop` |
| Result | sets the buyer's `PendingGift`, then `PromptProductPurchase`. Delivery is only by `ProcessReceipt`, into the friend's gift inbox |

## `Bag.Use`: client -> server
| | |
|---|---|
| Purpose | Use one item from the player's Bag |
| Payload | `productKey: string` |
| Server checks | known `StoreConfig` key (else rejected); the Bag holds at least one (else just re-sync the UI). Rate limit `RemoteLimits.Shop` |
| Result | removes one and, in the same step, starts the boost (`BuffService.grantTimed`) or opens the Mystery Hammer (roll, add, equip); toast + `Profile.Sync` |

## `Store.AdminSetMode`: client -> server
| | |
|---|---|
| Purpose | Admin opens, closes or schedules the store for every server |
| Payload | `{ Mode: "On" \| "Off" }` or `{ Mode: "Schedule", StartsAt: number, EndsAt: number }` (unix seconds) |
| Server checks | sender is an admin (decided by the server: owner, `StoreAdminConfig.AdminUserIds`, Studio tester); payload parsed by `Shared/StoreSchedule.parse` (finite numbers, ends after it starts, in the future, within a year). Non-admins are rejected and logged |
| Result | applied locally, saved to DataStore `StoreSettings`, published on MessagingService `StoreSettings`; admin gets a toast |

## `Store.State`: server -> one client
| | |
|---|---|
| Payload | `{ Open, MysteryAllowed, IsAdmin, Mode, StartsAt, EndsAt }` |
| When | on join, whenever settings change or a schedule boundary passes, after a refused purchase request |
| Client handling | display only (show or hide the Store button, tabs and Admin tab); the server re-checks everything on each request |

## Admin remotes (`Remotes.Admin`, docs/ADMIN.md)
All client -> server admin remotes share these checks, on top of the common rules above: sender is an
admin (`Lib/AdminAuth`, cached on join; non-admins are rejected and logged), rate limit
`RemoteLimits.Admin` (5 burst, 1/s), at most 3 arguments. Problems an admin can fix (bad number,
player left) come back as a `Notify.Toast`; malformed payloads are rejected and logged. Every
accepted action prints an `[Admin]` line.

| Remote | Payload | Server checks | Result |
|---|---|---|---|
| `SetLevel` | `userId: number, level: number` | integer level 1..`AdminConfig.MaxSetLevel` (500); target in this server with loaded data | `Xp = LevelRules.scoreForLevel(level)` (saved); Level attribute + `Profile.Sync` |
| `SetDamage` | `userId: number, damage: number` | integer 0..`MaxSetDamage` (1,000,000); target in this server | `BuffService` damage override for this session (0 clears). Hits use exactly that damage, never crit, and mark the boss life `AdminBoosted` for that player, who then gets **no** reward for it |
| `SetUnlock` | `userId: number, bossId: string or "*", unlocked: boolean` | known `BossConfig` id or `"*"`; target in this server | edits `AdminUnlocks` (saved); `"*"` + false clears them all. Earned unlocks are never removed |
| `CreateBoss` | `{ Name, LookId, MaxHealth, ScoreReward, CoinReward, RespawnMode }` | `CustomBossRules.parseSpec` (name 1-30 chars, look from `CustomBossConfig.LookIds`, integer bounds, `RespawnMode` exactly `"Continuous"` or `"Once"`); name passes `TextService` filtering unchanged; **position is where the admin's character stands** (raycast to the floor), at least `MinSpacing` (14 studs) from every boss; at most 20 custom bosses | saved with `UpdateAsync` to DataStore `CustomBosses`, spawned here, other servers told via MessagingService `CustomBosses` |
| `EditBoss` | `action: "Move" or "Delete", bossId: string` | custom boss id; Move uses the admin's position with the same spacing check | saved and synced like `CreateBoss` |
| `SetDropRates` | `{ NormalMin, NormalMax, LuckyMin, LuckyMax, LuckyEveryMinutes, LuckyLastsMinutes }` or `"Reset"` | `DropRateRules.parse`: chances are finite numbers 0..1 with min <= max per range; Every is an integer 10..1440 minutes; Lasts an integer 1..Every-1 | saved with `SetAsync` to DataStore `DropRates` (`"Reset"` removes the key, so `DropRateConfig.Default` applies); other servers told via MessagingService `DropRates` |
| `Moderate` | `{ Action: "Ban" or "Unban", UserId?, Username?, Duration?, Reason?, Note? }` | target by UserId or a valid username (`GetUserIdFromNameAsync`); not yourself; Ban: not an admin/owner, `Duration` and `Reason` must be keys of `AdminConfig.BanDurations` / `BanReasons` (players only ever see the fixed reason text), `Note` up to 200 chars (private) | `Players:BanAsync` / `UnbanAsync` with `ApplyToUniverse = true` (alts included); fails with a toast in Studio |

`Admin.State` (server -> one client): `{ IsAdmin }` for everyone on join; admins also get
`{ CustomBosses, DropRates, DamageOverrides, MaxSetLevel, MaxSetDamage, BanDurations, BanReasons }`,
re-sent when custom bosses, drop rates or damage overrides change. Display only.

## `Profile.Sync`: server -> one client
| | |
|---|---|
| Purpose | The player's own progression for the UI (HUD, shop, locked bosses) |
| Payload | `Types.ProfileSnapshot`: `{ Coins, OwnedHammerIds, EquippedHammerId, BossDefeats, UnlockedBossIds, ZenLevel, Level, Xp, Buffs, MysteryHammers, AdminUnlocks, Bag }` |
| When | on data load, after every reward, purchase and equip request |
| Client handling | display only; parsed defensively (`ProgressController`) |

## `Leaderboard.Snapshot`: server -> all clients (2026-10-07)
| | |
|---|---|
| Purpose | The leaderboard board's contents (docs/GAMEPLAY_RULES.md "Global leaderboard") |
| Payload | `{ Global, Note, Tabs = { Score, Xp, Coins }, Online }`; each list holds rows `{ UserId, Name, Score?, Xp?, Coins? }` (top 10 per tab; `Online` = players in this server with loaded data) |
| When | every `LeaderboardReadInterval` (60 s); to a joining player at once (last snapshot); to everyone ~2 s after joins, leaves and data loads |
| Client handling | display only; parsed defensively (`LeaderboardController`). There is no client -> server leaderboard remote. |

---

## Replicated state (server-written attributes)
Names live in `Shared/Attributes`. Only the server writes them; clients read them for display.

| Where | Attribute | Meaning |
|---|---|---|
| Boss `Model` under `Workspace.Bosses` | `BossInstanceId`, `BossId`, `Health`, `MaxHealth`, `Defeated`, `ShoutText`, `ShoutSeq` | live boss state for HP bars, target selection and the client-drawn monster's hit/defeat animations |
| Custom boss `Model` (admin-created) | `BossName`, `BossLook` | display name (already text-filtered) and the office boss whose look it borrows |
| Hammer `Tool` (server-created, in the character) | `HammerId` | marks the Tool as a hammer for the server's hand check |
| `Player` | `Stress` | the player's Stress Meter (also drives the server-drawn mood face and hammer glow) |
| `Player` | `Level` | Player Level from XP (HUD, "Lv N" head tag, Senior unlocks) |
| `Player` | `ZenBuffEnds` | `Workspace:GetServerTimeNow()` time the Zen buff ends (0 = none); HUD countdown only |
| `Player.leaderstats.Score`, `.Coins` (IntValue) | | lifetime score and coins (saved values, mirrored for display) |

## Movement sanity (`MovementGuardService`)
Reach is checked against the character's position, which Roblox lets each client simulate. The
server samples every character's root position every `MovementLimits.SampleInterval` (0.5 s); a
horizontal move faster than `MaxHorizontalSpeed` (50 studs/s; walking is 16) flags the player and
`RequestHammerHit` is ignored for `SuspectSeconds` (5 s). Respawns start fresh. This blocks teleporting
to a boss and large speed hacks; small boosts under the limit are an accepted v1 limitation. Sprint (`GameConfig.SprintSpeed` 26) stays well under the limit.

## Removed
- `Round.RoundState`: removed 2026-10-05; encounters end on defeat, there is no round timer.
