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
