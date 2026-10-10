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
raw    = (hammer.Damage + levelDamage + flatBonus) × (1 + damageBoost) × boss.DamageTakenMultiplier
crit?  = serverRoll < critChance            -- rolled by the server only
damage = max(MinHitDamage, round(raw × (1 + critDamage if crit)))
```
- `levelDamage`: the Player Level bonus, +3 per level up to Level 10, then +1 per level (see "Level bonuses" below)
- `flatBonus`: +`ZenBuffFlatDamage` (10) during the Zen buff, otherwise 0
- `damageBoost`: Damage store boost (0.03 / 0.05 / 0.10) **plus** a Mystery Hammer's bonus damage
  (0.15-0.25) **plus** the equipped pet's Damage buff (docs/PETS.md); they add up (e.g. +5 % boost
  and +20 % hammer = ×1.25)
- `critChance`: `BaseCritChance` (5 %) + the Player Level bonus (+0.05 percentage points per level
  above 1) + `ZenBuffCritChance` (5 %) during the Zen buff
- `critDamage`: `BaseCritDamage` (+50 %) + Mystery Hammer crit damage + Crit Damage store boost +
  the equipped pet's Crit Damage buff
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
each accepted hit:   stress -= min(hammer.Damage x StressReliefPerDamage, StressReliefMaxPerHit)
qualifying defeat:   stress -= DefeatStressRelief
passive:             each accepted boss hit starts a StressIdleDelay (15 s) grace period;
                     after it, stress += StressRegenStep (5) every StressRegenInterval (5 s)
                     until the next accepted hit (hit at 0 s -> rises at 20, 25, 30 s...)
always:              clamped to 0..MaxStress, rounded to hundredths
```

**Relief per hit (rebalanced 2026-10-08):** relief used to be the hit's *final* damage × 0.1. Crits,
Damage boosts, the Mystery bonus, pets and above all the Player Level bonus therefore drained stress
in a few seconds: a Level 30 player with a boosted Mystery Hammer relieved 16+ per hit, full to 0 in
about 3 s. Now it comes from the equipped **hammer's own damage** × 0.1, capped at
`StressReliefMaxPerHit` (2.5). Squeaky Hammer: 1 per hit (about 45 s of steady hitting from full to
Zen). Best hammers and the Mystery Hammer: 2.5 (about 18 s). Crits, boosts, pets, events, level,
boss toughness and admin damage never change it, so damage and stress relief stay separate. Rapid
clicking can't go faster than the server's hit cooldown (0.45 s), and the defeat bonus
(`DefeatStressRelief` 5) is unchanged.

**Passive stress (changed 2026-10-07; was 120 s of no hits):** only a hit the server has accepted
and applied (`CombatService`, after cooldown, reach, unlock, hammer and boss checks) restarts the
grace period (`StressService.resetStressTimer`). Walking, running, jumping, standing still, menus,
the Store, respawning, and swings or clicks that miss never do; there is no movement-based idle
check. Joining starts a grace period too. Each player has one deadline (`nextRiseAt`) and a single
server loop checks all of them every 0.25 s, so there are no per-player threads, nothing per frame,
and a hit just moves the deadline: an old schedule can never fire later. Rises stop at
`MaxStress`; a server hitch never causes a burst of rises. The HUD's existing Stress bar eases to
each new value.

