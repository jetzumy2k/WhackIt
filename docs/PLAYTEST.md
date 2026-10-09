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
| 3 | Walk up and click | A full swing: arm lifts with the hammer cocked back, then a fast strike with a swish that puts the hammer out in front on the boss, a small bounce off the boss, and the hammer swings back onto your shoulder; a short "bonk"; the boss flashes white, leans back with a hop, yellow `-10` floats up, small camera shake, HP `90 / 100`, stress drops by 1 |
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
| 24 | Swing at a locked boss | Swing plays, toast "Defeat Deadline Boss 1 more time to unlock!", no damage |
| 25 | Defeat Deadline Boss | Victory Card `+100 score +10 coins -5 stress`; Coins in HUD and player list +10 |
| 26 | Defeat it once | The Victory Card adds "NEW BOSS UNLOCKED: Meeting Master!"; Meeting Master turns colourful and can be hit |
| 27 | Open Hammers with < 75 coins | Squeaky Hammer "Equipped"; others "Need 75/150/400/650/1000/1600/2500/3500/5000/8000" (greyed); each row has a 3D preview of its hammer |
| 28 | Earn 150 coins, Buy Bouncy Mallet | Coins −150, hammer in hand changes to the blue rubber mallet, row shows "Equipped"; hits do 14 × boss multiplier |
| 29 | Equip Squeaky Hammer again | Hammer swaps back; damage back to 10 × multiplier |
| 30 | Stop and Play again (API access on) | Coins, bought hammers, equipped hammer and unlocked bosses are all kept |
| 31 | Rapid double-click Buy | Bought once; coins deducted once |
| 32 | Command bar: `game.ReplicatedStorage.Remotes.Shop.BuyHammer:FireServer("rainbow_mega_mallet")` without enough coins | Nothing bought; no error |

## Phase 4b: mood, Zen and reward split
| # | Check | Expected |
|---|---|---|
| 33 | Spawn at 100 stress | Your character has a flustered face: worried brows (not angry), a little "o" mouth and a sweat drop |
| 34 | Hit bosses until stress ≤ 75, ≤ 50, ≤ 25 | Face changes: worried with a small wobbly mouth → small smile → bigger smile |
| 35 | Bring stress to 0 | "ZEN ACHIEVED! +100 coins Zen Level 1" card; happy closed-eyes face with blush; hammer glows and sparkles; HUD shows `Zen Lv 1`, coins +100 |
| 36 | Keep hitting at 0 | Stays Zen, hammer keeps glowing; no second Zen reward |
| 37 | Stop hitting for 20 s | Stress rises by 5 at 20 s, then every 5 s; the glow stops as soon as stress is above 0; the face changes with the bands |
| 38 | Let stress rise to only ~20, then bring it back to 0 | No Zen reward this time (not re-armed); let it reach 50+ and back to 0 → Zen pays again |
| 39 | Two players, A deals ~70 %, B ~30 % and lands the last hit | Each Victory Card shows "your share" %; A's score/coins ≈ 70 % of the boss reward, B's ≈ 30 % + "LAST HIT BONUS!" |
| 40 | A player deals under 10 % | Gets a small score/coin share but "Deal at least 10% of its HP to count the defeat."; no unlock progress |
| 41 | Second client watching | Sees the other player's face and hammer glow change, and a toast when they reach Zen |

## Phase 6: hardening
| # | Check | Expected |
|---|---|---|
| 42 | From the **server** command bar (Test → Clients and Servers), teleport a player next to a boss: `game.Players:GetPlayers()[1].Character:PivotTo(CFrame.new(-68, 4, -32))`, then swing within 5 s | Server Output prints `[MovementGuard] … hits ignored for 5 s`; swings in those 5 s do no damage; after that hits land |
| 43 | Walk, jump and run around normally for a minute | No `[MovementGuard]` lines |

## Phase 7: content and polish
| # | Check | Expected |
|---|---|---|
| 44 | Spawn | HUD shows `Lv 1`; "Lv 1" floats above your head; a "Music: On" button only if tracks are configured |
| 45 | Lobby | Leaderboard board on the west wall ("TOP STRESS RELIEVERS"); in Studio with API access off its footer says "This server only" |
| 46 | Play for a while | Within ~2 minutes "Progress saved" flashes bottom-left |
| 47 | Walk the stairs (east side of the lobby) | Smooth climb to the upper corridor with a glass railing over the lobby; five crowned Senior bosses, greyed with "LOCKED: reach Lv 10" |
| 48 | Swing at a Senior boss below Level 10 | Toast "Reach Level 10 to fight this Senior boss!", no damage |
| 49 | Reach Level 10 (or test with a temporarily lower `UpstairsMinLevel`) after defeating the ground boss once | Senior boss turns colourful; Victory Card can show "NEW BOSS UNLOCKED: Senior …" when the level-up happens |
| 50 | Look around | Calm, darker rooms: slate walls and ceilings, warm dim lights, no glare; thin cyan (ground) and purple (upstairs) LED strips along the corridors; windows in office back walls show grass, trees and the skyline; the lobby's glass front looks out onto the campus, with an open entrance in the middle |
| 51 | Swing | Brief pause at the top, hammer head stretches then squashes, white trail, spark burst on the boss, stronger shake |

## Phase 7b: shouts, Executive Floor and the CEO
| # | Check | Expected |
|---|---|---|
| 52 | Stand near any boss for ~15 s | A speech bubble with a job-related line appears above its HP bar for a few seconds; other players see the same line |
| 53 | Hit a boss repeatedly | Now and then it shouts back (not more than once every 4 s) |
| 54 | 2nd floor, west end of the corridor: use "Ride up" before beating every boss | Toast "Executive Floor: defeat every boss once first (N to go)." (or the level message); you stay on the 2nd floor |
| 55 | Beat every boss once (for testing, temporarily lower `UpstairsMinLevel` and play through), then "Ride up" | You arrive on the Executive Floor, stress jumps to 100 % (frazzled face), toast "Welcome to the Executive Floor…" |
| 56 | The CEO | A big crowned monster with "Q4 RESULTS?!" sign, HP bar `90000 / 90000`; angry but clean shouts; hits land and the bar drops |
| 57 | "Ride down" on the 3rd floor | Back on the 2nd floor next to the elevator |
| 58 | (Server command bar) teleport a player without access onto the 3rd floor: `game.Players:GetPlayers()[1].Character:PivotTo(CFrame.new(0, 33, -10))` | Within ~1 s they are sent back down with the "defeat every boss" toast |

