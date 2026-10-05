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
| Server checks (`CombatService`) | player has a session and loaded data; not flagged by `MovementGuardService`; the boss is **unlocked for this player** (`ProgressionRules.isBossUnlocked`); at least `HitCooldown − HitCooldownGrace` since the player's last **accepted** hit (`CombatRules.isOffCooldown`); boss instance exists and is not defeated; live character **holding a hammer Tool** (tagged `HammerId`) whose root is within `GameConfig.HitReach + HitReachGrace` of the boss (`CombatRules.isInReach`; the client checks the exact `HitReach`, the grace absorbs movement during network lag). The Tool only gates the swing: damage comes from the session's `EquippedHammerId`, so editing the Tool changes nothing. The handler never yields, so checks and the state change are atomic. |
| Effect | damage = `CombatRules.computeHitDamage(equipped hammer, boss)`; HP reduced (overkill not credited); damage credited to the player's contribution; stress relieved by `StressRules.reliefForHit(applied)`. On the defeating hit: rewards (see `BossDefeated`) and respawn after `BossRespawnDelay` with a **new** instance id. |
| Response | `Combat.CombatFeedback` on success. Nothing on rejection (no oracle for probing). |
| Failure | invalid payload / rate limited → `reject` + drop. Cooldown or reach failures are normal play → drop without logging. |

## `Combat.CombatFeedback`: server -> client
| | |
|---|---|
| Purpose | Presentation only: HP bar update, hit effects, defeat effects. Clients must not derive rewards from it. |
| Payload | `Types.CombatFeedback`: `{ BossInstanceId, Health, MaxHealth, Damage, HitterUserId, Defeated }` |
| Recipients | all clients (`FireAllClients`). With few bosses this is cheapest; revisit per-proximity sending if boss count grows. |
| Client handling | treat as untrusted for logic, display only; ignore unknown `BossInstanceId` |

## `Combat.BossDefeated`: server -> client
| | |
|---|---|
| Purpose | Victory Card for each player who damaged the defeated boss. |
| Payload | `Types.BossDefeated`: `{ BossInstanceId, BossId, Rewarded, ScoreAwarded, CoinsAwarded, StressRelieved, UnlockedBossIds, SharePercent, LastHit }`. `Rewarded` means the player qualified (≥ 10 %); every contributor gets score/coins |
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

## `Profile.Sync`: server -> one client
| | |
|---|---|
| Purpose | The player's own progression for the UI (HUD, shop, locked bosses) |
| Payload | `Types.ProfileSnapshot`: `{ Coins, OwnedHammerIds, EquippedHammerId, BossDefeats, UnlockedBossIds, ZenLevel }` |
| When | on data load, after every reward, purchase and equip request |
| Client handling | display only; parsed defensively (`ProgressController`) |

---

## Replicated state (server-written attributes)
Names live in `Shared/Attributes`. Only the server writes them; clients read them for display.

| Where | Attribute | Meaning |
|---|---|---|
| Boss `Model` under `Workspace.Bosses` | `BossInstanceId`, `BossId`, `Health`, `MaxHealth`, `Defeated` | live boss state for HP bars, target selection and the client-drawn monster's hit/defeat animations |
| Hammer `Tool` (server-created, in the character) | `HammerId` | marks the Tool as a hammer for the server's hand check |
| `Player` | `Stress` | the player's Stress Meter (also drives the server-drawn mood face and hammer glow) |
| `Player.leaderstats.Score`, `.Coins` (IntValue) | | lifetime score and coins (saved values, mirrored for display) |

## Movement sanity (`MovementGuardService`)
Reach is checked against the character's position, which Roblox lets each client simulate. The
server samples every character's root position every `MovementLimits.SampleInterval` (0.5 s); a
horizontal move faster than `MaxHorizontalSpeed` (50 studs/s; walking is 16) flags the player and
`RequestHammerHit` is ignored for `SuspectSeconds` (5 s). Respawns start fresh. This blocks teleporting
to a boss and large speed hacks; small boosts under the limit are an accepted v1 limitation.

## Removed
- `Round.RoundState`: removed 2026-10-05; encounters end on defeat, there is no round timer.
