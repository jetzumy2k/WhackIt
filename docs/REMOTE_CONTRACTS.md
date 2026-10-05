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
| Server checks (`CombatService`) | player has a session; at least `HitCooldown − HitCooldownGrace` since the player's last **accepted** hit (`CombatRules.isOffCooldown`); boss instance exists and is not defeated; live character **holding a hammer Tool** (tagged `HammerId`) whose root is within `GameConfig.HitReach` of the boss (`CombatRules.isInReach`). The Tool only gates the swing: damage comes from the session's `EquippedHammerId`, so editing the Tool changes nothing. The handler never yields, so checks and the state change are atomic. |
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
| Payload | `Types.BossDefeated`: `{ BossInstanceId, BossId, Rewarded, ScoreAwarded, StressRelieved }` |
| Recipients | every contributor still in the server, once per defeat |
| Rewards | granted on the server **before** sending, only to players whose contribution ≥ `MinRewardDamageShare × MaxHealth`: `ScoreReward` to leaderstats Score and `DefeatStressRelief` stress. Non-qualifiers get `Rewarded = false`. |
| Client handling | display only |

---

## Replicated state (server-written attributes)
Names live in `Shared/Attributes`. Only the server writes them; clients read them for display.

| Where | Attribute | Meaning |
|---|---|---|
| Boss `Model` under `Workspace.Bosses` | `BossInstanceId`, `BossId`, `Health`, `MaxHealth`, `Defeated` | live boss state for HP bars, target selection and the client-drawn monster's hit/defeat animations |
| Hammer `Tool` (server-created, in the character) | `HammerId` | marks the Tool as a hammer for the server's hand check |
| `Player` | `Stress` | the player's Stress Meter |
| `Player.leaderstats.Score` (IntValue) | | session score |

## Known limitation
Reach is checked against the character's position, which Roblox lets each client simulate.
A movement exploiter could teleport next to a boss. Server-side movement/teleport sanity
checks are scheduled for the Phase 6 security pass.

## Removed
- `Round.RoundState`: removed 2026-10-05; encounters end on defeat, there is no round timer.