### Mood: face and hammer glow (visible to everyone)
| Stress | Mood | Face |
|---|---|---|
| 0 | Zen | happy closed eyes, big smile, blush; **hammer glows**: a soft warm light (brightness 0.9, range 6, no shadows) and ~3 slow golden sparkles a second (2026-10-07; was a bright light and Roblox's dense Sparkles object) |
| up to 25 | Relaxed | smile |
| up to 50 | Neutral | small friendly smile |
| up to 75 | Stressed | worried brows (inner ends raised), small wobbly mouth |
| above 75 | Frazzled | worried brows, little "o" mouth, sweat drop |

Open eyes have a small white shine. **No mood uses angry brows** (changed 2026-10-07: Stressed and
Frazzled used to frown with angry brows; Neutral had a flat mouth).

Faces are drawn from shapes by the server (`Lib/MoodFace`, `MoodService`, shapes in
`Shared/FaceShapes`), no image assets. Classic heads have their face decal hidden; newer animated
(mesh) heads get the drawn face on top, and the original face may show through a little. R6 and R15
both work (both have a `Head` part).

**Action expressions (2026-10-07, client only, `Lib/CharacterExpression`):** short faces drawn over
the mood face, then the mood face comes back.
| When | Expression | How long |
|---|---|---|
| You swing | Determined: focused eyes, level brows, confident grin | the swing (`HitCooldown`, 0.45 s) |
| Anyone's hit lands (`Combat.CombatFeedback`) | Happy: ^ ^ eyes, open smile, blush, on the hitter | 0.7 s, 1.5 s on the defeating hit |

Every client draws them for every character it can see, from events it already gets, so there's no
extra remote, no loop and no per-frame work: each head gets one local `ActionFace` SurfaceGui with
both expressions built once, then only `Visible` / `Enabled` are toggled. Others see your Happy
face (from `CombatFeedback`) but not your Determined one, since swings that miss aren't sent to
anyone.

### Zen (reaching 0)
- **Zen buff:** +`ZenBuffFlatDamage` (10) damage per hit and +`ZenBuffCritChance` (5 %) crit chance
  for `ZenBuffSeconds` (3 minutes), shown with a countdown under the score line. It is granted on
  every Zen, even when the coin reward isn't armed. It isn't saved.
- **Reward:** +`ZenBonusCoins` (100) and +1 to the saved **Zen Level** (`ZenLevel`, a count of rewarded
  Zens). Each one permanently adds `ZenCoinBonusPerLevel` (+5 %) to boss coins, counting up to
  `ZenCoinBonusMaxLevel` (10), so +50 % at most.
- **Shown as a "Zen bonus", not a level (2026-10-10):** players took "Zen Lv" for a second level to
  grind. The HUD shows `Zen +15%` (`Zen +50% (max)` at the cap), the card "Zen bonus now +15% boss
  coins", the toast to others just "<name> reached Zen!", the Profile tile "Zen bonus (boss coins)
  +15% (3/10)" with a line saying the level comes from XP (`StressRules.zenBonusText`). Saved data and
  rewards are unchanged.
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

### Outdoor campus (2026-10-07)
The lobby's glass front has a 14-stud-wide, 10-stud-tall open entrance straight ahead of the spawn
(sign above it inside: "OUTSIDE: Garden - Coffee - Stress-Relief Zone"). Outside is a walkable
campus (`ArenaConfig.Campus`, parts from `Lib/CampusBuilder`, grounds painted into Terrain). The
building, offices, stairs, elevator, leaderboard and spawn are unchanged.

| Area | Where | What's there |
|---|---|---|
| Front Plaza | in front of the entrance | paving, benches facing the building, planters, lamp posts, signpost |
| Walkways | entrance → Recreation Center; garden ↔ coffee corner; a loop around the building; loop → Stress-Relief Zone | concrete paths lined with lamp posts, trees and bushes; benches and trees behind the building |
| Recreation Center | south end of the main walkway (since 2026-10-10) | the pickleball pavilion (docs/PICKLEBALL.md) |
| Relaxation Garden | west | soft grass, a shallow walk-over pond with stones, benches facing it, flower beds, trees ("No meetings beyond this point") |
| Coffee Corner & Break Area | east | brick patio, the **Calm Brew Café** (since 2026-10-10: a small building with a counter, espresso machine, pastry case, menu board, striped awning, glass side windows and a lit roof sign), picnic tables with parasols, a vending machine ("SNACKS for feelings") |
| Stress-Relief Zone | behind the building, at the end of the walkway north from the loop (since 2026-10-10) | sand garden, bean bags, a giant pink stress ball, rocks ("Breathe in. Breathe out. Reply later.") |

- **Clear paths:** every walkway and the entrance lane are kept free of props, and the spawn has an
  open walk out of the lobby (both spec-checked). The paths inside (bosses, stairs, elevator,
  leaderboard) are untouched.
- **Boundary:** invisible walls (60 studs tall, can't be clicked or raycast) at x ±130, z -210 / +150
  (the north edge moved from -130 for the Recreation Center, 2026-10-10), with a low hedge just inside them. The street, the ring of trees and the skyline are scenery
  outside the walls.
- **No traps or falls:** the ground is solid Terrain everywhere inside the walls; the pond is a thin
  surface you walk across (no deep water). `Workspace.FallenPartsDestroyHeight` is -60, so anyone
  who somehow ends up under the map respawns at once instead of falling for a long time.
- **Light on performance:** grounds and paths are Terrain materials (no parts). About 250 campus
  parts, built from a dozen reusable templates (bench, picnic table, tree, bush, planter, flower bed,
  lamp post, bin, bean bag, rock, vending machine, coffee kiosk, signpost) cloned into place, all
  anchored, grouped in one folder per area under `Workspace.Outdoors.Campus`. No lights or particle
  emitters (lamp globes just glow softly). Spec cap: 500 parts.
- Admins can now also place custom bosses outdoors (they're placed on the ground under the admin).
- **Recreation Center** (2026-10-10): north of the building, reached by a walkway from the loop; two
  pickleball courts for matches between players. Rules, prizes and rating: docs/PICKLEBALL.md.

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
| Hammer | Damage | Price | Look (`Config/HammerStyleConfig`) |
|---|---|---|---|
| Squeaky Hammer | 10 | free (default) | foam toy: red head, white face caps, yellow shaft, pink grip |
| Classic Office Hammer (2026-10-07) | 12 | 75 coins | wooden shaft, steel head with claw, black rubber grip, blue collar |
| Bouncy Mallet | 14 | 150 coins | rubber mallet: blue head with dark blue caps, white shaft |
| Bubble-Wrap Hammer | 18 | 400 coins | clear glassy head dotted with bubbles |
| Neon Hammer (2026-10-07) | 21 | 650 coins | dark metal with cyan and pink neon strips; tiny cyan glow |
| Rainbow Mega Mallet | 25 | 1000 coins | cartoon mega: oversized rainbow-striped head |
| Golden Hammer (2026-10-07) | 27 | 1600 coins | polished gold with bands; a few soft glints |
| Fire Hammer (2026-10-07) | 29 | 2500 coins | lava-rock head, glowing orange faces; small warm glow, a few rising embers |
| Lightning Hammer (2026-10-07) | 30 | 3500 coins | white-blue head with yellow bolts; small blue glow, the odd spark |
| Cosmic Hammer (2026-10-07) | 31 | 5000 coins | deep-space head with a glowing planet ring and stars; drifting star specks |
| Stress Crusher (2026-10-07) | 32 | 8000 coins | heavy industrial head, diamond plate, hazard stripes, square steel shaft |
| Mystery Hammer (Robux, docs/STORE.md) | 35 base, +15-25 % damage and +5-10 % crit damage rolled once | 199 R$ | gold head, purple bands and neon caps; soft purple glints |

**Level requirements (2026-10-09):** Fire Hammer Lv 15, Lightning Hammer Lv 20, Cosmic Hammer Lv 30,
Stress Crusher Lv 40, on top of the price (see "Level rewards"). Owned hammers are never taken away.

**Hammer vending machine (2026-10-07):** a blue-and-orange "HAMMER STORE" vending machine stands
in the lobby beside the stairs (`ArenaConfig.StoreMachine`, `Lib/StoreMachineBuilder`,
`StoreMachineService`). Walk up and press **E** ("Open Hammer Store") to open this same Hammers
panel (`ShopController.open`); a soft click plays and its screen says "HAPPY WHACKING!". It is only
another way in: the "Hammers" button still works, and buying still goes through `Shop.BuyHammer` and
`ShopService` (coins, ownership and equip checked on the server). The prompt does nothing on the
server. Behind its glass, three small display hammers (Squeaky, Golden, Cosmic, drawn like the real
ones) sway gently and the thin neon strips pulse softly (one repeating tween each, set up once on
the client). About 55 parts, no lights or particles; specs keep it clear of the stairs and their
landing, the walk from the spawn, the entrance, the leaderboard and every lobby part.

A bought hammer is equipped immediately; any owned hammer can be re-equipped. Pricier hammers always
hit harder, and every coin hammer stays below the Mystery Hammer's fixed base damage (both
spec-enforced). During a **Hammer Shop sale** event (docs/EVENTS.md) prices drop by the sale percent
(at least 1 coin); the server charges its own price.

### Hammer looks (2026-10-07)
Looks are data (`Config/HammerStyleConfig`), built by `Shared/HammerModel` for the held Tool (server,
`Lib/HammerTool`) and for a small still 3D preview in each shop row (client). Damage, prices and
ownership are unchanged and still come from `HammerConfig` and the player's saved data, never the Tool.
- Parts: an invisible `Handle` the hand grips, a `Shaft`, a few handle details (grip wrap, collar,
  pommel) welded to it, and the `Head` with its details (bands, face caps...) joined to it by
  `DetailWeld`s, so the swing's squash-and-stretch scales them with the head
  (`Lib/SwingAnimator`). Each hammer's swing trail has its own colour.
- Proportions and cost are capped and spec-checked: shaft 2.8-3.6 studs, head at most 2.4 studs,
  at most 10 details, at most one `PointLight` (range <= 6, brightness <= 1, no shadows, never
  changing) and one `ParticleEmitter` (<= 6 per second, short-lived, tiny). No Fire, Smoke or
  Sparkles objects. The Zen glow (`MoodService`) is unchanged and comes on top.
- A look id that doesn't exist falls back to a plain two-colour hammer, so a bad config can't leave
  a player empty-handed.

## Player Level, leaderboard and the Senior floor (2026-10-05)
### Player Level (reworked 2026-10-09)
Level comes from saved XP (`Shared/LevelRules`), never stored. **XP** per defeat is the score earned
x `XpRewardMultiplier` (1.2) x any XP store boost and XP event. Score itself is never boosted, so the
leaderboard stays fair.

**The curve.** Going from level L to L + 1 costs `600 x (2L - 1)` XP, the original square curve; from
Level 10 on (`LevelCurveStartsAt`) that cost is also multiplied by `1 + 0.2 x (L - 9)`
(`LevelCurveGrowth`), so later levels are real goals. **Levels stop at 100** (`MaxLevel`); XP keeps
counting and still ranks the Top Level board. Below Level 10 nothing changed.

| Level | Total XP | Ideal solo farming* |
|---|---|---|
| 2 | 600 | |
| 5 | 9,600 | |
| 10 | 48,600 (unchanged) | ~25 min |
| 20 | 421,200 | ~1.3 h |
| 30 | ~1.6 M | ~4 h |
| 50 | 8,427,000 | ~18 h |
| 75 | ~30 M | ~56 h |
| 100 | 73,530,000 | ~127 h |

\* A model: one player always on the best boss for XP, a hit every 0.45 s, 5 s respawns, sensible hammer
upgrades. Real play (walking, sharing bosses, breaks) is roughly 2-3x slower; XP boosts, events and
group play are faster. Before 2026-10-09 Level 100 took ~9 hours in the same model and there was no cap
(admins could set up to 500).

**Nobody lost a level** when the curve got steeper: schema v10 raised every existing player's XP to the
new curve's threshold for the level they had (docs/DATA_SCHEMA.md), and those levels count as already
rewarded.

### Level bonuses (2026-10-08, rebalanced 2026-10-09)
Every level above 1 makes the character permanently stronger (`GameConfig.LevelDamagePerLevel`,
`LevelDamageSlowsAt`, `LevelDamagePerLevelAfter`, `LevelCritChancePerLevel`, `Shared/LevelRules`):

| Level | Base damage bonus | Crit chance |
|---|---|---|
| 1 | +0 | 5.00 % |
| 2 | +3 | 5.05 % |
| 5 | +12 | 5.20 % |
| 10 | +27 | 5.45 % |
| 11 | +28 | 5.50 % |
| 50 | +67 (was +147) | 7.45 % |
| 100 (max) | +117 (was +297) | 9.95 % |

- **Base damage:** +3 per level up to Level 10, then **+1 per level** (2026-10-09; was +3 all the way).
  At Level 50 the old bonus was 147, nearly five times the best coin hammer (32), so hammers stopped
  mattering. Now hammers, boosts and pets stay worth having. The bonus is added to the equipped
  hammer's damage before every percent bonus: Squeaky Hammer at Level 10 is 10 + 27 = 37 per normal hit
  on a x1 boss.
- **Crit:** the chance a hit crits, +0.0005 per level (0.05 percentage points, not 5 %). Crit *damage*
  bonuses (Mystery Hammer, Crit Damage boosts, pets) are separate and still add up.
- **Never stored, never awarded twice.** Worked out from the level (from saved XP) every time a hit is
  calculated (`BuffService.statsFor`). A jump of several levels gives every level's share at once. If an
  admin lowers a level, the bonus follows it down. Nothing grows past Level 100.
- **Boosts, pets and events stay separate:** they add on top and stop when they end. XP boosts and
  XP events only change how much XP is earned, never the level directly.
- **UI:** the Player Panel's Profile shows Base damage (hammer + level bonus), Crit chance, your title
  and a level bar. A "🎉 LEVEL UP!" card shows the gains, coins and unlocks, one card for levels gained
  close together (`LevelUpController`).

### Level rewards (2026-10-09)
Levels have a purpose (`Config/LevelRewardConfig`, `Shared/LevelRewardRules`, Player Panel → 🏅 Levels):

- **Coins every level:** reaching level L pays `20 x L` coins (Level 10 pays 200, Level 50 pays 1,000;
  about 100k over the whole climb). Paid by the server when XP crosses the level
  (`SessionService.addXp`), once: `LevelRewardsClaimed` remembers the highest level paid, so rejoining
  or dropping and regaining a level never pays twice. Levels an admin sets (Set Level) count as rewarded
  without coins. Admin **XP** rewards are earned XP and do pay.
- **Something every 5 levels:**

| Level | Unlock | Level | Unlock |
|---|---|---|---|
| 5 | title Junior Associate | 55 | Galaxy Trail |
| 10 | title Associate, the Senior floor, Warm Wood office theme | 60 | title Director, Night Sky office theme |
| 15 | Mint Trail, Fire Hammer in the shop | 65 | Aurora Glow |
| 20 | title Senior Associate, Lightning Hammer, Executive Desk | 70 | Lava Trail |
| 25 | Ocean Glow | 75 | title Vice President |
| 30 | title Team Lead, Cosmic Hammer, Aquarium | 80 | Violet Glow |
| 35 | Sunset Trail | 85 | Ice Trail |
| 40 | title Manager, Stress Crusher, Garden office theme | 90 | Sunburst Glow, Royal Gold office theme |
| 45 | Rose Glow | 95 | Prism Trail |
| 50 | title Senior Manager, Zen Fountain | 100 | title **Chief Calm Officer**, golden name tag 👑, Golden Hammer Statue |

- **Titles** follow the level on their own: the head tag reads "Lv 23 · Senior Associate" (MoodService),
  gold with a crown at Level 100. Level 1 is "Intern".
- **Looks:** an unlocked **hammer trail** replaces the hammer's own swing-trail colour; an unlocked
  **Zen glow** colours the light and sparkles of your hammer in Zen (gold by default). Pick them on the
  🏅 Levels page (`Level.SetCosmetic`, checked by the server); everyone sees them. If an admin lowers
  your level below a pick, the default look shows until you're back.
- **Hammer level requirements:** Fire Hammer Lv 15, Lightning Lv 20, Cosmic Lv 30, Stress Crusher
  Lv 40 (`HammerConfig.MinLevel`), checked by the server (`ProgressionRules.checkPurchase`); the shop
  shows "🔒 Lv 30". Hammers you already own stay yours and can always be equipped.
- **Career (major update):** these titles *are* the career ranks; there is no separate career level
  (docs/MAJOR_GAME_UPDATE.md §21.4). Quests, pickleball and co-op will give XP.
- **Office rewards (docs/OFFICES.md):** office themes (walls and carpet) are a third look picked on
  the 🏅 Levels page; level-reward furniture appears in the office editor's "Level rewards" tab.

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
level its bar reads "LOCKED: reach Lv 10" and swings show "Reach Level 10 to fight this boss!".
This spreads experienced players across two floors instead of crowding one boss.

### Department Heads (3rd floor, Level 30+, 2026-10-10)
Each Senior boss has a **Principal** version on the 3rd floor, reached by the tower elevator: Level 30
and 1 defeat of its Senior version, tougher than every Senior boss and paying more. Numbers and the
floor: docs/TOWER.md.

### Boss labels (2026-10-06)
A boss's name, HP bar and speech bubble float above it, sized in studs (they shrink with distance) and
shown up to 60 studs away. They are **not** drawn on top of walls: before, every boss in the building
showed its label through the walls and they piled up on top of each other. Damage numbers follow the
same rule.

### Office doors (2026-10-08)
Each boss office has a sliding door that shows **this player's** access
(`Controllers/OfficeDoorController`, `Lib/OfficeDoors`):
- **Same rule as the fight:** a door is open exactly when `ProgressionRules.unlockStatus` says the
  player may fight that boss (previous-boss defeats, Senior Level 10, admin unlocks). It uses the
  saved progress the server sends in `Profile.Sync`. There is no second requirement system.
- **Per player:** doors are built on each client, so a Level 10 and a Level 50 player in the same
  server see different doors. One player's unlock never opens anyone else's door.
- **Locked:** two solid panels block that player's character, with a small sign beside the doorway:
  "🔒 Requires Level 10" or "🔒 Beat Deadline Boss x1".
- **Unlocked:** the panels slide into the wall (0.45 s tween) and the sign says "✓ AVAILABLE", or
  "✓ BEATEN x3" once beaten. This happens as soon as the unlock arrives (a defeat, a level-up, an
  admin unlock), with no rejoin. Joining sets every door from the first sync, and respawning
  changes nothing.
- **Closing again** (only when an admin lowers a level or removes an admin unlock) waits until the
  player has left that office and its doorway, so nobody is shut in.
- **Not the security:** the server refuses every hit on a boss the player hasn't unlocked
  (`CombatService` → `ProgressionRules.isBossUnlocked`), so deleting or going around a door gives
  nothing. Bosses stay shared server objects; nothing is duplicated per player.
- **Cost:** doors update only when progress changes. There is no per-frame check, only a 1 s check
  while a door is waiting to close.

### Admin-created bosses
Admins can place extra bosses anywhere (docs/ADMIN.md). They're open to every player, take normal
damage, give the score and coins the admin set, and each qualifying player (10 % of its HP) gets one
random 30-minute store boost in their Bag (docs/STORE.md "Bag and gifts"). They don't count toward
unlocking office bosses.

### Global leaderboard
The "Hall of Calm" on the lobby's west wall (18 x 12 studs, gold frame and plaque) lists the
all-time top 10 across all servers (`LeaderboardService`). Without DataStore access (Studio with API
access off) it ranks the players in the current server and says so.

Redesigned 2026-10-07 (was a plain text list by score):
- **Tabs** (click on the board): **Top Score** (lifetime Score, `ScoreLeaderboard`), **Top Level**
  (by XP, `XpLeaderboard`) and **Top Coins** (current coins, `CoinsLeaderboard`). Each player picks
  their own tab; it changes nothing for anyone else.
- **Columns:** Rank, Player, Score, Level, Coins. The ranked column is gold. A value shows "-" when
  it isn't known (an offline player outside that stat's top 10); players in your server always show
  their live values.
- **Top 3:** #1 has a gold row, gold outline and gold name; #2 and #3 have silver and bronze badges
  and thin outlines.
- **Your Rank** under the list: "#4 on the board", or "#2 in this server ... the board starts at
  48,600 score".
- **Updates:** values are written from the server's saved data every 2 minutes (each only when it
  changed) and on leave; the stores are read every minute, and players joining or leaving re-send
  the board from the cached pages (no extra DataStore calls). Rows that changed fade and slide in.
  The board's rows are built once per client; updates only change text and colours.