## Phase 8: crits, Zen buff, XP and the Robux store
| # | Check | Expected |
|---|---|---|
| 59 | Hit bosses for a while | About 1 in 20 hits shows a bigger orange "CRIT! -N" (about 1.5x damage) |
| 60 | Reach 0 stress | Under the score line: "ZEN +10 dmg +5% crit 2:59" counting down; hits do about 10 more damage; crits more frequent; line disappears after 3 minutes |
| 61 | Existing save from before Phase 8 | Same Level as before (XP starts at old Score); Score unchanged |
| 62 | "Store" button (above "Hammers") with no product ids configured | Tabs XP Boost / Damage / Crit Dmg / (Mystery) / (Admin in Studio); each shows "Coming soon." |
| 63 | Buy a boost in Studio (test purchase), e.g. +10% XP 30 min | Toast "+10% XP boost (30 min) added to your Bag..."; the boost is **not** active yet; "Bag (1)"; Output has no `[Purchase]` warnings |
| 64 | Open the Bag and press Use; buy and use the same boost again | HUD shows "XP +10% 29:59"; the second Use adds the time (about 59:xx), percent stays the strongest |
| 65 | Leave and rejoin | Boost still there with the same time left (it doesn't count down while offline) |
| 66 | Mystery tab | Odds text: damage 20 to 35, each 1 in 16 (6.25%); crit +5% to +10%, each 1 in 6 (16.7%) |
| 67 | Buy the Mystery Hammer (test product id), then Bag > Open | After buying: in the Bag, nothing equipped yet. After Open: toast with the rolled stats; gold and purple hammer in hand; listed under "Hammers" with "Equipped" |
| 68 | Admin tab: "Close now" | Store shows "The store is closed right now" for other players (a second client loses the Store button); "Open now" brings it back |
| 69 | Admin tab: schedule from 1 minute from now for 2 minutes | Store opens at the start time and closes at the end time (within ~5 s), without anyone pressing anything |
| 70 | Non-admin (published game, another account) | No Admin tab; firing `AdminSetMode` from the console is rejected (`[Remote] rejected AdminSetMode … not an admin`) |

## Stairs and sprint
| # | Check | Expected |
|---|---|---|
| 71 | Walk from the spawn to the stairs (lobby, east side) and up | Open floor in front of the bottom step; you walk straight on and up to the upper corridor without getting stuck |
| 72 | Hold Shift while walking; release | Noticeably faster run with a slight camera zoom-out; back to normal speed on release; no `[MovementGuard]` lines in the server Output |
| 73 | Touch (Studio device emulator) / gamepad: tap Sprint or press L3, then move; stop | Button turns green and you run; about half a second after stopping, sprint switches off (button grey) |
| 74 | Sprint up to a boss and swing straight away | Hits land normally |

## Balance, boss labels, XP bar and the Admin panel (2026-10-06)
| # | Check | Expected |
|---|---|---|
| 75 | Stand in the corridor and in the lobby, look at the offices | Each boss's name/HP label shows only when you can see that boss (through the doorway); no labels piled up on the walls; upstairs labels don't show through the ceiling |
| 76 | Hit a boss while a second client hits one in another office | You don't see the other client's damage numbers through the wall |
| 77 | Look at the bottom of the screen | Thin blue XP bar under the hint: "Lv N  x / y XP to Lv N+1"; it fills after a defeat; doesn't cover buttons (also in the phone emulator) |
| 78 | Defeat the Deadline Boss solo with 0 XP | Score +105 (100 + 5 last-hit bonus); XP +126 (105 x 1.2), shown on the XP bar |
| 79 | Walk past each ground-floor office | HP bars read 100, 140, 240, 360, 560 |
| 80 | Studio (you're admin): Admin button above Store | Panel with Players / Bosses / Moderation tabs |
| 81 | Players: Set level 10 on yourself | Toast; HUD "Lv 10"; Senior bosses no longer say "reach Lv 10" (they still need their ground-floor defeat) |
| 82 | Players: Set damage 999, hit a boss to defeat | Every hit shows -999 (or the HP left); Victory Card says admin damage was on and gives no score/coins; "Normal" turns it off |
| 83 | Players: pick Senior Monday Monster, Unlock (on a level-1 test player) | That boss is hittable for them; "Reset admin unlocks" (click twice) locks it again |
| 84 | Bosses: create "Printer Jam" with look Deadline Boss, 300 HP, here in the lobby | Toast "Printer Jam created here..."; boss appears where you stood with that name and 300 HP; listed in the panel |
| 85 | Create another boss right next to the first one | Toast "Too close to another boss" |
| 86 | Defeat Printer Jam (deal 10 %+) | Victory Card "BONUS DROP: +N% ... boost (30 min), in your Bag!"; the boost is in the Bag, not active; it respawns after 5 s |
| 87 | Move here / Delete (click twice) | Boss moves to you / disappears; panel list updates |
| 88 | Stop and start the playtest (API access on) | Custom bosses come back where they were |
| 89 | Moderation: Ban in Studio | Toast "Ban failed (it only works in a published game)." |
| 90 | Published test place, second account: ban for 1 hour, then Unban | Second account is kicked and can't rejoin; after Unban it can |
| 91 | Non-admin account (published): fire `Remotes.Admin.SetLevel` from the console | Server log `[Remote] rejected Admin.SetLevel ... not an admin`; nothing changes |

## Bag and gifts (2026-10-06)
| # | Check | Expected |
|---|---|---|
| 92 | Existing save from before the Bag | Empty Bag; active boosts and owned Mystery Hammers unchanged |
| 93 | Use the last item of a kind | Row disappears; "Bag" button count goes down; pressing Use twice quickly uses only what you have |
| 94 | Store row for a boost | "Gift" button next to Buy; no Gift button on the Mystery Hammer |
| 95 | Gift: the friend list | Your Roblox friends, searchable by name; X closes it |
| 96 | Published test place, two accounts that are friends, both in the same server: A gifts a boost to B | A: "Gift sent to B: ..."; B: "Gift from A: ... It's in your Bag!" and it's in B's Bag; A's Bag unchanged |
| 97 | Same, but B is offline; B joins later | B gets the gift toast and the item within a few seconds of joining |
| 98 | Same, but B is in another server | B gets it within a few seconds (or at most 5 minutes) |
| 99 | Gift, cancel the prompt, then Buy the same boost | The bought boost goes to your own Bag, not to the friend |
| 100 | Fire `Remotes.Store.RequestGift` from the console with a non-friend's UserId, or with `mystery_hammer` | Rejected in the server log; no prompt |

## Respawn modes and boss buff drops (2026-10-07)
| # | Check | Expected |
|---|---|---|
| 101 | Admin panel, Bosses tab | New "Respawn" picker: Respawns / One time; existing custom bosses listed as "respawns" |
| 102 | Create a "One time" boss and defeat it | Rewards and buff drop as usual; it does **not** come back after 5 s; list shows "defeated"; server log `[CustomBoss] one-time boss ... defeated` |
| 103 | Stop and start the playtest (API access on) | The defeated one-time boss does not spawn; Delete removes it and frees the slot |
| 104 | Two servers, one-time boss: defeat it in server A while B is mid-fight | B can finish its fight; then it's gone in B too, and new servers never spawn it |
| 105 | Admin > Drops: set Normal Min and Max to 1, Save; defeat an office boss with 10 %+ | Victory Card "BONUS DROP ..."; boost in the Bag. Then Reset to defaults (click twice): fields go back to 0.0005 / 0.1 / 0.1 / 0.3 / 120 / 10 |
| 106 | Admin > Drops status line | "Normal chance now ... Next Lucky window in about N min" or "Lucky window is ON now ..." matching the UTC clock (on for the first 10 min of every even UTC hour) |
| 107 | Drops: Min above Max, a chance of 1.5, or Lasts >= Every; Save | Toast explaining the problem; nothing saved |
| 108 | Two servers: Save new rates in A | B's Drops tab shows them within seconds |
| 109 | Non-admin: fire `Remotes.Admin.SetDropRates` from the console | Server log `[Remote] rejected Admin.SetDropRates ... not an admin`; nothing changes |

## Character expressions (2026-10-07)
| # | Check | Expected |
|---|---|---|
| 110 | Spawn (R15 avatar), look at your face (zoom out, rotate camera) | Mood face as in 33; eyes have a small white shine; no angry brows at any stress |
| 111 | Swing at nothing | Determined face (level brows, grin) for the swing, then the mood face again; the hammer swings as before |
| 112 | Hit a boss | Determined while swinging, then Happy (^ ^ eyes, open smile, blush) for ~0.7 s, then the mood face; damage numbers, shake and rewards unchanged |
| 113 | Land the defeating hit | Happy for ~1.5 s; Victory Card as before |
| 114 | Second client watching you hit | Sees your Happy face on each landed hit; your mood face otherwise |
| 115 | Reset (Esc → Reset), then swing and hit again | New character: mood face appears, Determined / Happy work again; Output has no errors |
| 116 | Same with an R6 avatar (Game Settings → Avatar → R6, or a test place) | Faces sit on the head and behave the same |
| 117 | Avatar with an animated (dynamic) head | Drawn faces sit on top; the head's own face may show through a little (known, as before) |
| 118 | Rapid swings for 30 s | No lag or growing instance count: one `ActionFace` per head (Explorer, client view) |

## Hammer looks (2026-10-07)
For testing, use a test save with plenty of coins (or temporarily raise a boss's `CoinReward` in Studio and revert it).
| # | Check | Expected |
|---|---|---|
| 119 | Shop: scroll the list | 11 hammers (plus any Mystery Hammers), each with a recognisable 3D preview, head up |
| 120 | Equip each hammer in turn | Each looks distinct, sits in the right hand with the head past the fist (not floating, not pointing back at the shoulder), rests on the shoulder when idle |
| 121 | Swing each hammer at a boss | Head squashes and stretches with its bands / caps staying on it; trail in the hammer's colour; damage = that hammer's Damage × boss multiplier; cooldown unchanged |
| 122 | Neon, Fire, Lightning, Cosmic, Golden, Mystery | Only a small glow and a few particles; no flicker, no light flooding the office |
| 123 | Reset (Esc → Reset) with each of 2-3 hammers equipped | You respawn holding the same hammer, fully visible; still exactly one hammer (no duplicates in Backpack) |
| 124 | First person (zoom all the way in) and third person | Hammer visible and in hand in both |
| 125 | Second client watching | Sees your hammer's look, swing and trail; switching hammers updates for them |
| 126 | 30 s of rapid swings with Fire / Cosmic, 2+ players | No FPS drop (Ctrl+Shift+F5 / MicroProfiler); Output has no errors or warnings |

## Swing feel (2026-10-07)
| # | Check | Expected |
|---|---|---|
| 127 | Single click at a boss | Wind-up, brief coil at the top, fast strike, small bounce off the boss, smooth return to the shoulder; "bonk" + small shake on the hit |
| 128 | Click as fast as you can for 10 s | One swing after another, never restarting mid-swing or overlapping; damage numbers appear at most once per 0.45 s; server log has no cooldown rejections |
| 129 | Click once just before a swing ends | The next swing starts right as the first one finishes (no lost click); clicking earlier in the swing does nothing |
| 130 | Jump, walk and sprint while swinging | Swing plays the same; hammer stays in hand, head past the fist, not upside down; hits still register in reach |
| 131 | Reset mid-swing, then swing again | New character rests the hammer on the shoulder and swings normally; no errors in Output |
| 132 | Two clients hitting the same boss | Each sees the other's strike, bounce and return on confirmed hits; only your own hits make your camera shake and bonk |
| 133 | R6 avatar (test place) | Same beats; the wrist takes the elbow's part |

## Hit and glow effects (2026-10-07)
| # | Check | Expected |
|---|---|---|
| 134 | Hit a boss | Soft white flash on the monster, a few small golden/white sparkles, a tiny ring that grows and fades; nothing covers the screen |
| 135 | Crit, and the defeating hit | Crit: a few more, warmer sparkles. Defeat: a slightly bigger sparkle burst with pastel motes floating up; no explosion |
| 136 | 30 s of rapid hits on one boss | Explorer (client): the boss has exactly one `HitFx` attachment and its monster one `HitFlash`; no growing count of effects; FPS steady |
| 137 | 2-3 players hitting different bosses | Others' hits show a smaller burst and a faint ring; hits far away (other offices) show nothing |
| 138 | Defeat a boss and wait for the respawn | Old boss's effects go away with it; the new boss gets its own rig on its first hit |
| 139 | Reach Zen (0 stress) | Hammer has a soft warm glow and a few slow sparkles, not glitter; leaving Zen turns both off |
| 140 | Output after all of the above | No errors or warnings |

## Outdoor campus (2026-10-07)
| # | Check | Expected |
|---|---|---|
| 141 | Spawn | Lobby as before; the entrance in the middle of the glass front is straight ahead, sign above it |
| 142 | Walk out through the entrance | One small step down onto the plaza; nothing in the way |
| 143 | Walk the main walkway to the Stress-Relief Zone, then the cross walk to the Garden and the Coffee Corner, then the loop around the building | Every path is clear; signs point the way; nothing to get stuck on |
| 144 | Walk into the pond, bump into benches, tables, kiosk, trees | You walk across the pond; props block you like furniture but never trap you; no clipping into the ground |
| 145 | Walk / sprint / jump into the edges of the grounds | Stopped by an invisible wall at the hedge on every side; can't reach the street |
| 146 | Go back in: stairs (the "ladder") to the Senior floor, elevator to the CEO, the leaderboard on the lobby's west wall, the Store and Hammers buttons, every boss office | All work as before |
| 147 | Two players outside and inside | Both see the same campus; hits, swings and faces work anywhere |
| 148 | Performance outside (Ctrl+Shift+F5 / MicroProfiler), Output | Steady FPS; no errors or warnings |

## Boss personalities (2026-10-07)
| # | Check | Expected |
|---|---|---|
| 149 | Watch each of the 5 office bosses (and a Senior, the CEO) from the doorway | Each moves in its own style (hurry, pacing, jittery, head tilts, sleepy, pompous) and does its fidget every few seconds; stays on its spot |
| 150 | Stand far away / on another floor | Bosses look around instead of staring at you |
| 151 | Walk up to a boss | It hops in surprise, a "ping", and a short line in its bubble; walking away and back within 12 s doesn't repeat it |
| 152 | Walk up to a locked boss | "Not so fast! Come back later." (or similar) |
| 153 | Hit a boss repeatedly | Lean-back hop + dizzy wobble, a "boing" at most about every 0.7 s, sometimes "Ouch!"-style lines (not every hit); damage, HP, rewards unchanged |
| 154 | Two players hitting the same boss | Still at most one "boing" every 0.7 s; each player sees their own lines only; server shouts still appear for both |
| 155 | Defeat a boss, wait for the respawn | Lower "boing" with the spin; the new boss behaves normally |
| 156 | Reset your character near a boss | It notices you again when you come back (after its cooldown) |
| 157 | Output | No errors or warnings (in particular no "failed to load sound") |
| 158 | Explorer (client) during play | Each boss body has at most two `Boss...` Sounds; no growing count |

## Leaderboard (2026-10-07)
| # | Check | Expected |
|---|---|---|
| 159 | One player, Studio (API access off) | "Hall of Calm" board on the lobby's west wall, readable from the spawn; you at #1 with a gold row; note "This server only (global board offline)"; one warning at most in Output about the global board |
| 160 | Click Top Score / Top Level / Top Coins | Tab turns blue, the ranked column turns gold, rows re-sort; nothing changes for other players |
| 161 | Defeat a boss, wait up to a minute | Your Score / Level / Coins update; changed rows fade and slide in; "YOU: #1 on the board" follows your values |
| 162 | 2-3 players (local server test or published) | Top 3 get gold / silver / bronze; each sees their own "YOU" line |
| 163 | A player joins, then leaves | They appear within a few seconds of their data loading, and drop off the server-only board after leaving |
| 164 | Reset your character | Board stays as it was (no flicker, no duplicate) |
| 165 | Published place: play, leave, rejoin a new server | Your all-time Score rank is kept; Top Level / Top Coins include you after up to 2 minutes of play |
| 166 | Output (published) | No DataStore errors or warnings |

## Hammer vending machine (2026-10-07)
| # | Check | Expected |
|---|---|---|
| 167 | Spawn and look right (east) | "HAMMER STORE" machine beside the stairs: glass window with three hammers swaying gently, soft neon edges, screen "PRESS E for hammers", keypad, coin slot |
| 168 | Walk to the stairs and up them past the machine | Nothing in the way; the machine doesn't touch the stairs or the landing |
| 169 | Walk up to the machine | "Open Hammer Store" prompt (E) within ~8 studs |
| 170 | Press E | The Hammers panel opens (the same one as the button); soft click; screen shows "HAPPY WHACKING!" for a moment |
| 171 | Buy a hammer you can't afford | Button reads "Need N" and does nothing; coins unchanged |
| 172 | Buy one you can afford | Coins go down once, the hammer is equipped in hand and listed as owned; same as buying from the button |
| 173 | Rapid E presses, then rapid Buy clicks | Panel just stays open; bought once, coins deducted once |
| 174 | Two players use the machine at once | Each opens their own panel; purchases are separate |
| 175 | Reset your character, use the machine again | Works the same; the "Hammers" button still works too |
| 176 | Stop and Play again (server restart) | Machine is there and works |
| 177 | Output | No errors or warnings (in particular no "failed to load sound") |

## Lobby lounge NPCs (2026-10-07)
| # | Check | Expected |
|---|---|---|
| 178 | Spawn and look left (west) | Rita behind the reception desk, Ben and Mia on the west couch, Sam by the water cooler; all smiling, different colours; idle motion (looking around, reading, sipping) |
| 179 | Walk up to Rita | She waves and says hello in a bubble; walking away and back within 25 s doesn't repeat it |
| 180 | Stand near the couch for ~30 s | Now and then a line; Ben and Mia answer each other |
| 181 | Walk through the lounge, into the NPCs, to the leaderboard, the stairs, the vending machine, out the entrance | Nothing blocks you (you pass through the NPCs); the board stays fully visible |
| 182 | Swing your hammer at an NPC | Nothing happens (no hit, no stress, XP or coins) |
| 183 | Two players | Each sees the NPCs animate and gets their own greetings |
| 184 | Reset your character near an NPC | Greetings keep working after the respawn |
| 185 | Performance and Output | Steady FPS; no errors or warnings |

## Passive stress timer (2026-10-07)
Watch the Stress bar (top). "Hit" means a hit that lands (damage number appears).
| # | Check | Expected |
|---|---|---|
| 186 | Hit a boss, then wait 15 s | No passive rise during the 15 s |
| 187 | Keep waiting to 20 s | Stress +5 once, at about 20 s |
| 188 | Keep waiting to 35 s | +5 at about 25, 30 and 35 s |
| 189 | After a hit, walk / sprint / jump around for 60 s | Stress keeps rising every 5 s after the grace; moving never resets it |
| 190 | After a hit, stand still for 60 s | Same as 189 |
| 191 | During the rises, hit a boss | Stress drops by the hit's relief; no rise for the next 15 s; then +5 every 5 s again |
| 192 | Swing at nothing / out of reach / at a locked boss, click fast | No reset: the rises carry on on schedule |
| 193 | Hit a boss several times in a row, then stop | One grace period from the LAST hit; rises every 5 s, never two at once |
| 194 | Two players: A keeps hitting, B walks around | A's stress doesn't rise; B's does; neither affects the other |
| 195 | Let stress reach 100 | Stays at "Stress 100 / 100", never above |
| 196 | Reset your character during the rises | Stress keeps its value and the same schedule (no extra or faster rises) |
| 197 | Open the Store / Hammers / Bag panels for 30 s | Stress still rises |
| 198 | Leave and rejoin (published or API access on) | Saved stress loads as before; a new 15 s grace starts on join |
| 199 | Output | No errors |

## Admin Panel and Player Panel (2026-10-07)
| # | Check | Expected |
|---|---|---|
| 200 | Press M, or click Menu (top-left) | Player Panel scales in quickly: header with title and X, sidebar Profile / Hammers / Game / Help, Profile selected |
| 201 | Profile | Level, XP, Score, Coins, Stress, Zen tiles match the HUD; hit a boss with the panel open: values update, no flicker |
| 202 | Hammers: Equip another hammer | The hammer in hand changes; the list shows it as "Equipped" (disabled); Shop button opens the Hammers panel |
| 203 | Game: each shortcut | Player Panel closes and the Hammer Shop / Store / Bag opens; Admin Panel shortcut only for admins |
| 204 | Help: open / fold "Controls" and "Settings" | Cards fold and unfold; text wraps, never cut off |
| 205 | Press M again / click X | Panel scales out and hides |
| 206 | Admin: click Admin or press F2 | Admin Panel opens on Dashboard: server tiles, game tiles, player list |
| 207 | Dashboard: Manage / Moderate on a player | Opens Players / Moderation with that player selected |
| 208 | Every Admin tab: run each action once (set level, damage, unlock, create / move / delete a custom boss, drop rates, ban in Studio) | Same results and toasts as before the redesign |
| 209 | Scroll a long page, then trigger a server update (e.g. set damage) | Page redraws without jumping back to the top |
| 210 | Non-admin account | No Admin button; F2 does nothing; firing an Admin remote from the console is rejected in the server log |
| 211 | Resize the Studio window / Device emulator: 1920x1080, 1600x900, 1366x768, a small window, a phone (landscape) and a tablet | Windows fit on screen; on narrow screens the sidebar becomes a top tab strip; nothing overlaps or is cut off; everything reachable by scrolling; buttons stay at least 44 px tall |
| 212 | Reset your character with a panel open | Panel stays usable; reopening works; no duplicate panels or buttons |
| 213 | Two players | Each has their own panels; admin tools only for admins |
| 214 | Output | No errors or infinite-yield warnings |

## Responsive UI, announcements, bundles, Mystery Hammer, events (2026-10-08)
Unit specs first: open `build/tests.rbxl` in Studio and press Run (F8). New and changed specs:
`Client/Responsive`, `Shared/AnnouncementRules`, `Shared/EventRules`, `Shared/BagRules`,
`Shared/HammerRules`, `Server/PlayerDataSchema` (v7), `Server/RewardRules`, `Config/StoreConfig`,
`Config/HammerConfig`.

### Responsive UI (docs/UI.md)
| # | Check | Expected |
|---|---|---|
| 215 | Device emulator: 1920x1080, 1600x900, 1366x768 | Hammers / Store / Bag / Admin buttons bottom-right as before; HUD unchanged |
| 216 | Small desktop window (about 800x450) | Popups fill most of the window; Admin / Player panels use the top tab strip and a slim header; nothing off screen |
| 217 | Tablet landscape and portrait | Button column top-right (below the score lines in portrait), clear of the jump button; Sprint left of the jump button |
| 218 | Phone landscape (e.g. iPhone 14) | Button column top-right, 4 buttons above the jump button; Sprint next to jump; Victory Card readable; hint fades after 20 s |
| 219 | Phone portrait | Column starts under the score / boost lines; popups 96 % wide; Store tabs scroll sideways |
| 220 | Every popup and panel on a phone: Store (each tab), Hammers, Bag, Player Panel (each tab), Admin (each tab) | No text bigger than its row, no clipped buttons ("Moderate", "Remove unlock" fit), long notes wrap and grow, everything reachable by scrolling |
| 221 | Rotate the emulated phone with a panel open | Layout follows within a moment; nothing duplicated |

### Announcements
| # | Check | Expected |
|---|---|---|
| 222 | Admin → Announce: "Welcome to Whack It Out!", 10 sec, SEND (2 players) | Both see "📢 ANNOUNCEMENT" top-centre; it closes after 10 s or on OK; admin gets a toast; server log `[Admin] … announced` |
| 223 | Send again within 10 s | Toast "Wait N s…"; nothing shown to players |
| 224 | 200-character message; then 201 characters | First shows (wrapped, card grows); second refused with a toast |
| 225 | Message with line breaks, `<b>bold</b>` and extra spaces | One line, tags shown as typed, spaces collapsed |
| 226 | Non-admin (in Studio set `StoreAdminConfig.StudioTesterIsAdmin = false` first: Studio testers are admins otherwise), client command bar: `game.ReplicatedStorage.Remotes.Admin.Announce:FireServer("hi", 10)` | Nothing shown; server log `[Remote] rejected Admin.Announce … not an admin` |
| 227 | Phone emulator | Card fits the width, text readable, OK tappable |

### Bundles (needs Developer Products created and their ids in `StoreConfig`)
| # | Check | Expected |
|---|---|---|
| 228 | Before ids are set | Store → Bundles says "Coming soon." |
| 229 | Buy Beginner Bundle (Studio test purchase) | Toast "Beginner Bundle: 9 boosts added to your Bag"; Bag shows 3 each of +10 % XP, +5 % Damage, +5 % Crit Damage (30 min) |
| 230 | Buy it again | Bag counts become 6 each; nothing else changes |
| 231 | Use one 5-hour boost from a Stress Reliever Package, then another of the same kind | First runs 5 h; the second adds 5 h (existing rule); the others stay in the Bag |
| 232 | Leave and rejoin after buying | Bag contents are still there |
| 233 | Cancel the purchase prompt | Nothing granted |

### Mystery Hammer
| # | Check | Expected |
|---|---|---|
| 234 | Store → Mystery tab | Odds: base damage 35 always, bonus damage +15-25 % (1 in 11 each), crit +5-10 % |
| 235 | Open a Mystery Hammer from the Bag | Toast "35 damage, +N% damage, +M% crit damage"; 15 ≤ N ≤ 25, 5 ≤ M ≤ 10; equipped |
| 236 | Equip another hammer and back, reset, rejoin | Same N and M every time (Hammers panel, Player Panel) |
| 237 | Hit the Deadline Boss with no boosts | Normal hits = round(35 × (1 + N/100)); crits bigger by the base +50 % plus M % |
| 238 | Data from before (Studio: a v6 profile with `MysteryHammers = { mystery_1 = { Damage = 22, CritDamagePercent = 9 } }`) | Loads as 35 damage, +15 % damage, +9 % crit; still equipped |

### Events (docs/EVENTS.md)
| # | Check | Expected |
|---|---|---|
| 239 | Admin → Events: 2x XP, Start now, 30 minutes | All players get "🎉 EVENT STARTED! 2X EXPERIENCE"; the "🎉 1 EVENT" chip appears; Player Panel → Events shows it with a ticking countdown |
| 240 | Beat a boss during 2x XP | XP gained is twice what it is without the event (with the same boosts); score and coins unchanged |
| 241 | Add a 3x XP event too | XP is 3x, not 6x |
| 242 | Outdoor Boss Event: Production Bug, Garden Path, 3 | Three "🎉 Production Bug (Event)" bosses on the garden cross walk; normal HP, hits, crits, stress, rewards; they respawn after defeat; office bosses unchanged |
| 243 | Stop that event | Its bosses vanish at once (office and custom bosses stay); "EVENT ENDED" notice |
| 244 | Boss Drop Event: all bosses, Beginner Bundle, 100 % | Every qualifying player gets "EVENT DROP: Beginner Bundle, in your Bag!" and 9 boosts; a player under 10 % damage gets nothing; one drop per defeat |
| 245 | Drop event for one boss | Only that boss (and its outdoor event copies) drops |
| 246 | Hammer Shop Sale 20 %, all hammers | Shop shows "Buy 80 (-20%)" for a 100-coin hammer; buying charges 80 |
| 247 | Sale on selected hammers | Only those show the sale price |
| 248 | Let a sale end with the shop open, then click an old sale price | Purchase refused (no coins taken); the shop redraws with full prices |
| 249 | Schedule an event 2 minutes ahead for 2 minutes | Listed as SCHEDULED, starts and ends on its own with notices; moves to history |
| 250 | Two servers (published game) | An event created in one starts in the other within seconds |
| 251 | Restart a server during an event | The event is still running after the restart (no "started" notice for it) |
| 252 | Non-admin (`StudioTesterIsAdmin = false` in Studio) fires `Remotes.Admin.Events:FireServer({ Action = "Create", Type = "XpBoost", DurationSeconds = 1800, Config = { Multiplier = 5 } })` | Rejected and logged; no event |
| 253 | Admin sends bad values (Multiplier 10, chance 500, discount 100, end before start) | Refused with a toast; nothing saved |
| 254 | Studio without API access | Toast "Saved for this server only"; the event works in that server |
| 255 | Output during all of the above | No errors or infinite-yield warnings |

## Pets, eggs and incubators (2026-10-08, docs/PETS.md)
Specs first (Studio, `build/tests.rbxl`, F8): `Shared/PetRules`, `Config/PetConfig`,
`Server/IncubatorBuilder`, `Client/PetVisual`, `Server/PlayerDataSchema` (v8), `Config/StoreConfig`,
`Shared/BagRules`.

| # | Check | Expected |
|---|---|---|
| 256 | Walk out to the lawn east of the Front Plaza | Six incubators under the "🐾 PET INCUBATION CENTER" sign; each shows "🥚 INCUBATOR n / Empty"; nothing blocks the walkway |
| 257 | Admin → Events → World eggs: spawn a Common, then a Rare egg; walk to each spawn spot (markers in Workspace.PetCenter.OutdoorEggSpawnPoints) | "🥚 NEW EGG FOUND!" card for everyone (no location); the egg floats clearly above the walkway (never sunk into it) with a white outline, sparkles and a 🥚 marker within ~60 studs; it bobs gently |
| 258 | Two players press Claim Egg at the same moment | One gets "You found a Rare Egg!" and the egg in their Bag; the other only sees "<name> found the Rare Egg!"; the egg is gone |
| 259 | With one kind of egg, press E at an incubator | Egg appears in the pod; display "🥚 RARE EGG / Incubating... 01:00" counting down with a bar and "Owner: <you>"; toast says it keeps going |
| 260 | Walk far away, open menus, reset your character | Countdown keeps going (Player Panel → Pets shows the same time); never resets |
| 261 | Wait for 00:00 | Egg shakes, sparkles pop, the pet appears in the pod; "✨ EGG HATCHED! Your 🐰 Rabbit is ready!" with its buffs; a first pet is equipped automatically and starts following; the incubator frees after ~5 s |
| 262 | Another player tries the busy incubator | No prompt is offered on it |
| 263 | Hold two kinds of egg, press E | A picker asks which egg; Cancel closes it |
| 264 | Bag → Incubate, standing far from the incubators | Toast pointing to the Pet Incubation Center; the egg stays in the Bag |
| 265 | Start an egg, leave at 00:30, rejoin 10 s later | The egg is back in an incubator with ~00:20 left, not 01:00 |
| 266 | Start an egg, leave, rejoin after 2 minutes | It hatches immediately on join (card shown), exactly one new pet |
| 267 | Player Panel → 🐾 Pets with several pets | Equipped pet first with "✓ EQUIPPED"; EQUIP another: the old one stays listed, the new one follows |
| 268 | Tap ✓ EQUIPPED | Pet goes away; no pet buffs |
| 269 | Note a Rare pet's random buff; equip, unequip, reset, rejoin | The buff never changes |
| 270 | Hit the Deadline Boss with a +6 % Damage pet and nothing else (Squeaky Hammer) | Non-crit hits 11 (10 × 1.06 rounds to 11); with a Monkey (+10 % crit damage) crits are 10 × 1.6 = 16 |
| 271 | Defeat a boss with a +6 % XP pet | XP gained is 1.06x what it is without the pet (same boosts); with a 2x XP event too, ×2 on top |
| 272 | Two players: A equips a Dog, B a Dragon | Each pet follows its owner on both screens; A's buffs don't change when B's pet is near |
| 273 | Walk through doors, stand next to a boss, a store machine, NPCs, an incubator | The pet never blocks, pushes or gets hit; boss hits work as before |
| 274 | Store → Eggs (once products exist; Studio test purchases) | Odds shown; buying puts the egg in the Bag; a restricted account (PolicyService) sees no Eggs tab |
| 275 | Boss Drop Event with Common Egg at 100 % | Qualifying players get "EVENT DROP: Common Egg, in your Bag!" |
| 276 | Mobile emulator: Pets tab, egg picker, hatch card, incubator display | Readable, buttons tappable, nothing off screen |
| 277 | Non-admin fires `Remotes.Admin.SpawnEgg:FireServer("Mythical")`; anyone fires `Remotes.Pets.Equip:FireServer("pet_999")` and `Remotes.Pets.Incubate:FireServer("egg_mythical", 1)` without owning one | Rejected or ignored; no egg, no pet, nothing equipped |
| 278 | Leave the game with a pet out | Its model disappears for everyone; no errors |
| 279 | Output during all of the above | No errors, infinite-yield warnings or duplicate pets |

## Pet looks and movement (2026-10-08, docs/PETS.md "Looks and movement")
Specs first: `Client/PetMotion`, `Client/PetVisual`, `Config/PetConfig`.

| # | Check | Expected |
|---|---|---|
| 280 | Equip a Dog and stand still | Beside and behind you, breathing; every few seconds it looks around or at you; after ~6 s it may sit; tail wags; one Dog only |
| 281 | Walk, then sprint, then stop | Legs step in time with the ground (no sliding), faster strides when sprinting; it stops near you and settles facing your way |
| 282 | Walk in circles and turn around sharply | The pet turns smoothly toward where it goes; never walks sideways or backwards, never spins or jitters |
| 283 | Outdoors: grass, paths, the steps down from the lobby, a slope | Feet on the ground everywhere: no floating, sinking or falling |
| 284 | Rabbit, then Beetle/Ladybug | Rabbit moves in hops with ears back; bugs scuttle on six legs with antennae swaying |
| 285 | Butterfly, then Dragon, then Phoenix | Fly beside you at their height with a gentle bob, bank into turns; Butterfly flutters lightly and drifts a little; Dragon beats slowly and swings its tail; Phoenix fans its tail feathers; they hover when you stop |
| 286 | Hit a boss with a pet out | The pet gives a short happy reaction; boss damage is the same as without the reaction (only its buff counts) |
| 287 | Glitter: Common, Rare and Mythical pets side by side | A few tiny sparkles on each, a little more for rarer ones; never covering the pet, no glow or flashes |
| 288 | Ride the Executive Elevator / reset / respawn | The pet reappears beside you; still one pet, no leftover models or sparkles in Workspace.ClientPets |
| 289 | Equip another pet, then put it away | The old model disappears at once; nothing left in Workspace.ClientPets afterwards |
| 290 | 2 players: A with a Dog, B with a Dragon | Each follows its own owner on both screens |
| 291 | Team test with 5-10 clients, all with pets, near each other | Smooth movement; check the MicroProfiler / Stats: no big frame time from pets (one Heartbeat, one BulkMoveTo); far pets update less |
| 292 | Phone emulator | Pets still animate; glitter is sparser |
| 293 | Output | No errors or warnings from PetController / PetVisual / PetMotion |

## Level bonuses and office doors (2026-10-08, docs/GAMEPLAY_RULES.md)
Specs first: `Shared/LevelRules`, `Shared/CombatRules`, `Client/OfficeDoors`.

| # | Check | Expected |
|---|---|---|
| 294 | New Level 1 player: Player Panel → Profile | Base damage = hammer damage (Squeaky 10); Crit chance 5.00 %; level bonus +0 |
| 295 | Admin → Players → Set level 2, then 3 | Card "🎉 LEVEL UP! Level 1 → Level 2 / +3 Base Damage +0.05% Crit", then another; Profile shows 13 / 5.05 %, then 16 / 5.10 % |
| 296 | Set level 13 from 10 in one step | One card: "Level 10 → Level 13 / +9 Base Damage +0.15% Crit" |
| 297 | Hit the Deadline Boss at Level 10 with the Squeaky Hammer, no boosts | Normal hits 37 (10 + 27) |
| 298 | Leave and rejoin; reset your character | Same Base damage and Crit chance; no level-up card |
| 299 | Level 10 with a Mystery Hammer (+20 %), a +6 % Damage pet and a +5 % Damage boost | Normal hit on the Deadline Boss = round((35 + 27) × 1.31) = 81; let the boost run out: round(62 × 1.26) = 78; level part unchanged |
| 300 | 2x XP event | XP from defeats doubles; Base damage and Crit chance don't change until a real level-up |
| 301 | New Level 1 player walks the corridors | Deadline Boss door open "✓ AVAILABLE"; the other ground offices closed "🔒 Beat … x1"; Senior offices closed "🔒 Requires Level 10" |
| 302 | Walk into a closed door | Can't pass it |
| 303 | Beat the Deadline Boss | Meeting Master's door slides open within a moment; no rejoin |
| 304 | Two players: Level 1 and Level 12 (with the ground bosses beaten) | Each sees their own doors; the Level 1 player's Senior doors stay closed while the other walks in |
| 305 | Exploit: delete your door in the client Explorer and walk in to a locked boss | Hits do nothing; Studio Output "[Combat] hit … is locked for this player" |
| 306 | Admin removes your admin unlock while you stand inside that office | Door stays open until you walk out, then closes |
| 307 | Respawn; rejoin | Doors show the same states; no duplicate doors in Workspace.ClientDoors |
| 308 | Output | No errors from OfficeDoorController / LevelUpController |

## GUI, stress, admin rewards and history, bypass, events, pets (2026-10-08, second pass)
Specs first: `Shared/StressRules`, `Shared/EventRules`, `Shared/PetRules`, `Client/Responsive`.

| # | Check | Expected |
|---|---|---|
| 309 | Desktop 1920x1080 / 1366x768 | Top-left ☰ Menu with 🎵 Music beside it; bottom-right column 🛡️ Admin (admins), 🎒 Bag, 🛒 Store, 🔨 Hammers, each icon + label; all work as before |
| 310 | Phone landscape and portrait | Same buttons as compact icon tiles with tiny captions, clear of the jump button and the HUD lines; panel text noticeably smaller than before but readable; nothing clipped; tabs scroll |
| 311 | Mute music | Button shows 🔇 Muted; unmute shows 🎵 Music |
| 312 | Hit the Deadline Boss from 100 stress with the Squeaky Hammer, no boosts | About 1 stress per hit (~100 hits to Zen) |
| 313 | Same with a Mystery Hammer at a high level with Damage boost and pet; land crits | Never more than 2.5 per hit; crits relieve the same as normal hits |
| 314 | Two players hitting the same boss | Each loses stress at their own hammer's rate |
| 315 | Admin → Players → Turn bypass ON (Level 1 admin) | Every office door opens; Senior bosses and the CEO (elevator) can be hit; Profile unchanged; OFF closes them again (after you leave the office) |
| 316 | Non-admin fires `Remotes.Admin.Bypass:FireServer(true)` (`StudioTesterIsAdmin = false` in Studio) | Rejected and logged; doors stay closed; hits on locked bosses do nothing |
| 317 | Admin → Rewards: 500 coins, 10,000 XP, 2 Rare Eggs, a hammer, a Dragon to another player, reason "Event compensation" | Confirm dialog each time; the target gets each with a toast; Coins/XP/Bag/Hammers/Pets update at once |
| 318 | Reward a hammer the player already owns | Toast "already owns…"; History shows the entry as FAILED |
| 319 | Non-admin fires `Remotes.Admin.Reward:FireServer({ UserId = <own id>, Kind = "Coins", Amount = 99999 })` | Rejected and logged; no coins |
| 320 | Admin → History → that player → LOAD | The rewards (admin, target, amount, reason, status), purchases, boosts used, eggs, pets, with dates; filters and pages work |
| 321 | Admin → History → Admin log → Today | Every admin action of today (rewards, events, bypass, set level...) |
| 322 | Rejoin / restart the server, LOAD again (published game) | The same entries (saved within ~30 s) |
| 323 | Create an XP event, then Edit it (change the multiplier), SAVE CHANGES | The running event changes; history later shows its planned and actual end |
| 324 | Schedule an event, then Start now | It starts at once with the "EVENT STARTED" notice |
| 325 | Outdoor Boss Event running → Stop → [Cancel] | Nothing happens |
| 326 | … → Stop → [Confirm] | Bosses vanish at once, "EVENT ENDED"; history status Stopped, by you, at that time |
| 327 | Another event → Force remove → Confirm | Same, status Removed; in a server whose DataStore fails it still ends there with a "retry" toast |
| 328 | Egg Hunt: Rare, every 2 min, up to 3, start now for 30 min | "EVENT STARTED Rare Egg Hunt"; a Rare egg appears at once and every 2 min, at most 3 unclaimed; one claim each |
| 329 | Schedule a Mythical Egg Hunt 3 minutes ahead | It starts on time on its own; Mythical eggs appear |
| 330 | Stop the hunt with eggs still out | Its unclaimed eggs vanish; normal 2-hour eggs (if any) stay |
| 331 | Delete an entry in Event history | Gone after Confirm |
| 332 | Player Panel → 🐾 Pets with several pets | Pet details card (name, rarity colour, type, buffs, status) and a card grid; tap a card: details switch; hover on desktop previews |
| 333 | EQUIP PET / UNEQUIP PET in the details card | Pet appears / disappears at once; owned list unchanged; damage and XP bonuses follow (only the equipped pet's) |
| 334 | Equip, respawn, rejoin, switch pets several times; hit a boss | Damage the same every time for the same pet (no stacked buffs) |
| 335 | Output | No errors from AdminController, AdminService, HistoryService, EventService, PetService |

## GUI foundation: settings, reduced motion, gamepad (2026-10-09, major update Phase 1)
Specs first: `Client/UiTokens`, `Client/GamepadNav`, `Client/PanelKit`, `Shared/SettingsRules`,
`Config/SettingsConfig`, `Server/PlayerDataSchema` (v9). For the gamepad rows, plug in a controller
(or use Studio's controller emulator).

| # | Check | Expected |
|---|---|---|
| 336 | Open every panel (Player Panel pages, Admin Panel, Hammer Shop, Store, Bag) on desktop and phone | Looks exactly as before: same colours, fonts, sizes and corners |
| 337 | Player Panel → Profile | A blue "Lv N → Lv N+1" bar under the stat tiles, filled to your XP progress; it moves when you earn XP |
| 338 | Player Panel → Settings | "Comfort" card with **Reduced motion** (Off) and its description; "Sound" card (music switch, or "no background music yet") |
| 339 | Turn Reduced motion On, then open/close the Player Panel, get a notification card, hit a boss, sprint | Panel and card appear and vanish with no zoom; no camera shake on hits; no zoom-out while sprinting; the Stress bar jumps instead of easing |
| 340 | Rejoin (API access on) or a second server | Reduced motion is still On; turn it Off again: everything animates as before |
| 341 | Help page | Controls list "Y for this menu, B to close a panel"; a line points to the Settings page |
| 342 | Pets page with no pets; Events page with no events | 📭 cards with the same sentences as before |
| 343 | Hover the ☰ Menu button (desktop); long-press it (phone) | Tooltip "Menu (M, or Y on a controller)"; on phone it hides after ~2 s |
| 344 | Controller: press Y | Player Panel opens with a tab selected (not the X); D-pad moves; A presses; switching tabs keeps a selection |
| 345 | Controller: Settings page → A on Reduced motion | It flips On/Off and the selection stays on the switch |
| 346 | Controller: open the Hammer Shop, Store, Bag (via Player Panel → Game) | The first control (not Close) is selected; B closes the panel |
| 347 | Controller: Admin Panel → an action with a confirm (e.g. Stop event) | **Cancel** is selected first; B cancels; Confirm still works |
| 348 | Mouse and touch players | Never see a selection highlight |
| 349 | Command bar / exploit: `Remotes.Settings.Set:FireServer("ReducedMotion", "yes")`, `("Coins", true)`, 20 times in a row | Rejected and logged (at most once per 5 s); nothing saved; rate limit holds |
| 350 | Output | No errors from PanelKit, GamepadNav, SettingsController, SettingsService, PlayerPanelController |

## Levelling rework (2026-10-09, docs/GAMEPLAY_RULES.md "Player Level", "Level rewards")
Specs first: `Shared/LevelRules`, `Shared/LevelRewardRules`, `Config/LevelRewardConfig`,
`Shared/ProgressionRules`, `Server/PlayerDataSchema` (v10). Admin → Players → Set level helps reach
levels quickly (it pays no coins, by design).

| # | Check | Expected |
|---|---|---|
| 351 | New player: head tag; Player Panel → Profile | "Lv 1 · Intern"; Level tile "Lv 1 · Intern" with a level bar |
| 352 | Earn your way past Lv 2 (beat the Deadline Boss a few times) | Card "🎉 LEVEL UP! Level 1 → Level 2 / +3 Base Damage +0.05% Crit +40 coins / Next at Lv 5: Title: Junior Associate"; coins go up by 40 |
| 353 | Reach Lv 5 by earning XP | Card says "Unlocked: Title: Junior Associate"; head tag updates |
| 354 | Admin Set level 9, then earn to Lv 10 | Only Lv 10's coins (200) are paid; card: "Unlocked: Title: Associate, The Senior floor upstairs" |
| 355 | Admin Set level 14, then earn to 15; Player Panel → 🏅 Levels | Card lists "Mint Trail, Fire Hammer in the Hammer Shop"; Levels page: next reward, Mint Trail selectable, others "🔒 Lv …"; the reward track shows ✓ up to 15 |
| 356 | Pick Mint Trail; swing | The swing trail is mint; another player sees it too |
| 357 | Admin Set level 25, pick Ocean Glow, reach Zen | The hammer's Zen light and sparkles are blue; Default puts the gold back |
| 358 | Admin Set level 10 (below your picks) | Trail and glow show the default look; set level 25 again: your picks come back |
| 359 | Hammer Shop at Lv 14 | Fire Hammer shows "🔒 Lv 15", can't be bought; at Lv 15 it shows "Buy 2500" |
| 360 | Exploit: `Remotes.Shop.BuyHammer:FireServer("stress_crusher")` at Lv 20 with 8,000+ coins | Nothing bought, no coins taken |
| 361 | Exploit: `Remotes.Level.SetCosmetic:FireServer("Trail", "prism")` at Lv 20; `("Hat", "x")`; 20 calls in a row | Prism refused (still default); bad kind rejected and logged; rate limit holds |
| 362 | Admin Set level 100 | Head tag "👑 Lv 100 · Chief Calm Officer" in gold; XP bar "Lv 100 MAX LEVEL n XP" and full; Levels page "Max level reached"; no coins paid |
| 363 | At Lv 100, beat bosses | XP keeps counting (Top Level board), level stays 100, no level-up card |
| 364 | Admin panel → Set level field | Says 1 to 100; 101 is refused |
| 365 | Data (API access on, test place): a v9 profile at old Lv 50 (XP 1,440,600) joins | Still Lv 50 (XP raised to 8,427,000), coins unchanged, no level-up card; a Lv 8 profile keeps its XP exactly |
| 366 | Output | No errors from SessionService, LevelRewardService, MoodService, HammerService, LevelUpController, PlayerPanelController |
## Personal offices (2026-10-09, major update Phase 2a, docs/OFFICES.md)
Specs first: `Config/FurnitureConfig`, `Config/OfficeConfig`, `Shared/FurnitureRules`,
`Shared/FurnitureModel`, `Server/OfficeWingBuilder`, `Server/PlayerDataSchema` (v11). Set **Max
Players** (Game Settings) before testing; use **Test → Clients and Servers** with 2-3 players for the
visiting rows.

| # | Check | Expected |
|---|---|---|
| 367 | Join; HUD column | A 🏢 **Social** button at the end of the column (all screen sizes, clear of the jump button) |
| 368 | 🏢 Social → **Go to my office** | You stand inside the door of a 40 × 40 room with your name over the door, a long window, a soft light; a Computer Desk, chair and small plant are already there; the bar says "🏢 Your office" with ✏️ Edit / 🚪 Lobby |
| 369 | ✏️ Edit | The furniture strip appears, your hammer is put away; clicking never swings |
| 370 | Pick Sofa; move the mouse over the floor | A see-through sofa follows, snapping to whole studs; green on free floor, red near a wall, in the doorway or over the desk, with the reason in the hint |
| 371 | R / ⟳ Turn, then click (or ✓ Place) on green floor | The sofa turns, then appears for real; the strip stays on Sofa so you can place another |
| 372 | Place a Round Rug under the sofa; then another rug on top of it | The first is allowed; the second is red ("That overlaps the Round Rug.") |
| 373 | Click a placed item → ✥ Move, put it elsewhere; select it → R; → 🗑 Remove (or Delete) | It moves, turns in place, disappears; the count "n / 60 items" follows |
| 374 | ✓ Done; rejoin (API access on) | Your hammer is back; after rejoining the office looks exactly the same |
| 375 | Trophies tab with none owned | "Trophies come from rewards and events." / cards show "0 left", disabled |
| 376 | Admin → Rewards → Special office furniture → Golden Hammer Trophy ×2 to yourself | Toast; Trophies tab shows "2 left"; you can place 2, not a third |
| 377 | Fill the room to 60 items (or note the count stops you) | The 61st is refused: "Your office is full (60 items)." |
| 378 | Phone: Edit, tap the floor, ✓ Place; tap a placed item → Move / Remove | Works with taps; ✓ Done gives you the thumbstick back |
| 379 | Controller: Edit, aim with the camera, X to place, LB/RB to turn, X on furniture to select, B to cancel then leave | All work; the panel selection starts on a category tab, never ✓ Done |
| 380 | Player 2: 🏢 Social → Offices in this server | Player 1's office listed with avatar, name, "Anyone can visit", **Visit** |
| 381 | Player 2 → Visit | Player 2 arrives in player 1's office; their bar says "🏢 <Name>'s office" with only 🚪 Lobby (no Edit) |
| 382 | Player 1 sets **Private** while player 2 is inside | Within ~1 s player 2 is sent to the lobby with "That office is closed to visitors now."; the list shows "🔒 Private", Visit disabled |
| 383 | Player 1 sets **Friends**; player 2 (not a friend) presses Visit (Studio test players aren't friends) | Toast "…'s office is for friends only."; stays where they were |
| 384 | Player 2 in player 1's (Public) office; player 1 leaves the server | Player 2 is sent to the lobby within ~1 s; the room shows "Vacant Office" |
| 385 | Door prompt (E) inside any office; 🚪 Lobby; respawn while in an office | Each returns you to the lobby; no "[MovementGuard]" warnings, hits on bosses work right away |
| 386 | Exploit / command bar as a visitor in someone's office: `Remotes.Office.Place:FireServer("sofa", 0, 0, 0)`; as owner: `("sofa", 0.5, 0, 0)`, `("sofa", 999, 0, 0)`, `("sofa", 0, 0, 45)`, `("rocket", 0, 0, 0)`, `RemoveItem:FireServer("x")`, `Go:FireServer(-1)`, 30 Place calls in a row | Visitor: "Go to your office…" toast, nothing changes; the others rejected and logged (at most once per 5 s); rate limit holds; the room never changes |
| 387 | Data: an existing (v10) profile joins | Loads with the starting desk, chair and plant, Public; coins, hammers, pets, settings unchanged |
| 388 | Output | No errors from OfficeService, OfficeController, PlayerPanelController, FurnitureModel |
| 389 | Admin Set level 30; Edit → Level rewards tab | Executive Desk and Aquarium show "Free"; Zen Fountain and the statue "🔒 Lv 50" / "🔒 Lv 100", disabled; placing a locked one is refused ("Reach Level 50 to place the Zen Fountain.") |
| 390 | Place an Aquarium, then Admin Set level 1, rejoin | The aquarium is still there and can be moved; a new one can't be placed |
| 391 | Admin Set level 40; 🏅 Levels → Office theme → Garden Office | Your room's walls go green and the carpet dark green at once; a visitor sees it; Default restores the slate look |
| 392 | Exploit: `Remotes.Level.SetCosmetic:FireServer("Office", "royal_gold")` at Lv 40 | Ignored (still Garden); nothing logged as an error |
