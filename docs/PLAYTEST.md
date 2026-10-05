# Playtest Checklist

Unit specs cover the rules; these checks cover what only a live server shows.
Record the date, build (commit) and result for each run in the PR.

## Setup
1. `scripts\check.ps1` (builds `build\WhackItOut.rbxl`).
2. In Studio, close any open copy of the place, then **File → Open from File** → `build\WhackItOut.rbxl`.
   The place has its own floor and spawn (`Workspace.Arena`). If you instead `rojo serve` into a
   place that already has a Baseplate, delete one of the two floors.
3. Open **View → Output** (newer Studio: **Window → Output**).

## Phase 2: shared boss loop

### Solo (Test → Play, F5)
| # | Check | Expected |
|---|---|---|
| 1 | Spawn | Floor; an orange cartoon monster with angry eyes, a toothy mouth and a "DUE TODAY!" sign, bobbing and turning to face you, with name + HP bar `100 / 100`. You carry a red-and-yellow hammer resting on your right shoulder. HUD shows `Stress 100 / 100`, `Score: 0`, hint at the bottom; no hotbar |
| 2 | Click while far from the boss | Your character swings the hammer (animation + swish sound), "Get closer to the boss!" appears above the hint, the boss doesn't react |
| 3 | Walk up and click | A full swing: arm lifts with the hammer cocked back, then a fast strike with a swish that puts the hammer out in front on the boss, a little follow-through, and the hammer swings back onto your shoulder; the boss flashes white, leans back with a hop, yellow `-10` floats up, small camera shake, HP `90 / 100`, stress drops by 1 |
| 3b | Hammer orientation | At rest the hammer lies back over your shoulder; at the hit it points out in front, head on the boss; then it returns to the shoulder. **Report where the head ends up if any of these look wrong (e.g. pointing down, sideways, or into your body).** |
| 4 | Click as fast as possible | Swings complete one after another (never cut off mid-swing); about 2 hits per second land |
| 5 | Defeat the boss | HP bar shows `DEFEATED!`, the monster spins and shrinks away, Victory Card `+100 score -5 stress`, Score `100` in HUD and player list |
| 6 | Wait ~5 s | A fresh boss at `100 / 100` replaces it; hitting works again |
| 7 | Reset character (Esc → Reset) mid-fight | You respawn holding a new hammer; HUD and HP bars stay; hitting works again |
| 8 | Output window | No red errors. No `[Remote] rejected` warnings during normal play. In Studio the server prints `[Combat] hit from <name> ignored: <reason>` (max once/s) for swings that don't land, e.g. `out of reach (11.0 > 10.5 studs)`. If a hit you expected doesn't land, copy that line into your report. If the arm doesn't swing, look for `[SwingAnimator] no right-shoulder joint …` and include it |

### Shared boss (Test → Clients and Servers → 2 or 3 players → Start)
| # | Check | Expected |
|---|---|---|
| 9 | Both players hit the same boss | Both see the same HP and each other's swings; each sees their own hits in yellow, the other's in grey; the monster turns to face each viewer |
| 10 | Player A deals most damage, player B ≥ 1 hit (≥ 10 HP) | Both get `+100 score` Victory Cards |
| 11 | Player B never hits the boss | B gets no Victory Card and no score (the below-10%-share case is covered by `BossState` specs) |
| 12 | Both hit on the defeating moment | Exactly one defeat; each qualifying player rewarded once |
| 13 | A player leaves mid-fight | No errors; the remaining player can finish and is rewarded |

### Abuse (server Output)
| # | Check | Expected |
|---|---|---|
| 14 | Hold an autoclicker on the boss | Hit rate stays at the cooldown; no errors |
| 15 | From the client command bar: `game.ReplicatedStorage.Remotes.Combat.RequestHammerHit:FireServer("nope")` | No hit; no error |
| 16 | Same with `FireServer(123)`, `FireServer({})`, `FireServer(string.rep("a", 1000))` | `[Remote] rejected RequestHammerHit … invalid bossInstanceId` (throttled), no hit |
| 17 | `for i = 1, 200 do …:FireServer("boss-1") end` from far away | No damage; `rate limited` warning at most once per 5 s |

## Phase 3: saving progress
Real saving needs **Game Settings → Security → Enable Studio Access to API Services** turned on
(use a test place or your own account: it writes to the live DataStore). With it off, everything
works but nothing is kept between Play sessions.