- **Server-authoritative:** the server merges the stores with live data (`Lib/LeaderboardRules`) and
  sends one snapshot to every client (`Leaderboard.Snapshot`, server -> client only). There is no
  remote from the client, so nobody can change a ranking. Players whose data is still loading are
  left out until it loads.
- **Existing rankings are kept:** `ScoreLeaderboard` is unchanged. The XP and Coins boards start
  empty and fill as players play (each player's values are written within 2 minutes of joining).

### Sprint
Hold **Shift** (keyboard), press the **left stick (L3)** (gamepad) or tap the **Sprint** button (touch)
to run at `SprintSpeed` (26) instead of `WalkSpeed` (16), with a slight camera zoom-out. A toggle
(L3 or the touch button) switches off once the character has run and then stopped. The client applies
the speed. The server's movement guard (50 studs/s) still applies; the config spec makes sure
sprinting stays well under it.
Note: a player who turned on Roblox's own *Shift Lock* setting will toggle it with Shift too
(it's off by default).

### Swing feel
One swing lasts exactly `HitCooldown` (0.45 s) and is pure client visuals (`Shared/SwingPose`,
`Lib/SwingAnimator`); the server never uses it to decide a hit.
| Beat | Share of the swing | What you see |
|---|---|---|
| Wind-up | 0-24 % | arm lifts, hammer cocked back over the head |
| Anticipation | 24-34 % | a slow extra coil at the top |
| Strike | 34-50 % | fast snap forward; head stretches, coloured trail; the hit request is sent at 50 % |
| Impact | 50-66 % | head squashes, the hammer bounces back up a little off the boss, then settles (2026-10-07; was a follow-through past the boss) |
| Return | 66-100 % | smooth swing back onto the shoulder |

Each confirmed hit of yours adds a soft white flash on the boss, a few golden / white sparkles, a
tiny impact ring, a small camera shake (0.08 s), a short "bonk" (built-in sound, higher pitched on
crits; 2026-10-07) and the boss's hop.

### Hit effects (2026-10-07, `Lib/HitEffects`, local visuals)
| Hit | Sparkles | Floating motes | Ring |
|---|---|---|---|
| Yours | 6 (10 on a crit, warmer gold) | 2 pastel | bright |
| Someone else's | 3 (7 on a crit) | none | faint |
| Defeating hit | 14 | 8 pastel | as above |

- **Pooled per boss:** the first hit builds one rig on the boss (an Attachment with two emitters, a
  ring billboard, and one Highlight on the drawn monster). Every later hit only calls `Emit()` and
  restarts two prebuilt tweens, so nothing is created per hit. Emitters are never `Enabled` (no
  continuous emission) and particles live under a second.
- **Cleanup:** the rig is parented to the boss, so it goes away with it (defeat, respawn, streaming
  out). The pools use weak keys. Damage numbers are still removed by `Debris` after 0.7 s.
- **Soft:** sparkles are small (0.35 studs) with low light emission; the flash is a light fill
  (`FillTransparency` 0.55) for 0.1 s on the monster only, never full-screen; no lights are added.
- **Far away:** hits more than 90 studs from your camera show no effects, so many bosses and
  players stay cheap.
- Was (until 2026-10-07): a new Highlight and a new 14-particle emitter on every hit (large, fast,
  bright sparks).

**Clicking (2026-10-07):** one swing per `HitCooldown`. A press in the last 0.12 s of a swing queues
exactly one more swing for the moment the cooldown ends; every other press during a swing is ignored.
Nothing is created per swing: each holder has one swing state that `play()` restarts, so swings can't
stack. The posing runs from a single `PreRender` connection that exists only while someone holds a
hammer, and at rest it does no work (the rest pose is set once; the Animator never overwrites it).

### Music
`AudioController` loops `MusicConfig.Tracks` with fades and a "Music: On/Off" button. The list is
empty until licensed tracks are added (see `docs/RELEASE.md` §4).

## Boss personalities (2026-10-07)
Bosses feel alive between whacks. All of this is drawn by each client
(`Controllers/BossVisualController`, maths in `Shared/BossMotion`, values in
`Config/BossPersonalityConfig`); the server's hitbox, health, rewards and shouts are unchanged, so
none of it affects hit detection or can be abused.

| Boss (and its Senior) | Personality | Idle | Fidget every 4-8 s |
|---|---|---|---|
| Deadline Boss | always in a hurry | quick bob, fast little steps | two quick foot-taps |
| Meeting Master | stressed executive | paces, looks around a lot | nervous glance over the shoulder |
| Reply-All Boss | overwhelmed by email | jittery | flinches at an incoming "ping" |
| Production Bug | confused developer | looks both ways, wide sway | tilts its head: "huh?" |
| Monday Monster | sleepy | slow bob | a big yawn |
| The CEO | pompous | slow | puffs itself up |

Admin-created bosses behave like the boss whose look they borrow.

- **Looking around:** a boss faces you when you're within 30 studs on its floor; otherwise it looks
  around (toward its door and back and forth).
- **Moving slightly:** the drawn monster shuffles side to side by at most 0.8 studs; the hitbox
  never moves.
- **Noticing you:** walking within 14 studs (after being 24+ away) makes it hop in surprise, "ping",
  and say a short line to you, e.g. "Hey! Is it done yet?", "I need coffee!", "Huh? Who's there?";
  locked bosses say "Not so fast! Come back later." At most once every 12 s per boss.
- **Hit reaction:** the existing lean-back hop plus a short dizzy wobble, and a cartoon "boing"
  pitched to the boss's personality, at most every 0.7 s per boss however many players hit it.
  Sometimes (40 %, at most every 3 s) your own hit gets a line: "Ouch!", "Okay, okay!", "Not again!",
  "That's a feature!". Defeat plays the "boing" pitched down, with the existing spin.
- **Lines** are short (<= 30 characters), written by us, never rude (spec-checked against the same
  blocked words as the shouts), shown in the boss's speech bubble to you only, and never cover a
  server shout.
- **Sounds:** Roblox built-in files (`action_jump.mp3`, `electronicpingshort.wav`), so no uploads;
  at most two `Sound`s per boss, created on first use under the boss and reused, removed with it.
  Not played farther than 60 studs. To use real voice clips ("Hey!", "Ouch!"), upload them and put
  their ids in `BossPersonalityConfig.Sounds`.
- Bosses never attack or hurt players.

## Player Panel (2026-10-07)
A **Menu** button (top-left), **M** or **Y** on a controller opens the Player Panel (`PlayerPanelController`, built on
`Lib/PanelKit` like the Admin Panel): a wide window with a sidebar (a top tab strip on narrow
screens), cards, scrolling content, a quick scale-in/out animation and a close X.

| Page | What's there |
|---|---|
| Profile | level and title, XP to the next level, score, coins, stress, Zen bonus (updated live, text only); active boosts with time left; your leaderboard line |
| 🏅 Levels (2026-10-09) | your title and next reward, trail and Zen glow pickers, the whole reward track |
| Hammers | equipped hammer and its damage; every hammer you own with **Equip** (the existing `Shop.EquipHammer`, server-checked); a link to the Hammer Shop; your Bag's item count and **Open Bag** |
| Game | shortcuts to the Hammer Shop, the Robux Store, the Bag (the existing panels) and, for admins, the Admin Panel; where things are in the office |
| 🏢 Social (2026-10-09) | your office (go there, edit, who can visit) and every office in the server to visit (docs/OFFICES.md); also the 🏢 Social HUD button |
| Settings (2026-10-09) | saved on/off switches (Reduced motion) and the music switch when there is music (docs/UI.md "Settings") |
| Help | how to play, controls (computer, phone, controller) |

It only shows what already exists and only displays server data; its own requests are
`Settings.Set` (Settings page) and the `Office.*` trips and privacy (Social page, 2026-10-09), all
checked by the server. The
existing HUD buttons (Hammers, Store, Bag, Admin, Music) all still work.

## Lobby lounge NPCs (2026-10-07)
Four friendly office workers make the lounge by the leaderboard feel lived-in (`Config/NpcConfig`,
built by `Lib/NpcBuilder` / `NpcService`, animated by `NpcController` on each client):

| NPC | Where | Doing |
|---|---|---|
| Rita (Reception) | behind the reception desk, facing the lobby | looks around; waves and says hello when you walk up |
| Ben (Accounting) | west couch, left | reads a book, looks up now and then, turns a page |
| Mia (Design) | west couch, right, turned to Ben | sips coffee and chats with Ben |
| Sam (IT) | by the water cooler | sips coffee, looks around |

- **Look:** blocky cartoon staff in the same plain-parts style as the bosses: shirt and tie or a
  name badge, smiling drawn faces, different skin, hair and shirt colours, and a prop (clipboard,
  book, coffee mug).
- **Talking:** walking within 10 studs gets a greeting (at most every 25 s per NPC); every 10-18 s
  one NPC near you says a line, and Ben and Mia answer each other. Lines are short, friendly and
  spec-checked ("Welcome to Stress Relief Dept.!", "Need a stress break?", "Nice score today!",
  "I need more coffee!"). Bubbles are shown to you only.
- **Never in the way:** no `Humanoid`, every part non-colliding, unclickable and untouchable, kept
  out of the space in front of the leaderboard, the stairs, the vending machine, the spawn and the
  entrance (spec-checked). They live in `Workspace.LobbyNpcs`, not `Workspace.Bosses`, so combat,
  stress, XP, coins and the leaderboard never see them.
- **Light:** about 13 parts each, built once by the server; each client runs a few repeating tweens
  per NPC (started once) and one distance check every 0.5 s for all of them. No per-frame work.

## Boss shouts (2026-10-05)
Every boss shouts lines about its fictional "job" (`BossShoutConfig`) in a speech bubble above its
HP bar that everyone nearby sees: one every 8–15 s (`ShoutIdleMin`/`ShoutIdleMax`) and, with a 20 %
chance, when hit (`ShoutHitChance`, at most one shout per `ShoutCooldown` 4 s). The server picks the
line so all players see the same shout. Lines are written by us (not players), stay family-friendly,
and a spec rejects a blocklist of bad words, including for the angry CEO.

## Executive Floor and the CEO (2026-10-05)
- **Unlock:** defeat **every** ground-floor and Senior boss at least once (Level 10 is implied by the
  Senior bosses). Rule: `BossConfig.UnlockAfterAllBosses` on the CEO.
- **Getting there:** the **tower elevator** at the west end of the corridor (since 2026-10-10 one
  shaft for every floor with a floor panel, docs/TOWER.md). The server checks access; without it the
  panel and a toast say what's missing ("Defeat every boss once (N to go)"). Anyone found on the floor
  without access is sent back down.
- Since 2026-10-10 the Executive Floor is the **4th (top) floor**, above Department Heads, with the
  Rooftop Lounge over it (docs/TOWER.md).
- The Principal tier (3rd floor, docs/TOWER.md) is **not** part of this unlock and not counted in the
  CEO's health.
- **Stress spike:** arriving on the Executive Floor sets the Stress Meter to **100 %** (and re-arms Zen).
- **The CEO:** a 1.6× size, crowned raid boss. **MaxHealth = 150 × the toughest other boss**
  (`GameConfig.CeoHealthMultiplier`, derived from config: 150 × 600 = **90,000** today). Rewards
  5,000 score and 1,000 coins, split by damage share like every boss, plus the last-hit bonus.
  Designed for a team: roughly 30 minutes solo with the best hammer, a few minutes for ten players.
