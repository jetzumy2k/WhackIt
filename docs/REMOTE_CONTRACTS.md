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
| Server checks (Phase 2, `CombatService`) | boss instance exists and is not defeated; player has a live character within reach; at least `GameConfig.HitCooldown` since the player's last accepted hit |
| Effect | damage = `CombatRules.computeHitDamage(equipped hammer, boss)`; HP reduced; damage credited to the player's contribution |
| Response | `Combat.CombatFeedback` on success. Nothing on rejection (no oracle for probing). |
| Failure | invalid payload / rate limited → `reject` + drop. Cooldown or reach failures are normal play → drop without logging. |

## `Combat.CombatFeedback`: server -> client
| | |
|---|---|
| Purpose | Presentation only: HP bar update, hit effects, defeat effects. Clients must not derive rewards from it. |
| Payload | `Types.CombatFeedback`: `{ BossInstanceId, Health, MaxHealth, Damage, HitterUserId, Defeated }` |
| Recipients (Phase 2) | players near the boss, so everyone fighting it sees shared HP |
| Client handling | treat as untrusted for logic, display only; ignore unknown `BossInstanceId` |

## Removed
- `Round.RoundState`: removed 2026-10-05; encounters end on defeat, there is no round timer.
