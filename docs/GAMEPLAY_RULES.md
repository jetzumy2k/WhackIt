# Gameplay Rules

Authoritative rules for combat and encounters. All results are computed on the server;
values live in `src/config/` and formulas in `src/shared/CombatRules.luau` and `src/shared/StressRules.luau`.

## Design decisions (2026-10-05)
| Topic | Decision |
|---|---|
| Session model | **Shared bosses**: several players can hit the same boss at once. |
| Encounter end | **On defeat** (HP reaches 0). No round timer in v1. |
| Damage | **Hammer-driven**: damage depends on the player's equipped hammer, scaled per boss. |
| Stress Meter | **Damage-proportional relief** (decided 2026-10-05), plus a defeat bonus. |

## Hit damage
```
damage = max(MinHitDamage, round(hammer.Damage × boss.DamageTakenMultiplier))
```
- `hammer.Damage`: `HammerConfig`
- `boss.DamageTakenMultiplier`: `BossConfig` (higher = boss is easier to hurt)
- `MinHitDamage`: `GameConfig` (currently 1)
- Rounding is half-up to a whole number, so HP stays integral.

Starting balance: with the default `squeaky_hammer` (Damage 10), every boss takes exactly the
damage per hit it took before hammers existed (Deadline 10, Meeting 8, Reply-All 12,
Production Bug 15, Monday 20).

## Hit acceptance (server)
A hit request is applied only if all of these hold (details in `docs/REMOTE_CONTRACTS.md`, Phase 1–2):
- the player has a live character;
- the target boss exists and is not defeated;
- the player is within reach of the boss;
- at least `GameConfig.HitCooldown` seconds since the player's last accepted hit.

## Shared-boss rules (confirmed 2026-10-05)
- **Contribution:** the server records accepted damage per player per boss.
- **Rewards:** on defeat, every player whose accepted damage is at least a minimum share of the boss's MaxHealth receives the **full** reward. Cooperative: no kill-stealing, no last-hit bonus.
- **Respawn:** a defeated boss respawns at full HP after a configured delay.

Tunable values (added to `GameConfig` when Phase 2 implements them; starting proposals):
| Key | Proposed start | Meaning |
|---|---|---|
| `MinRewardDamageShare` | 0.10 | fraction of boss MaxHealth a player must deal to qualify for the reward |
| `BossRespawnDelay` | 5 s | time from defeat to the boss reappearing at full HP |

## Stress Meter
Each player has their own Stress Meter. It starts at `StartingStress` (100) and whacking relieves it.
The server owns the value; clients only display it.

```
on each accepted hit:   stress = applyRelief(stress, damage × StressReliefPerDamage)
on boss defeat:         stress = applyRelief(stress, DefeatStressRelief)   -- reward-qualifying players only
applyRelief:            clamp to [0, MaxStress], round to hundredths
```
| Key (`GameConfig`) | Value | Meaning |
|---|---|---|
| `StressReliefPerDamage` | 0.1 | stress relieved per point of accepted damage |
| `DefeatStressRelief` | 5 | bonus for each player who qualifies for the boss reward (`MinRewardDamageShare`) |

Starting balance: soloing a 100-HP boss relieves 10 + 5 = 15 stress, so about 7 defeats take a
player from 100 to 0. Better hammers relieve stress faster because relief follows damage.
Open (Phase 2+): what happens at 0 stress (e.g. a "Zen" celebration), and whether stress
persists between sessions (Phase 3).
