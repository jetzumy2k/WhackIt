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
- the player's root is within `GameConfig.HitReach` (9 studs, about as far as the swung hammer visibly reaches); the server
  adds `HitReachGrace` (1.5 studs) for network lag, the client uses the exact 9 of the boss centre;
- at least `HitCooldown − HitCooldownGrace` (0.45 − 0.05 s) since the player's last accepted hit. One hammer swing lasts exactly `HitCooldown`, and the client sends one request per swing at the moment of impact; the grace only absorbs network jitter.

## Shared-boss rules (confirmed 2026-10-05)
- **Contribution:** the server records accepted damage per player per boss.
- **Rewards:** split by damage share, with a small last-hit bonus (see Progression below). Superseded the earlier "full reward for every qualifier" rule on 2026-10-05.
- **Respawn:** a defeated boss stays visible (defeated) for `BossRespawnDelay`, then is replaced by a fresh boss at full HP with a new instance id.

Tunable values (`GameConfig`):
| Key | Value | Meaning |
|---|---|---|
| `MinRewardDamageShare` | 0.1 | fraction of boss MaxHealth a player must deal to qualify for the reward |
| `BossRespawnDelay` | 5 s | time from defeat to the boss reappearing at full HP |

## Stress Meter (decided 2026-10-05)
Each player has their own Stress Meter, saved with their data. It starts at `StartingStress` (100).
The server owns it (`StressService`); clients only display it.

```
each accepted hit:   stress -= damage x StressReliefPerDamage
qualifying defeat:   stress -= DefeatStressRelief
idle:                after StressIdleDelay (180 s) without an accepted hit,
                     stress += StressRegenStep (5) every StressRegenInterval (10 s)
always:              clamped to 0..MaxStress, rounded to hundredths
```

### Mood: face and hammer glow (visible to everyone)
| Stress | Mood | Face |
|---|---|---|
| 0 | Zen | happy closed eyes, big smile, blush; **hammer glows** (light + sparkles) |
| up to 25 | Relaxed | smile |
| up to 50 | Neutral | flat mouth |
| up to 75 | Stressed | frown, angry brows |
| above 75 | Frazzled | frown, angry brows, sweat drop |

Faces are drawn from shapes by the server (`Lib/MoodFace`, `MoodService`), no image assets. Classic
heads have their face decal hidden; newer animated (mesh) heads get the drawn face on top, and the
original face may show through a little.

### Zen (reaching 0)
- **Reward:** +`ZenBonusCoins` (100) and +1 **Zen Level**. Each Zen Level permanently adds
  `ZenCoinBonusPerLevel` (+5 %) to boss coins, counting up to `ZenCoinBonusMaxLevel` (10) levels.
- Your screen shows "ZEN ACHIEVED!"; everyone else gets a toast. Your hammer glows while you stay at 0.
- **No refill:** stress stays at 0 while you keep hitting; it only climbs back when you go idle.
- **Anti-farming:** the next Zen only pays out once stress has climbed back to `ZenRearmStress` (50)
  since the last one (`ZenArmed`, saved, so rejoining doesn't reset it).

## Arena
Boss spawn points and hitbox size are in `src/config/ArenaConfig.luau`. The server's boss is an
invisible hitbox; each client draws a cartoon monster over it (`Shared/BossVisual`, looks in
`src/config/BossVisualConfig.luau`) and animates it locally: idle bob, turning to face the player,
a lean-back hop on each confirmed hit, and a spin-and-shrink on defeat.

Every player is handed their hammer Tool on spawn (`HammerService`, built by `Lib/HammerTool`).
While held, the hammer rests on the shoulder (`SwingPose.REST`). Clicking, tapping or pressing R2
plays one swing: the arm lifts with the hammer cocked back, then arm and wrist snap forward so the
hammer is out in front at the boss, follow through, and the hammer swings back onto the shoulder.
The client's `Lib/SwingAnimator` (driven by `HammerPoseController` for every hammer holder) rotates
the shoulder, elbow, waist and wrist (`RightGrip`) joint offsets, `Motor6D.C0`/`Weld.C0` or an
`AnimationConstraint`'s attachment, on top of Roblox's tool-hold animation. Roblox's built-in swing
sound plays on the downswing. The hit request is sent at the impact moment (`SwingPose.IMPACT`,
halfway through the swing), so the boss reacts as the hammer lands. Joint animation is local, so other clients replay the strike on
the hitter's character when the hit is confirmed. Presses during a swing are ignored.

The map is an office floor (`ArenaConfig.Offices`, built by the server's `Lib/OfficeBuilder` from simple
parts): each boss stands in **its own 32×32 office** along a carpeted corridor, with a name plate over
the open doorway, a carpet in the boss's tint, and a desk (monitor joke per boss), chair, filing
cabinet, plants and a themed poster, all kept clear of the boss and the walk from the door. South
of the corridor is the lobby (welcome sign, reception desk, couches, water cooler, plants) with the
player spawn. Offices are 34 studs apart, so one swing can only reach one boss. The base floor and
spawn are in `default.project.json` (`Workspace.Arena`).

## Progression (Phase 4, decided 2026-10-05)
Rules in `src/shared/ProgressionRules.luau` (server enforces, client displays); values in `BossConfig`
and `HammerConfig`.

### Rewards per defeat (once per player per boss life)
Every contributor gets the boss's score and coins **in proportion to the share of its HP they dealt**
(overkill isn't credited, so shares add up to 100 %). The player who lands the **defeating hit** gets an
extra `LastHitBonusShare` (5 %) of the boss's score and coins, at least 1 of each. Coins then get the
Zen Level bonus. Only players with at least `MinRewardDamageShare` (10 %) **qualify**: their defeat
counts toward unlocking the next boss and they get the stress bonus. (`Lib/RewardRules`)

The full boss reward (100 % share, solo):

| Boss | Score | Coins | Unlocks after |
|---|---|---|---|
| Deadline Boss | 100 | 10 | always open |
| Meeting Master | 120 | 15 | 3 defeats of Deadline Boss |
| Reply-All Boss | 150 | 20 | 3 defeats of Meeting Master |
| Production Bug | 200 | 30 | 3 defeats of Reply-All Boss |
| Monday Monster | 300 | 50 | 3 defeats of Production Bug |

Score is the lifetime leaderboard number and never goes down; coins are spent in the hammer shop.
Locked bosses are drawn greyed out with "LOCKED: beat <previous> xN"; swings at them don't count and
show "Defeat <previous> N more times to unlock!".

### Hammer shop ("Hammers" button)
| Hammer | Damage | Price |
|---|---|---|
| Squeaky Hammer | 10 | free (default) |
| Bouncy Mallet | 14 | 150 coins |
| Bubble-Wrap Hammer | 18 | 400 coins |
| Rainbow Mega Mallet | 25 | 1000 coins |

A bought hammer is equipped immediately; any owned hammer can be re-equipped. Pricier hammers always
hit harder (spec-enforced).