| # | Check | Expected |
|---|---|---|
| 18 | First join (API access on) | HUD `Score: 0`, `Stress 100 / 100`; you can hit as soon as the score appears |
| 19 | Earn score, relieve some stress, Stop, Play again | Score and stress are exactly where you left them |
| 20 | Output on join/leave | No `[PlayerData]` warnings or red errors |
| 21 | API access off | A "mock" note from ProfileStore may appear; play works; progress resets next session |
| 22 | Two Studio test servers can't share a session; on a live server, joining a second server with the same account | The first server kicks you with "Your progress was opened on another server…" and nothing is lost |

## Phase 4: rewards, unlocks and shop
| # | Check | Expected |
|---|---|---|
| 23 | Spawn | You start in the lobby facing a corridor of five offices, each with a name plate over its door; inside each office a monster stands between the desk, cabinet and plants. Only Deadline Boss is in colour, the other four grey with "LOCKED: beat …" bars. HUD shows `Score: … Coins: …`; a "Hammers" button bottom-right |
| 24 | Swing at a locked boss | Swing plays, toast "Defeat Deadline Boss 3 more times to unlock!", no damage |
| 25 | Defeat Deadline Boss | Victory Card `+100 score +10 coins -5 stress`; Coins in HUD and player list +10 |
| 26 | Defeat it 3 times total | Third Victory Card adds "NEW BOSS UNLOCKED: Meeting Master!"; Meeting Master turns colourful and can be hit |
| 27 | Open Hammers with < 150 coins | Squeaky Hammer "Equipped"; others "Need 150/400/1000" (greyed) |
| 28 | Earn 150 coins, Buy Bouncy Mallet | Coins −150, hammer in hand changes to the blue/white mallet, row shows "Equipped"; hits do 14 × boss multiplier |
| 29 | Equip Squeaky Hammer again | Hammer swaps back; damage back to 10 × multiplier |
| 30 | Stop and Play again (API access on) | Coins, bought hammers, equipped hammer and unlocked bosses are all kept |
| 31 | Rapid double-click Buy | Bought once; coins deducted once |
| 32 | Command bar: `game.ReplicatedStorage.Remotes.Shop.BuyHammer:FireServer("rainbow_mega_mallet")` without enough coins | Nothing bought; no error |

## Phase 4b: mood, Zen and reward split
| # | Check | Expected |
|---|---|---|
| 33 | Spawn at 100 stress | Your character has a frowning face with angry brows and a sweat drop |
| 34 | Hit bosses until stress ≤ 75, ≤ 50, ≤ 25 | Face changes: frown without sweat → flat mouth → smile |
| 35 | Bring stress to 0 | "ZEN ACHIEVED! +100 coins Zen Level 1" card; happy closed-eyes face with blush; hammer glows and sparkles; HUD shows `Zen Lv 1`, coins +100 |
| 36 | Keep hitting at 0 | Stays Zen, hammer keeps glowing; no second Zen reward |
| 37 | Stop hitting for 2 minutes | Stress rises by 5 every 5 s; the glow stops as soon as stress is above 0; the face changes with the bands |
| 38 | Let stress rise to only ~20, then bring it back to 0 | No Zen reward this time (not re-armed); let it reach 50+ and back to 0 → Zen pays again |
| 39 | Two players, A deals ~70 %, B ~30 % and lands the last hit | Each Victory Card shows "your share" %; A's score/coins ≈ 70 % of the boss reward, B's ≈ 30 % + "LAST HIT BONUS!" |
| 40 | A player deals under 10 % | Gets a small score/coin share but "Deal at least 10% of its HP to count the defeat."; no unlock progress |
| 41 | Second client watching | Sees the other player's face and hammer glow change, and a toast when they reach Zen |

## Phase 6: hardening
| # | Check | Expected |
|---|---|---|
| 42 | From the **server** command bar (Test → Clients and Servers), teleport a player next to a boss: `game.Players:GetPlayers()[1].Character:PivotTo(CFrame.new(-68, 4, -32))`, then swing within 5 s | Server Output prints `[MovementGuard] … hits ignored for 5 s`; swings in those 5 s do no damage; after that hits land |
| 43 | Walk, jump and run around normally for a minute | No `[MovementGuard]` lines |

