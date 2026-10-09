# Major Update: Architecture Audit (Phase 0)

_Audit date: 2026-10-09 · branch `master` at `9b6e6e8` · spec: `docs/MAJOR_GAME_UPDATE.md` (owner decisions §21)_

This is a record of what exists today and how each proposed feature should connect to it. It changes
no behaviour. Every statement below was checked against the source on the audit date. Anything not
checked is marked **unverified**.

## 1. Baseline

| Check | Result (2026-10-09) |
|---|---|
| `scripts/check.ps1` (StyLua, Selene src + tests, luau-lsp strict type-check src + tests, build game + test place) | ✅ All checks passed, run in this audit |
| TestEZ specs | **Not run in this audit.** The CLI runner is blocked on this machine (port 50312 is Windows-reserved), so specs must be run in Studio (F8 in `build/tests.rbxl`). The source has 526 `it(` blocks. The last recorded Studio run was 398/398 (2026-10-07, `docs/ACTION_PLAN.md`), so specs added since are unconfirmed. |
| Polish-pass playtest (`docs/PLAYTEST.md` 110–214) | **Pending** per `docs/ACTION_PLAN.md`. It must pass before Phase 1 so regressions can be told apart from old bugs. |
| Performance baseline (frame time, memory, instance count, network) | **Not measured.** It needs Studio's MicroProfiler / Developer Console on a live or Team Test server. Recording form: `docs/UPDATE_TEST_PLAN.md` §2. |
| Instance streaming | `default.project.json` doesn't set `Workspace.StreamingEnabled`. Some builders set `ModelStreamingMode` (NPCs and bosses Atomic, leaderboard and vending machine Persistent). Whether streaming is on in the built place is **unverified**: check in Studio before Phase 3. |

Size: about 28,500 lines of Luau in 120 modules. The biggest are `AdminController` (2,026), `AdminService` (1,057),
`EventRules` (857) and `PetService` (806).

## 2. Repository layout (actual)

The repo doesn't use the `CLAUDE.md` "preferred" tree. This is the real mapping (`default.project.json`):

| Source | Roblox location | Role |
|---|---|---|
| `src/shared` | `ReplicatedStorage.Shared` | pure rules (unit-tested), types, `Validate`, `RateLimiter`, `Lifecycle` |
| `src/config` | `ReplicatedStorage.Config` | gameplay values, frozen tables with `List` + `ById` |
| `src/server/services` | `ServerScriptService.Services` | authoritative state, booted by `Lifecycle` (all `init()`, then all `start()`) |
| `src/server/controllers` | `ServerScriptService.Controllers` | `RemoteController` (remote guard) |
| `src/server/lib` | `ServerScriptService.Lib` | server helpers and map builders |
| `src/server/config` | `ServerScriptService.Config` | server-only limits (`RemoteLimits`, `MovementLimits`, `DataConfig`, `AdminConfig`) |
| `src/client/controllers`, `src/client/lib` | `StarterPlayerScripts` | presentation and input |
| `ReplicatedStorage.Remotes` | declared in `default.project.json` | every RemoteEvent, by folder |

New work should follow this layout: rules in `Shared` with specs, values in `Config`, state in a
`Service`, display in a `Controller`, and remotes declared in `default.project.json` and documented in
`docs/REMOTE_CONTRACTS.md`.

## 3. Existing systems that new features must reuse

