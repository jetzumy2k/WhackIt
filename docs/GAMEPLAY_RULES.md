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
raw    = (hammer.Damage + flatBonus) × (1 + damageBoost) × boss.DamageTakenMultiplier
crit?  = serverRoll < critChance            -- rolled by the server only
damage = max(MinHitDamage, round(raw × (1 + critDamage if crit)))
```
- `flatBonus`: +`ZenBuffFlatDamage` (10) during the Zen buff, otherwise 0
- `damageBoost`: Damage store boost (0.03 / 0.05 / 0.10)
- `critChance`: `BaseCritChance` (5 %) + `ZenBuffCritChance` (5 %) during the Zen buff
- `critDamage`: `BaseCritDamage` (+50 %) + Mystery Hammer crit damage + Crit Damage store boost
- Crits show a bigger orange "CRIT! -N" number.
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
- **Respawn:** a defeated boss stays visible (defeated) for `BossRespawnDelay`, then is replaced by a fresh boss at full HP with a new instance id. Admin-created "One time" bosses don't come back (docs/ADMIN.md).
- **Buff drop (2026-10-07):** each qualifying player rolls once per office boss defeat. The roll's chance is picked at random within the range in effect (`Config/DropRateConfig`, probabilities, 0.30 = 30 %):
  - **Normal** (most of the time): 0.0005 to 0.10.
  - **Lucky window**: 0.10 to 0.30, for the first 10 minutes of every 2 hours, counted in UTC (00:00-00:10, 02:00-02:10, ...), the same in every server.

  On a drop, a random 30-minute store boost (same pool as custom bosses) goes into their Bag and the Victory Card shows "BONUS DROP". Custom bosses always drop one. Players who hit with admin-set damage get nothing. Admins can change all six values in the Admin panel's **Drops** tab (docs/ADMIN.md).

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
idle:                after StressIdleDelay (120 s) without an accepted hit,
                     stress += StressRegenStep (5) every StressRegenInterval (5 s)
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
- **Zen buff:** +`ZenBuffFlatDamage` (10) damage per hit and +`ZenBuffCritChance` (5 %) crit chance
  for `ZenBuffSeconds` (3 minutes), shown with a countdown under the score line. It is granted on
  every Zen, even when the coin reward isn't armed. It isn't saved.
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

The map is a two-storey office building (`ArenaConfig.Offices`, built by the server's `Lib/OfficeBuilder`
from simple parts; ceilings with lights, office windows, a roof, and outdoor grass, street, trees and a
city skyline from `Lib/OutdoorBuilder`). The interior uses a darker, eye-friendly palette: muted slate
walls and ceilings, deepened carpets, dim warm lights (brightness ≤ 1, no glowing panels) and thin
cyan/purple LED accent strips; specs cap surface brightness so it can't drift back to glare: each boss stands in **its own 32×32 office** along a carpeted corridor, with a name plate over
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

The full boss reward (100 % share, solo), and how tough each boss is. **Effective HP** is
`MaxHealth / DamageTakenMultiplier`: the hammer damage it really takes to win. Since 2026-10-06 both
HP and effective HP rise with every boss down the list (ground floor, then Senior floor, then the
CEO); `BossConfig.spec` enforces it.

| Boss | HP | Effective HP | Score | Coins | Unlocks after |
|---|---|---|---|---|---|
| Deadline Boss | 100 | 100 | 100 | 10 | always open |
| Meeting Master | 140 | 175 | 120 | 15 | 1 defeat of Deadline Boss |
| Reply-All Boss | 240 | 200 | 150 | 20 | 1 defeat of Meeting Master |
| Production Bug | 360 | 240 | 200 | 30 | 1 defeat of Reply-All Boss |
| Monday Monster | 560 | 280 | 300 | 50 | 1 defeat of Production Bug (lowered from 3 on 2026-10-05) |
| Senior Deadline Boss | 600 | 600 | 550 | 55 | Lv 10 + 1 defeat of Deadline Boss |
| Senior Meeting Master | 640 | 800 | 700 | 70 | Lv 10 + 1 defeat of Meeting Master |
| Senior Reply-All Boss | 1,080 | 900 | 850 | 90 | Lv 10 + 1 defeat of Reply-All Boss |
| Senior Production Bug | 1,500 | 1,000 | 1,000 | 120 | Lv 10 + 1 defeat of Production Bug |
| Senior Monday Monster | 2,400 | 1,200 | 1,300 | 170 | Lv 10 + 1 defeat of Monday Monster |
| The CEO | 90,000 | 90,000 | 5,000 | 1,000 | Lv 10 + every other boss once |

Before 2026-10-06 the HP went up and down (Reply-All had 80 HP after Meeting Master's 120, and
effective HP went 100, 150, 67, 100, 100), so later bosses could feel easier than earlier ones.

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

## Player Level, leaderboard and the Senior floor (2026-10-05)
### Player Level
`level = floor(sqrt(Xp / LevelScoreFactor)) + 1` (`Shared/LevelRules`, factor 600). **XP** per defeat
is the score earned x `XpRewardMultiplier` (1.2, i.e. +20 %, since 2026-10-06) x any XP store boost. Score itself is never boosted, so the
leaderboard stays fair. Level is derived from XP, never stored, and shown in the HUD and as "Lv N"
above every head. Existing players start with XP equal to their score (schema v4).

| Level | XP |
|---|---|
| 1 | 0 |
| 2 | 600 |
| 5 | 9,600 |
| 10 | 48,600 |

### XP bar
A thin blue bar along the bottom edge of the screen shows progress to the next level
("Lv 4   1200 / 4200 XP to Lv 5"). It sits below the how-to-play hint, clear of the Stress Meter,
the buttons on the right and the mobile thumbstick and jump button.

### Senior floor (upstairs, Level 10+)
Stairs along the lobby's east wall lead to the upper corridor. Their foot is 9 studs from the front wall, so there's open floor to walk onto them. Each ground-floor boss has a **Senior**
version in the office directly above it: tougher than every ground-floor boss, paying more than its
ground version, with a gold crown and its own jokes (numbers in the table above).
A Senior boss unlocks with **Player Level ≥ `UpstairsMinLevel` (10)** and **1 defeat of its
ground-floor version** (`BossConfig.UnlockAfterBossId` / `UnlockDefeats` / `MinLevel`). Below the
level its bar reads "LOCKED: reach Lv 10" and swings show "Reach Level 10 to fight this Senior boss!".
This spreads experienced players across two floors instead of crowding one boss.

### Boss labels (2026-10-06)
A boss's name, HP bar and speech bubble float above it, sized in studs (they shrink with distance) and
shown up to 60 studs away. They are **not** drawn on top of walls: before, every boss in the building
showed its label through the walls and they piled up on top of each other. Damage numbers follow the
same rule.

### Admin-created bosses
Admins can place extra bosses anywhere (docs/ADMIN.md). They're open to every player, take normal
damage, give the score and coins the admin set, and each qualifying player (10 % of its HP) gets one
random 30-minute store boost in their Bag (docs/STORE.md "Bag and gifts"). They don't count toward
unlocking office bosses.

### Global leaderboard
A board on the lobby's west wall lists the all-time top 10 by lifetime score across all servers
(`LeaderboardService`, OrderedDataStore `ScoreLeaderboard`). Scores are written from the server's saved
data every 2 minutes (when changed) and on leave; the board refreshes every minute. Without DataStore
access (Studio with API access off) it ranks the players in the current server and says so.

### Sprint
Hold **Shift** (keyboard), press the **left stick (L3)** (gamepad) or tap the **Sprint** button (touch)
to run at `SprintSpeed` (26) instead of `WalkSpeed` (16), with a slight camera zoom-out. A toggle
(L3 or the touch button) switches off once the character has run and then stopped. The client applies
the speed. The server's movement guard (50 studs/s) still applies; the config spec makes sure
sprinting stays well under it.
Note: a player who turned on Roblox's own *Shift Lock* setting will toggle it with Shift too
(it's off by default).

### Swing feel
The swing eases into a short anticipation pause at the top, the hammer head stretches on the
downswing and squashes on impact, a white trail follows the fast part of the swing, and each confirmed
hit throws a spark burst on the boss (`SwingPose.headScale` / `trailActive`, local visuals).

### Music
`AudioController` loops `MusicConfig.Tracks` with fades and a "Music: On/Off" button. The list is
empty until licensed tracks are added (see `docs/RELEASE.md` §4).

## Boss shouts (2026-10-05)
Every boss shouts lines about its fictional "job" (`BossShoutConfig`) in a speech bubble above its
HP bar that everyone nearby sees: one every 8–15 s (`ShoutIdleMin`/`ShoutIdleMax`) and, with a 20 %
chance, when hit (`ShoutHitChance`, at most one shout per `ShoutCooldown` 4 s). The server picks the
line so all players see the same shout. Lines are written by us (not players), stay family-friendly,
and a spec rejects a blocklist of bad words, including for the angry CEO.

## Executive Floor and the CEO (2026-10-05)
- **Unlock:** defeat **every** ground-floor and Senior boss at least once (Level 10 is implied by the
  Senior bosses). Rule: `BossConfig.UnlockAfterAllBosses` on the CEO.
- **Getting there:** the **Executive Elevator** at the west end of the 2nd-floor corridor ("Ride up"
  prompt; "Ride down" on the 3rd floor). The server checks access; without it a message says what's
  missing ("defeat every boss once first (N to go)"). Anyone found on the floor without access is
  sent back down.
- **Stress spike:** arriving on the Executive Floor sets the Stress Meter to **100 %** (and re-arms Zen).
- **The CEO:** a 1.6× size, crowned raid boss. **MaxHealth = 150 × the toughest other boss**
  (`GameConfig.CeoHealthMultiplier`, derived from config: 150 × 600 = **90,000** today). Rewards
  5,000 score and 1,000 coins, split by damage share like every boss, plus the last-hit bonus.
  Designed for a team: roughly 30 minutes solo with the best hammer, a few minutes for ten players.
