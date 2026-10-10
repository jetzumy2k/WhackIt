# Major Update: Implementation Plan

_Written 2026-10-09 (Phase 0). Sources: `docs/MAJOR_GAME_UPDATE.md` (owner decisions in §21),
`docs/UPDATE_ARCHITECTURE_AUDIT.md`. Values marked (P) are provisional and go into config modules._

## 1. Phase order (proposed change)

The spec's order runs Quests/Furniture/Career (2) before the Tower (3) and Recreation (4). Pickleball
rewards are office supplies (§21.2), so furniture has to exist first. Quests and career don't depend
on pickleball. This plan splits Phase 2 and moves Recreation forward:

| Step | Phase | Why here |
|---|---|---|
| 0 | Audit and baseline (this document) | done when the gate in §8 passes |
| 1 | GUI foundation | settings, gamepad navigation, shared confirm/tooltip/progress pieces; every later panel needs them |
| 2a | Furniture, personal offices, Office Directory | the owner's top request; pickleball's office-supply prizes need it |
| 4 | Recreation Center: pickleball Singles + Doubles, rating, seasons | the owner's second request |
| 2b | Quests and career | uses offices (furniture rewards) and pickleball ("finish a match" objectives) |
| 5 | Daily events and co-op missions | event objectives need quests |
| 3 | Tower expansion | the biggest map rework and the least gameplay value; best done once the destinations it connects exist |
| 6 | Showcase, contests, sharing | needs offices to have been in use for a while |
| 7 | Integration and release | — |

**D1 accepted by the owner (2026-10-09):** this order is the plan.

## 2. Decisions needed before the phase they block

| Id | Question | Recommendation (✅ = accepted 2026-10-09) | Blocks |
|---|---|---|---|
| D1 | Phase order | ✅ as in §1 | 1 |
| D2 | Server size (`MaxPlayers`, Game Settings) | ✅ 12. Set it in Game Settings before Phase 2a. Office slots and court count scale with it. | 2a |
| D3 | Where the Recreation Center stands | ✅ **Move the campus north boundary from z -130 to z -210** and build the center behind the office (x -60..60, z -140..-200). It's walkable from campus, so other players can see matches. The other option is a teleport-only area like the offices, which is cheaper but hides the matches. | 4 |
| D4 | Doubles rewards | ✅ (2026-10-10) 60 / 20 coins **per player** (as in §21.2). Total coin output is twice the singles rate, which is acceptable because the daily caps limit it. | 4 |
| D5 | Rating start and formula | ✅ (2026-10-10) Elo, start 1000, K = 32 (P). In doubles each player's change uses the team average. | 4 |
| D6 | Season length | ✅ (2026-10-10) 4 weeks starting Monday 00:00 UTC (P) | 4 |
| D7 | First quest release | ✅ (2026-10-10) tutorial + daily + weekly quests from existing activities only; new mini-activities (coffee delivery, documents, supplies) later as 2c | 2b |
| D8 | Quest counts and resets | ✅ (2026-10-10) 3 daily (00:00 UTC) + 3 weekly (Monday 00:00 UTC), one free reroll of a daily a day | 2b |
| D10 | Daily events | ✅ (2026-10-10) an automatic Event of the Day from a rotation, personal points and 3 tiers; admin events stay | 5 |
| D11 | Co-op missions | ✅ (2026-10-10) team boss missions (2-4 players, rewards by contribution with a floor) | 5 |
| D12 | Event / co-op rewards | ✅ (2026-10-10) direct rewards (coins, XP, supplies, sometimes an egg or boost); no new currency | 5 |
| D13 | Where progress counts | ✅ (2026-10-10) personal goals only (co-op per team); no server or global community goals | 5 |
| D9 | Quest rewards | ✅ (2026-10-10) coins + XP; weekly quests add an office-supply roll; a bonus for claiming all 3 dailies | 2b |

## 3. Phase 1: GUI foundation

**Status (2026-10-09):** ✅ implemented on branch `feat/phase1-gui-foundation`; `scripts/check.ps1`
passes; Studio specs **568 passed, 0 failed** (2026-10-09; the first run's one failure was a float
comparison in the new `UiTokens` spec, fixed); playtest `docs/PLAYTEST.md` 336–350 reported passed by the owner. Deviations from
the table below, kept small on purpose:
- **Schema v9 holds only `Settings`** (`ReducedMotion`). `HideChallenges` arrives with Phase 4 as a
  config entry (no migration needed); `OfficePrivacy` and the furniture fields go in v11 with 2a (v10 went to the levelling rework).