| Need | Existing implementation | Notes |
|---|---|---|
| Remote guarding | `RemoteController.bind(remote, {name, maxArgs, rateLimit}, handler)`, plus `Shared/Validate` and `Config/RemoteLimits` | Checks the sender is still in the game, the argument count and a token bucket per player. Handlers validate `unknown` arguments themselves. Every new remote must use it. |
| Coins | `SessionService.addCoins` / `trySpendCoins` | The only writers of `Coins`. Coins aren't sold for Robux (`docs/STORE.md`). |
| Player data | `PlayerDataService.get`, `onLoaded`, `saveAndConfirmAsync`; `Lib/PlayerDataSchema` (v8, `MIGRATIONS`, `template`, `sanitize`, `prepare`) | ProfileStore with session locking. A failed load kicks the player (never plays on defaults). Data from a newer schema is refused. |
| Grant once | `ProcessedPurchases` (last 200), `ClaimedGifts` (last 200), `BossState.markRewarded` | The pattern for match results, season prizes and quest claims. |
| Cross-server records | DataStores `GiftInbox`, `Events`, `CustomBosses`, `DropRates`, `PlayerHistory`, all validated by a `Shared/*Rules.parse*` | The pattern for season results. |
| Rankings | `LeaderboardService` with `ScoreLeaderboard`, `XpLeaderboard` and `CoinsLeaderboard`; `Lib/LeaderboardRules` | Writes every 120 s when a value changed, reads every 60 s. |
| Server teleports | `ExecutiveService.moveTo` → `MovementGuardService.noteTeleport` + `PivotTo` | Office and court teleports **must** call `noteTeleport`, or the movement guard flags the player. |
| Area guard | `ExecutiveService.guardTick` (1 s loop, sends players without access back) | The pattern for private offices and for active courts. |
| Toasts / notices | `Remotes.Notify.Toast`; `AnnouncementController` (queued card, auto-hides after 6 s, **supports one action button**) | The challenge notice can use the action button for **Accept**. |
| "Something is running" chip | `EventController` (chip under Menu, list shown on tap, countdowns only while open) | The pattern for the open-challenges chip. |
| Big panels | `Lib/PanelKit` (window, sidebar or top tabs, sections, rows, stat tiles, grid, hover/press/disabled states, open animation) | Used for the Office Directory, Pickleball panel and furniture inventory. |
| Screen sizes | `Lib/Responsive` (`classify`, `dockButton`, `capText`, `fitPopup`, `onChanged`) | Already includes phone, tablet and desktop rules (`docs/UI.md`). |
| Profile to client | `ProgressService.sync` → `Profile.Sync` (`Types.ProfileSnapshot`) | New owned data (furniture, settings, rating) is added to this snapshot, not given its own sync remote. |
| Unlock checks | `ProgressionRules.isBossUnlocked` / `unlockStatus` | Tower floors (Phase 3) must use this; doors already do. |
| Scheduled events | `EventService` / `EventRules` (UTC, all servers, MessagingService + 5-min reload) | Daily events (Phase 5) are added as new event types (`docs/EVENTS.md` "Adding an event type later"). |
| Logging | `HistoryService.record` / `recordAdmin` | Match results and placement abuse can be logged here. |
| Admin checks | `Lib/AdminAuth`, `AdminService` | Phase 6 moderation tools go here. |
| Text filtering | Only `AdminService` uses `TextService` today | The first release avoids player-typed text (office names are "<DisplayName>'s Office"). |

## 4. What each proposed feature has today

