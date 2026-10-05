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
| 1 | Spawn | Floor, an orange "Deadline Boss" block ahead with name + HP bar `100 / 100`; HUD shows `Stress 100 / 100`, `Score: 0`, hint at the bottom |
| 2 | Click while far from the boss | Nothing happens (out of reach) |
| 3 | Walk up and click | White flash, yellow `-10`, small camera shake, HP `90 / 100`, stress drops by 1 |
| 4 | Click as fast as possible | At most ~4 hits per second land |
| 5 | Defeat the boss | HP bar shows `DEFEATED!`, boss fades, Victory Card `+100 score -5 stress`, Score `100` in HUD and player list |
| 6 | Wait ~5 s | A fresh boss at `100 / 100` replaces it; hitting works again |
| 7 | Reset character (Esc → Reset) mid-fight | HUD and HP bars stay; hitting works after respawn |
| 8 | Output window | No errors. No `[Remote] rejected` warnings during normal play |

### Shared boss (Test → Clients and Servers → 2 or 3 players → Start)
| # | Check | Expected |
|---|---|---|
| 9 | Both players hit the same boss | Both see the same HP; each sees their own hits in yellow, the other's in grey |
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