- **"🏢 Social" dock button moved to Phase 2a:** with no offices or pickleball yet it would open an
  empty page. The Settings page lives in the Player Panel (Menu / M / Y).
- **Layer tokens and the ranking / placement colours** are added with the first screen that uses
  them (2a), so no token sits unused.
- Gamepad navigation also covers the Hammer Shop, Store (and gift picker) and Bag, not only
  PanelKit windows. The Admin panel's confirm dialog now uses `PanelKit.confirmDialog`.

**Goal:** shared pieces and settings the new panels depend on. No new gameplay.

| Work | Files |
|---|---|
| Name the existing tokens: `PanelKit.Colors`, fonts and sizes move into `Lib/UiTokens` (colours, type scale, spacing, radii, tween durations, z-order layers). PanelKit reads them, and every existing look stays the same. | new `src/client/lib/UiTokens.luau`; `PanelKit.luau` |
| Confirm dialog, tooltip, progress bar, empty/loading/error/locked states as PanelKit pieces | `PanelKit.luau` |
| Gamepad navigation: when a panel opens, `GuiService.SelectedObject` goes to its first control; B / ButtonB closes; selectable order follows the layout | `PanelKit.luau`, `Responsive.luau` |
| `Settings` page in the Player Panel: Reduced motion, Hide challenge notices, Music (moved here) | `PlayerPanelController.luau` |
| Saved `Settings` (schema v9) | `PlayerDataSchema.luau`, specs |
| `Settings.Set` remote (key from a fixed list, value checked against that key's type) | `default.project.json`, new `SettingsService.luau`, `REMOTE_CONTRACTS.md` |
| Reduced motion: `UiTokens.motion()` returns 0-length tweens and turns off camera shake and floaty UI motion. Read by PanelKit, HitEffects (camera shake), the Victory Card and level-up cards | those modules |
| "🏢 Social" dock button that opens the Player Panel on a new **Social** page (F2) | `Responsive.luau`, `PlayerPanelController.luau` |

**Gate:** existing panels look the same (screenshots before and after on 3 form factors). Every
panel can be driven with a gamepad. Reduced motion removes the shake and panel tweens. Settings survive a rejoin.

## 3b. Levelling rework (owner request 2026-10-09, before 2a)

**Status (2026-10-10):** ✅ complete on branch `feat/levelling-rework`; `scripts/check.ps1` passes;
Studio specs **594 passed, 0 failed**; playtest (`docs/PLAYTEST.md` "Levelling rework", 351–366)
reported passed by the owner (2026-10-10). Decisions in
`docs/MAJOR_GAME_UPDATE.md` §21.4. **Phase 2a is parked** (a git stash on `feat/phase2a-offices`,
unverified) until this is finished; when it resumes, its schema version becomes **v11** (this work took
v10), and its office rewards join the level reward track.

## 4. Phase 2a: furniture, personal offices, Office Directory

**Status (2026-10-10):** ✅ complete on branch `feat/phase2a-offices`, after the levelling
rework (#13, merged), schema **v11**, with office themes and level-reward furniture on the level track (docs/OFFICES.md);
`scripts/check.ps1` passes; Studio specs **636 passed, 0 failed**; Studio Play boots clean after
fixing a remote named `Remove` (2026-10-10, see docs/REMOTE_CONTRACTS.md "Naming"); playtest
(`docs/PLAYTEST.md` "Personal offices", 367–392) reported passed by the owner (2026-10-10).
Owner decision: Basic furniture is free and unlimited, Special items (trophies) come from rewards.
Changes from the plan below: layout entries carry a stable `Id` (so a move or removal can never hit
the wrong item), the starter furniture is a placed default layout rather than an inventory kit, the
Office Directory lives on the Player Panel's new Social page (🏢 Social HUD button), and admins can
reward Special furniture. Still open: the performance baseline (deferred, B4), so the Office Wing's
cost hasn't been measured yet.

### 4.1 Rules (`Shared/FurnitureRules`, pure, spec-covered)
- Room: 40 × 40 studs (P), positions are whole studs relative to the room's centre, rotation is 0/90/180/270.
- Footprint = the item's `Size` X/Z swapped for 90/270. It must fit inside the room minus a 1-stud
  wall margin, must not overlap another placed footprint, and must not touch the **entry zone**
  (the 8 × 6 area inside the door, plus a 3-stud path to the room's middle) (P).
- `count placed of item ≤ count owned`; at most 60 placed items (P).
- `parseLayout(raw)` sanitises a saved layout: drops unknown items, out-of-range or overlapping
  entries, and entries beyond what the player owns. It never errors and keeps the most entries
  possible (first come, first kept).

### 4.2 Config (`Config/FurnitureConfig`)
About 25 starting items in 5 categories (Desks & chairs, Tech, Plants & storage, Decor, Trophies), each
with `Key, Name, Category, Size, Rarity, Template` (template = part-built like the campus, no uploads).
`StarterKit = {desk_basic=1, chair_basic=1, plant_small=1}`. `SupplyDropTable`: odds per rarity for
the loser's and winner's pools (published in config and `docs/OFFICES.md`).

### 4.3 Server (`Services/OfficeService`)
- At startup: build `MaxPlayers` empty rooms (D2) in the **Office Wing** at y = 400 (P), far from and
  invisible to the main map. A room is about 60 parts (floor, walls, windows, door, nameplate,
  lights). Anchored, templates cloned.
- `onLoaded`: assign a free slot, fill it from `OfficeLayout` (sanitised), set the nameplate.
  `PlayerRemoving`: clear and free it.
- Remotes (`Office` folder): `Go(targetUserId?)` visits own office or another's; `Return`;
  `Place(itemKey, x, z, r)`; `Move(index, x, z, r)`; `Remove(index)`; `SetPrivacy(mode)`. Each one
  is checked for argument types and ranges, the player's ownership, being inside **their own** room
  (for edits), the rules in 4.1, and a rate limit (`RemoteLimits.Office`, 6 per 2 s (P)).
- Layout edits change `OfficeLayout` in the profile immediately (ProfileStore saves it). No extra
  DataStore calls.
- Privacy guard (1 s loop, like `ExecutiveService.guardTick`): anyone inside a room they aren't
  allowed in is sent to the lobby with a toast. Friends-only uses `Player:IsFriendsWith`, cached per
  pair for the session (P).
- Every teleport goes through `MovementGuardService.noteTeleport`.

### 4.4 Client
- `OfficeController`: edit mode inside your own office: inventory strip (PanelKit grid with
  category filters), a placement **preview** following the mouse or a touch drag, snapped to the
  grid. It turns green or red using the same `FurnitureRules`, with rotate / confirm / cancel buttons
  (also gamepad: LB/RB rotate, A place, B cancel). The server's answer is final: a refused
  placement shows its reason.
- `OfficeDirectoryController`: Social page → **Offices**: one row per player in the server (avatar
  thumbnail, name, "Public / Friends / Private", **Visit**, disabled with a reason when not
  allowed). **My Office** and **Return** buttons.

**Gate:** see `docs/UPDATE_TEST_PLAN.md` §3.1. Includes a two-client test (visiting, privacy,
no editing others' rooms) and the migration of a v8 profile.

## 5. Phase 4: Recreation Center and pickleball

**Status (2026-10-10):** ✅ 4a complete on branch `feat/phase4-pickleball` (docs/PICKLEBALL.md), schema
**v12**; `scripts/check.ps1` passes; Studio specs **693 passed, 0 failed** (2026-10-10); the 2-client
playtest (`docs/PLAYTEST.md` "Pickleball", 393–422) reported working by the owner after the swing fix
(`f2cc101`: Studio test players have negative UserIds; held swings; arm swing; reach glow). Rejoin
rows 410/421 need a published place.

**Phase 4b (2026-10-10):** ✅ complete on branch `feat/phase4b-season-board`: `RecreationRankService`
(ordered store `RecRating_<seasonId>`, frozen results in `RecSeasons`, prizes on join or within a
minute, once per season via `SeasonClaims`), `Rec.Season` remote, the 📈 Season tab, season prizes on
the Prizes tab, pure rules + specs in `PickleballRules`. No schema change (v12). Deviations: ranked
only after 5 rated matches (P), so one lucky win can't take a prize; prizes are coins + Special
furniture (the Champion Plaque for #1), **no season titles yet** (titles are level-derived; saved
titles would be a schema change); the last 3 finished seasons can still be collected. `scripts/check.ps1`
passes; the playtest (`docs/PLAYTEST.md` 423-429) was reported working by the owner (2026-10-10); a Studio
spec run with the new season specs was not reported. D4–D6 accepted by the owner. Changes from the plan below:
- **Split into 4a and 4b.** 4a (this branch): challenges, matches, rules, rewards, supplies, the Elo
  rating with its season reset. 4b (next): the seasonal leaderboard (ordered store per season) and
  the top-10 season prizes. v12 already saves `SeasonId` and `SeasonClaims`, so 4b needs no migration.
- **Friendly matches are per match:** if anyone in it has reached a daily cap, nobody pays or earns.
- **Doubles:** either partner may return a serve (players are placed so the correct receiver stands
  in the right court); a player left alone is always placed to serve or return.
- **Six new Special furniture items** (office supplies) for the drop pools; the Golden Hammer
  Trophy and Zen Bonsai are in them too, the Champion Plaque is kept for season prizes.
- `PlayerDataService.beforeRelease` (new): a leaver's forfeit is recorded before their data is saved
  for the last time. `HammerService.setPutAway` (new) keeps the hammer away during a match.
- Courts at x ±24 (not ±20) so a 14-stud spectator lane with the sign fits between them.

### 5.1 Rules (`Shared/PickleballRules`, `Shared/BallFlight`; pure, spec-covered)
Standard rules from §21.1: one game to 11, win by 2, side-out scoring, singles serving side
by score parity, doubles server 1/2 with the 0-0-2 start, two-bounce rule, kitchen volley fault,
line in / serve-on-kitchen-line fault, net, out, double bounce, wrong service court.
`BallFlight.path(launch, velocity, t0)` gives positions, bounce points and net contact deterministically, so
the server and clients agree. Elo rating (D5).

### 5.2 Server (`Services/RecreationService`)
- **Challenges:** `Rec.Challenge(mode)`, `Rec.Accept(challengeId, team?)`, `Rec.Cancel()`. The
  server checks the fee is affordable (it doesn't charge yet), one open challenge per player, a 30 s cooldown (P), expiry
  (60 / 90 s), and "first to accept wins" with check-then-set and no yield (audit §7.4).
  Notices go to everyone except players with `HideChallenges` (`AnnouncementController` card with
  **Accept**) plus a "🏓 Challenges (n)" chip (EventController pattern).
- **Courts:** 2 (P). If none is free, the challenge is queued and shows its position.
- **Match start:** check the fee again and charge it to every player (`trySpendCoins`). If anyone can't pay, cancel
  and refund the rest. Teleport onto the court (`noteTeleport`). Put the hammer away and hand over a
  paddle Tool. Fix walk speed at 18 (P), sprint off. A court guard sends away anyone not in the match.
- **Play:** `Rec.Swing(aim)`, where `aim` is a direction and power in [0,1] that the server clamps.
  A hit is accepted only if it's this player's turn to be allowed to hit (two-bounce, serve order),
  the ball's server-computed position at the server's receive time is within paddle reach + grace
  (P 6 + 1.5 studs), and the swing cooldown has passed. The kitchen rule uses the server's view of the
  player's position. The server then starts a new flight and broadcasts `Rec.Shot {launch, velocity,
  t0}`. Score events go out as `Rec.MatchState`.
- **End:** winner(s) +60, loser(s) +20 (P), a supply roll each (better pool for the winners) into
  `Furniture`, rating update, `ProcessedMatches` id saved. Each step is idempotent per match id.
  Daily caps (10 rewarded matches, 3 per same opponent set (P)) are checked against `Recreation.DayKey`
  (the UTC date). Over the cap = friendly match (no fee, nothing awarded).
- **Disconnects / timeouts:** as in §21.1. Before the first point: cancel and refund. After: the
  leaver's side forfeits. Doubles partner left alone: may play on or forfeit. 20-minute limit (P).
- **Seasons** (`RecreationRankService`): ordered store `RecRating_<seasonId>`, written like
  `LeaderboardService` (on change, at most every 120 s, and on leave). After a season ends, the first server to
  read it saves a frozen top-10 record in DataStore `RecSeasons` (`UpdateAsync`, only if missing). Each player's prize is
  granted on their next join if `SeasonClaims` doesn't contain the season id yet.

### 5.3 Client (`PickleballController`)
Challenge panel (mode picker, fee shown, open challenges with Accept), match HUD (three-number
score in doubles, serve indicator, faults explained in words: "Kitchen volley!"), the ball drawn
from `BallFlight`, paddle swing animation (SwingAnimator-style joint offsets), a result card with
**Rematch** / **Back to campus**. Spectators stand outside the court lines.

**Gate:** `docs/UPDATE_TEST_PLAN.md` §3.2, including the 2- and 4-client Studio tests and an abuse
script (fake swings, swings out of reach, racing accepts, leaving mid-match).

## 6. Later phases (planned in detail when reached)
- **2b Quests: ✅ complete 2026-10-10 on branch `feat/phase2b-quests`** (docs/QUESTS.md, schema v13,
  D7-D9). `scripts/check.ps1` passes; Studio specs **718 passed, 0 failed** (2026-10-10, after fixing one
  spec that set progress 1 on a 1-step quest); playtest (`docs/PLAYTEST.md` 430-446) reported working by the owner (2026-10-10).
  Deviations: no `Career` points (career = level titles), finished but unclaimed quests are paid at the
  reset instead of being lost, the tutorial has no pickleball or visiting step (both need other players).
  Original plan:
- **2b Quests (career = level titles since 2026-10-09, §21.4):** `QuestConfig` / `QuestRules` (objectives counted from events the server
  already sees: defeats, Zen, matches, furniture placed, coffee deliveries), reset windows in UTC,
  claims stored as ids. Career points come from quests/matches/co-op, ranks unlock furniture
  and titles only.
- **5a Event of the Day: ✅ complete 2026-10-10 on branch `feat/phase5a-daily-event`**
  (docs/DAILY_EVENTS.md, schema v14, D10/D12/D13). Also `Services/ActivityService`: one activity feed
  for quests and events (services report there instead of to `QuestService`). `scripts/check.ps1`
  passes; playtest (`docs/PLAYTEST.md` 447-455) reported working by the owner (2026-10-10). Tiers pay automatically
  (no claim button). **5b team boss missions** (D11) next.
- **5 Events and co-op:** new `EventRules` types; co-op contribution counted per action.
- **3 Tower:** new floors stacked above the existing building, behind the existing Level/unlock rules.
  Re-check every fixed-position spec.
- **6 Showcase:** offline office visits (read-only layout), contests, voting limits, moderation.

## 7. Files expected to change (2a + 4)
New: `src/config/{FurnitureConfig,PickleballConfig}.luau`, `src/shared/{FurnitureRules,PickleballRules,BallFlight}.luau`,
`src/server/services/{OfficeService,RecreationService,RecreationRankService,SettingsService}.luau`,
`src/server/lib/{OfficeWingBuilder,CourtBuilder}.luau`,
`src/client/controllers/{OfficeController,OfficeDirectoryController,PickleballController}.luau`,
`src/client/lib/UiTokens.luau`, matching specs under `tests/Unit/*`, `docs/{OFFICES,PICKLEBALL}.md`.
Changed: `default.project.json` (remotes), `PlayerDataSchema.luau` (+specs), `Types.luau`
(`ProfileSnapshot`), `ProgressService.luau` (snapshot), `RemoteLimits.luau`, `HammerService.luau`
(put away / give back), `PanelKit.luau`, `Responsive.luau`, `PlayerPanelController.luau`,
`ArenaConfig.luau` / `CampusBuilder.luau` (D3), `docs/{DATA_SCHEMA,REMOTE_CONTRACTS,GAMEPLAY_RULES,UI,PLAYTEST}.md`.

## 8. Phase 0 gate (to finish Phase 0)
1. ✅ Audit, plan, risk register, UI/UX spec and test plan written (2026-10-09).
2. ✅ `scripts/check.ps1` passes (2026-10-09).
3. ✅ Full TestEZ suite in Studio: 533 passed, 0 failed (2026-10-09, after fixing 2 outdated specs).
4. ✅ Polish-pass playtest `docs/PLAYTEST.md` 110–214 reported done by the owner (2026-10-09).
5. ⏭ Performance baseline deferred by the owner (2026-10-09). It **must** be recorded before Phase 2a adds the Office Wing (`docs/UPDATE_TEST_PLAN.md` B4, B5).
6. ✅ D1–D3 accepted by the owner as recommended (2026-10-09). D4–D6 are still open until Phase 4.