| Spec feature | Exists today | Gap |
|---|---|---|
| A. Multi-storey tower (§5) | Ground floor (5 bosses), 2nd floor (5 Senior), Executive 3rd floor (CEO); stairs; Executive Elevator; per-player office doors; built by `Lib/OfficeBuilder` from `ArenaConfig` | No departments, recreation building or rooftop. Building bounds `±86 × -52..34` are fixed, and many specs check gaps against fixed positions. |
| B. Career progression (§6, §21.3) | Player Level (from XP, gives damage and crit) | None. Must stay separate from Level and give no damage (spec). |
| C. Quests (§7) | None | All new. |
| C. Furniture inventory (§7.1) | `Bag` holds **StoreConfig product keys only**. `BagRules.sanitize` **drops unknown keys** | Furniture **can't** go in the Bag without changing what it means. A separate `Furniture` field is needed (see §5). |
| C. Personal offices (§21.3) | None (the boss offices aren't player-owned) | All new: slots, layouts, placement, directory, privacy. |
| D. Pickleball (§8, §21.1) | None. `CombatService` needs the hammer Tool; `HammerService` hands it out on spawn | Paddle Tool, courts, match state, ball simulation, challenge flow and rating are all new. |
| D. Seasonal rankings (§8.2) | Lifetime ranking stores only | Needs a season-keyed ordered store and season-prize claims. |
| E. Daily events (§9) | Admin-created timed events (5 types). Lucky drop window (UTC, every 2 h) | Repeating schedules and event objectives. Objectives need the quest system. |
| F. Co-op challenges (§10) | Shared bosses with damage-share rewards (a co-op mechanic) | Non-combat co-op activities are new. |
| G. Showcase / awards (§11) | None | Visiting comes with Phase 2 offices. Contests and voting are new. |
| H. Shareable moments (§12) | Victory Card (server-confirmed defeat summary) | `SocialService` invites and capture are new. Nothing uses them today. |
| GUI design system (§4.3) | `PanelKit.Colors` / fonts / sizes are tokens in all but name; `Responsive` | No reduced-motion setting, **no gamepad UI navigation** (no `GuiService.SelectedObject` / selection handling anywhere), no shared modal / tooltip / confirm component outside the Admin panel. |
| Player settings | Music on/off only (client) | No saved settings. Reduced motion, hiding challenge notices and office privacy need a `Settings` field. |

## 5. Data model: what each phase adds (proposal)

Current: schema **v8**. Each phase that adds saved fields bumps the version once and adds a
migration, sanitize rules and specs (`docs/DATA_SCHEMA.md` "Changing the schema").

| Version | Phase | New fields (all with safe defaults, nothing removed) |
|---|---|---|
| v9 ✅ | 1 GUI foundation (2026-10-09) | `Settings: {[key]: boolean}` (`ReducedMotion`). New on/off settings (`HideChallenges` in Phase 4) are config entries and need **no** migration (`SettingsRules.sanitize`) |
| v10 ✅ | Levelling rework (2026-10-09) | `LevelRewardsClaimed`, `Cosmetics = {Trail, Glow}`; one-time XP raise so nobody loses a level |
| v11 ✅ | 2a Offices (2026-10-09) | `Furniture: {[itemKey]: count}` (Special items only; Basic furniture is free); `OfficeLayout: {{Id, Item, X, Z, R}}` (at most 60, room-local, R in 0/90/180/270); `NextOfficeItemId`; `OfficePrivacy: "Public" \| "Friends" \| "Private"` |
| v12 | 4 Pickleball | `Recreation = {Rating, Wins, Losses, Season, DayKey, DayRewarded, DayPairs: {[pairKey]: n}}`; `ProcessedMatches: {string}` (last 200); `SeasonClaims: {string}` (last 20) |
| v13 | 2b Quests | `Quests` (active, progress, claimed ids per reset window). No `Career` field: career = level titles (§21.4) |
| later | 5–6 | event objective claims, showcase settings |

Size check: a full layout is 60 × ~40 bytes ≈ 2.4 KB. Match history is **not** kept in the profile
(only grant-once ids). The profile stays far below the 4 MB DataStore limit.

## 6. Dependency map (new modules → existing)

```
FurnitureConfig (Config) ── FurnitureRules (Shared, pure: bounds, grid, overlap, entry zone, caps)
        │                          │
OfficeService (Server) ────────────┼── PlayerDataService, SessionService, ProgressService (sync),
  slots, layouts, place/remove,    │   MovementGuardService.noteTeleport, RemoteController,
  visit + privacy guard            │   HistoryService (rejections)
        │                          │
OfficeController / OfficeDirectoryController (Client) ── PanelKit, Responsive, AnnouncementController

PickleballConfig ── PickleballRules (Shared, pure: rules, faults, scoring, serve rotation, rating)
        │               │
        │           BallFlight (Shared, pure: deterministic path, bounces, net, lines)
        │               │
RecreationService (Server): challenges, court allocation, match state, fees and rewards
        ├── SessionService (coins), FurnitureService grant (office-supply drop), PlayerDataService
        ├── MovementGuardService, HammerService (put the hammer away / give it back), RemoteController
        └── RecreationRankService: season ordered store (LeaderboardService pattern), season claims
PickleballController (Client): paddle input, ball display, match HUD ── PanelKit, Responsive
```

Rules stay pure and server-free, so TestEZ can cover scoring, faults, rotation, rating and placement
without Studio play mode. That's how `CombatRules` / `StressRules` / `EventRules` work today.

## 7. Technical limitations that shape the design

1. **Characters are client-simulated.** The server reads positions that can be up to one network
   round-trip old. Paddle reach and kitchen checks need a grace margin, like `HitReachGrace` (1.5
   studs).
2. **The movement guard catches only big jumps** (50 studs/s). A speed hack under that would help in
   pickleball, so courts need their own tighter speed check (the match's walk speed is fixed, sprint
   is off).
3. **Ball physics can't belong to a client** without trusting it. The server computes each flight
   (launch position, velocity, start time; gravity and bounces are deterministic) and sends **one
   event per shot**. Clients draw the same path. No position stream, so network use is small.
4. **Event handlers run one at a time on the server.** A check-then-set with no yield in between is
   atomic, which is enough for "first to accept wins" (same as the world-egg claim in `PetService`).
5. **`Players.MaxPlayers` comes from Game Settings, not the repo.** The office slot count is read
   at runtime.
6. **No uploaded assets so far.** Everything is built from parts with built-in sounds. Authored
   animations and models need uploads with a known licence (`docs/RELEASE.md` §4, asset manifest in
   the plan).
7. **Studio without API access** uses a mock ProfileStore and ignores DataStores. Season and
   cross-server behaviour can only be fully tested on a live or test place with API access.

## 8. Findings to act on

| # | Finding | Action |
|---|---|---|
| F1 | Furniture can't use the Bag (`BagRules.sanitize` drops unknown keys) | Separate `Furniture` field (v9) |
| F2 | The HUD button column is full on phones (Menu, Music, Admin, Bag, Store, Hammers + Sprint) | New entries (My Office, Offices, Pickleball) go in **one** new dock button, "🏢 Social", and the Player Panel. Don't add three buttons. |
| F3 | No gamepad UI navigation anywhere | Phase 1 foundation work, needed before pickleball and furniture placement |
| F4 | No saved settings | `Settings` in v9 |
| F5 | The recreation building has no free spot on the campus (bounded x ±130, z -130..150; the area behind the building has the back loop at z -63) | Owner decision in the plan (D3): move the north boundary, or put the courts in a teleport-only area like the offices |
| F6 | Spec count unconfirmed since 2026-10-07 | Run the full suite in Studio as part of the Phase 0 gate |
