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
A hit request is applied only if all of these hold (`CombatService`; details in `docs/REMOTE_CONTRACTS.md`):
- the player has a live character holding their hammer;
- the target boss exists and is not defeated;
- the player's root is within `GameConfig.HitReach` (12 studs) of the boss centre;
- at least `HitCooldown − HitCooldownGrace` (0.45 − 0.05 s) since the player's last accepted hit. One hammer swing lasts exactly `HitCooldown`, and the client sends one request per swing at the moment of impact; the grace only absorbs network jitter.

## Shared-boss rules (confirmed 2026-10-05)
- **Contribution:** the server records accepted damage per player per boss.
- **Rewards:** on defeat, every player whose accepted damage is at least a minimum share of the boss's MaxHealth receives the **full** reward. Cooperative: no kill-stealing, no last-hit bonus.
- **Respawn:** a defeated boss stays visible (defeated) for `BossRespawnDelay`, then is replaced by a fresh boss at full HP with a new instance id.

Tunable values (`GameConfig`):
| Key | Value | Meaning |
|---|---|---|
| `MinRewardDamageShare` | 0.1 | fraction of boss MaxHealth a player must deal to qualify for the reward |
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

## Arena
Boss spawn points and hitbox size are in `src/config/ArenaConfig.luau`. The server's boss is an
invisible hitbox; each client draws a cartoon monster over it (`Shared/BossVisual`, looks in
`src/config/BossVisualConfig.luau`) and animates it locally: idle bob, turning to face the player,
a lean-back hop on each confirmed hit, and a spin-and-shrink on defeat.

Every player is handed their hammer Tool on spawn (`HammerService`, built by `Lib/HammerTool`).
Clicking, tapping or pressing R2 starts a full swing (`Shared/SwingPose`, played by the client's
`Lib/SwingAnimator` on the arm, elbow and waist joints): wind-up over the shoulder, a fast
downward strike, follow-through and recovery, with Roblox's built-in swing sound on the downswing.
The hit request is sent at the impact moment (`SwingPose.IMPACT`, 55 % through the swing), so the
boss reacts as the hammer lands. Joint animation is local, so other clients replay the strike on
the hitter's character when the hit is confirmed. Presses during a swing are ignored. The floor and
player spawn are in `default.project.json` (`Workspace.Arena`). Phase 2 spawns one Deadline Boss.
