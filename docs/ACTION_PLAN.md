# WHACK IT OUT! — Progress Review & Action Plan

_Review date: 2026-10-05 · Last status update: 2026-10-05 · branch `feat/phase4-progression`_

**Status legend:** ✅ Done · 🟡 Partly done / awaiting verification · ⬜ Not started

---

## 0. Status at a glance

| Item | Status | Where / note |
|---|---|---|
| P1-1 Fresh clone can't build | ✅ | `06043a6` — optional `$path` folders |
| P1-2 Wrong script topology | ✅ | `06043a6` — `Main` scripts + `Shared/Lifecycle` |
| P1-3 Format gate fails (CRLF) | ✅ | `06043a6` — `.gitattributes` LF |
| P1-4 `--!strict` unenforced | ✅ | `06043a6` — luau-lsp + strict `.luaurc` |
| P1-5 No test harness | ✅ | `06043a6` — harness + first spec; 4/4 passed in Studio (2026-10-05) |
| P2-1 … P2-8 Standards issues | 🟡 7 of 8 done; P2-7 partly (CLAUDE.md layout tree) | §3 |
| P3 Cleanup | 🟡 9 of 10 done | §3 |
| Git: single default branch | ✅ | `master` is default; `main` deleted; its `LICENSE` kept (`53d8a56`) |
| Phase 0 — Foundation | ✅ Complete | CI green on PR #1 and on `master` (`f2faca7`) |
| Phase 1 — Core architecture | ✅ Complete (PR #2) | Lifecycle, config, Types, Validate, RateLimiter, RemoteController, REMOTE_CONTRACTS; 46/46 specs pass in Studio |
| Phase 2 — Shared-boss vertical slice | ✅ Accepted for now (2026-10-05, solo playtest after 6 rounds); multiplayer/abuse playtest checks 9–17 still to run | 5 services, 6 client controllers, arena, 93 specs |
| Phase 3 — Persistence | ✅ Complete (PR #4): 108/108 specs; save playtest reported no errors or warnings (2026-10-05) | ProfileStore via `PlayerDataService`, schema v1 with migrations and validation |
| Phase 4 — Rewards, progression, content | 🟡 Implemented; specs + playtest pending | Coins, boss unlocks, hammer shop, five boss stations, schema v2 |
| Phases 5–6 | ⬜ | |
| §5 Design decisions | 🟡 3 of 5 decided | Shared bosses (+ reward/respawn rules) · end on defeat · hammer-driven damage. Open: persistence library, monetization |

---

## 1. Where the project stands

**Stage:** playable shared-boss loop implemented (Phase 2), specs passing, awaiting playtest. No persistence yet.

| Area | Status | Notes |
|---|---|---|
| Toolchain (Rokit: Rojo 7.7.1, Wally 0.3.2, StyLua 2.5.2, Selene 0.32.0, luau-lsp 1.70.1, run-in-roblox 0.3.0) | ✅ Installed | run-in-roblox blocked on this machine (port 50312 reserved by Windows) |
| Rojo project / instance tree | ✅ | Builds on fresh clone; one `Main` Script + one `Main` LocalScript; `Services`/`Controllers`/`Screens` are Folders |
| Boot pattern | ✅ | `Shared/Lifecycle`: all `init()` then all `start()`, name-ordered |
| Shared config | ✅ Hardened | `GameConfig`, `BossConfig` (5 bosses), `HammerConfig` (1 hammer), `ArenaConfig` (boss spawns): frozen, `List` + `ById`, duplicate ids fail at load |
| Combat & stress rules | ✅ | `Shared/CombatRules` (damage, cooldown, reach), `Shared/StressRules`, documented in `docs/GAMEPLAY_RULES.md` |
| Shared types | ✅ | `Types`: `BossInstanceId`, `CombatFeedback` payload (PascalCase). Unused camelCase `PlayerStats` removed. `PlayerData` arrives with Phase 3 |
| Remotes | ✅ Handled | `RequestHammerHit` → `CombatService`; `CombatFeedback`, `BossDefeated` sent by server; replicated attributes documented in `REMOTE_CONTRACTS.md` |
| Server services (Boss, Combat, Stress, PlayerData, Reward, Purchase, Session, RemoteController) | 🟡 7 of 8 (+ `HammerService`, `ShopService`, `ProgressService`) | `RemoteController`, `SessionService`, `BossService` (+ `Lib/BossState`), `CombatService`, `StressService`, `PlayerDataService` (+ `Lib/PlayerDataSchema`), `RewardService`; `PurchaseService` (real-money) is Phase 5 |
| Server-only config | ✅ | `ServerScriptService.Config` (`src/server/config`): `RemoteLimits` |
| Client controllers (Input, Gameplay, UI, Feedback, Audio) | 🟡 4 of 5 (+ BossVisual, HammerPose, Progress, Shop) | Audio deferred: needs uploaded/licensed sound assets |
| UI screens | 🟡 Code-built placeholder | HUD (Stress Meter, score, hint), boss HP billboards, Victory Card. Art pass in Phase 4 |
| Arena | 🟡 Placeholder | Floor + spawn in `default.project.json`; bosses are code-built cartoon monsters (`BossVisualConfig`) until real art |
| Tests (TestEZ) | 🟡 | 137 specs. 108 passed in Studio; 29 new (ProgressionRules, schema v2, reward guard, config) pass static checks, **not yet run in Studio** |
| Checks script | ✅ | `scripts/check.ps1` (format, lint, type-check, build; `-Tests` for TestEZ) |
| Docs | 🟡 | `DEVELOPMENT_WORKFLOW`, `GAMEPLAY_RULES`, `REMOTE_CONTRACTS`, `PLAYTEST` current; `DATA_SCHEMA` still a template (Phase 3) |
| CI | ✅ | `.github/workflows/ci.yml` green on GitHub; `actions/checkout` moved to v7 (Node 24) |
| License | ✅ | MIT `LICENSE` on `master` |

**Content-rule check:** all five bosses (Deadline Boss, Meeting Master, Reply-All Boss, Production Bug, Monday Monster) are fictional everyday annoyances with no real people, groups, or political references. ✅ Keep it that way in art direction too: render them as cartoon monsters/objects, not as human "bosses/managers", and keep hit reactions squash-and-stretch, no blood.

---

## 2. Verification

### Current (after `06043a6`)

| Check | Command | Result |
|---|---|---|
| Build, working tree | `scripts/check.ps1` | ✅ Pass (game + test place) |
| Build, simulated fresh clone | `scripts/check.ps1` in a copy with only Git-tracked files | ✅ Pass |
| Format | `stylua --check src tests scripts` | ✅ Pass |
| Lint | `selene src scripts`, `selene --config selene.tests.toml tests` | ✅ 0 errors / 0 warnings |
| Type check (`--!strict`) | `luau-lsp analyze` (src; tests + scripts) | ✅ Pass. Confirmed it fails on a planted type error |
| Instance tree | `rojo sourcemap --include-non-scripts` | ✅ `Services`/`Controllers` are Folders; TestEZ absent from game place |
| Unit tests | `build/tests.rbxl` in Studio → Run (F8) | ✅ `4 passed, 0 failed, 0 skipped` · `[Tests] PASSED: 4 test(s)` (2026-10-05). CLI route (`check.ps1 -Tests`) still blocked: run-in-roblox can't bind port 50312 (Windows-reserved range 50260–50359) |

### Baseline (at original review, `a49f30d`), kept for reference

| Check | Result |
|---|---|
| Build, local | ✅ Pass |
| Build, fresh clone | ❌ `File $path: src/server/controllers` not found |
| Format | ❌ 5 files differ (CRLF) |
| Lint | ✅ |
| Type check | ⛔ luau-lsp not installed |
| Tests | ⛔ None |
| Instance tree | ⚠️ `ServerScriptService.Services` was a Script |

---

## 3. Findings (by severity)

P0 = crash/data loss/security catastrophe · P1 = major failure / blocks next phase · P2 = standards violation · P3 = cleanup

### P1 — fix before writing gameplay code

| # | Status | Finding | Resolution |
|---|---|---|---|
| P1-1 | ✅ | **Fresh clone can't build.** Git doesn't track empty dirs; Rojo errored on missing `$path`. | Folders use `"$className": "Folder"` + `"$path": { "optional": … }`, so a missing dir builds as an empty Folder. Verified on a simulated fresh clone. |
| P1-2 | ✅ | **Wrong script topology.** `init.server.luau` turned `Services` into a Script; `init.client.luau` was unmapped. | `src/server/Main.server.luau` and `src/client/Main.client.luau` are the only scripts; they boot ModuleScripts through `src/shared/Lifecycle.luau`. Health-check, `init.*` and `Hello.luau` deleted. |
| P1-3 | ✅ | **Format gate fails** (CRLF vs StyLua `Unix`). | `.gitattributes` (`* text=auto eol=lf`), files renormalized, StyLua applied. |
| P1-4 | ✅ | **`--!strict` unenforced.** | luau-lsp 1.70.1 pinned in `rokit.toml`; strict `.luaurc`; Roblox defs downloaded to match the pinned version by `scripts/check.ps1`. |
| P1-5 | ✅ | **No test harness.** | TestEZ 0.4.1 dev-dependency (`DevPackages/`, not shipped), `test.project.json`, `scripts/TestRunner.server.luau`, `types/testez.d.luau`, `selene.tests.toml` + `testez.yml`, first spec `tests/Unit/Config/BossConfig.spec.luau`. Executed in Studio: 4/4 passed. TestEZ is archived upstream; Jest-Lua remains the fallback. |

### P2 — standards violations to fix during Phase 0/1

| # | Status | Finding | Fix |
|---|---|---|---|
| P2-1 | ✅ | `RequestHammerHit` contract takes a config `{ bossId }` from the client. With shared bosses (decided), several boss instances can be in the world. | Payload: a server-issued boss **instance** id (bounded string), never a config id or damage. Server checks the instance exists, is alive and is within reach, plus cooldown. **Done:** contract in `REMOTE_CONTRACTS.md`; enforcement code lands with `CombatService` in Phase 2. |
| P2-2 | ✅ | Config tables were mutable; `BossConfig` had no lookup. | All config deep-frozen; `List` + `ById`; duplicate ids error at require; specs check freezing, indexing, values. |
| P2-3 | ✅ | Damage rules were duplicated/ambiguous. | Hammer-driven: `max(MinHitDamage, round(hammer.Damage × boss.DamageTakenMultiplier))`. `HitDamage` → `DamageTakenMultiplier`, `DefaultHitDamage` → `DefaultHammerId`. Multipliers chosen so hits-to-defeat match the old balance (spec-guarded). |
| P2-4 | ✅ | Stress Meter had no rules. | Damage-proportional relief + defeat bonus: `StressRules` (`reliefForHit`, `applyRelief`), `GameConfig.StressReliefPerDamage` / `DefeatStressRelief`, documented in `GAMEPLAY_RULES.md`, specs. |
| P2-5 | ✅ | Naming: `Types.PlayerStats` camelCase vs `DATA_SCHEMA.md` PascalCase. | PascalCase for data/payload fields; `PlayerStats` removed; `Types` documents the rule. |
| P2-6 | ✅ | Timed rounds vs defeat→reward→replay loop. | Decided: shared bosses, end on defeat. `RoundDuration` and `Round.RoundState` removed. Shared-boss reward/respawn rules confirmed; numeric values land in config in Phase 2. |
| P2-7 | 🟡 | Docs referenced `skills/`; CLAUDE.md "preferred repository" layout differs from actual. | ✅ `skills/` paths fixed (`ef7aefd`). **Open:** CLAUDE.md layout tree still shows `src/ReplicatedStorage/...` instead of `src/server`, `src/client`, `src/config`, `src/shared`. |
| P2-8 | ✅ | Nothing marked which config values are server-only. | Server-only config lives in `src/server/config` → `ServerScriptService.Config` (never replicated). First resident: `RemoteLimits`. |

### P3 — cleanup

| Status | Item |
|---|---|
| ✅ | `wally.lock` `registry = "test"` — Wally's own output, not a defect. `private = true` added to `wally.toml`. |
| ✅ | `src/shared/Hello.luau`, empty `src/remotes/` deleted. |
| ✅ | Health-check `print` banners removed. |
| ✅ | Untracked `selene.toml`, `stylua.toml`, `wally.toml`, `wally.lock` committed. `.gitignore` also covers `DevPackages/`, `sourcemap.test.json`, `globalTypes.d.luau`. |
| ✅ | Git: one default branch (`master`); `main` deleted after carrying over its `LICENSE`. Feature-branch workflow in use. |
| ✅ | `.gitignore` correct; `WhackItRoblox.rbxl` ignored. |
| ✅ | `package.json` deleted (`ef7aefd`). |
| ✅ | `GameConfig.Version` removed; `wally.toml` is the single version source. |
| ✅ | `Workspace.Gravity` override removed. |
| ⬜ | Merged branch `chore/phase0-foundation` still exists locally and on origin → delete when no longer needed. |

---

## 4. Roblox platform compliance checklist (applies across phases)

None of these are due yet; each is mapped to the phase where it lands.

| Status | Requirement | Phase |
|---|---|---|
| ⬜ | **Maturity & Compliance questionnaire** (Creator Hub): hammer-hitting cartoon targets is "violence" → answer honestly (expected: Mild — cartoon, no blood). No realistic injury, ragdoll gore, or damage decals. | 6 |
| ✅ ongoing | **Community Standards / content:** fictional targets only (true today); no user-generated boss names/images without moderation; player-visible text from players goes through `TextService:FilterStringAsync`. | all |
| ⬜ | **Server authority:** every RemoteEvent is untrusted input. Never use client `Touched` or client-reported positions as proof of a hit; server checks character alive, distance to boss ≤ configured reach, cooldown, active encounter. | 1–2 |
| ✅ | **DataStore rules:** ProfileStore provides session locking, `UpdateAsync`-based saves with retries within budget, auto-save and shutdown flush; key `Player_<UserId>`; load failure kicks instead of playing on defaults; newer-schema data refused untouched (`docs/DATA_SCHEMA.md`). Live verification pending | 3 |
| ✅ | **Right-to-erasure:** data keyed by UserId and linked with `AddUserId`; deletion procedure documented in `docs/DATA_SCHEMA.md` | 3 |
| ⬜ | **Monetization:** idempotent `ProcessReceipt` (record `PurchaseId` before granting, `NotProcessedYet` on any failure); server-side `UserOwnsGamePassAsync`; paid random items gated by `PolicyService` (`ArePaidRandomItemsRestricted`) with disclosed odds; no pay-to-win pressure. | 5 |
| ⬜ | **Policy-aware features:** `PolicyService` before anything restricted by region/age. | 5 |
| ⬜ | **Cross-platform:** `ContextActionService` with touch, mouse/keyboard, gamepad; UI scales with `UIScale`/`UIAspectRatioConstraint`; phone-size emulator test. | 2, 4 |
| ⬜ | **Assets:** original or properly licensed only; audio uploaded under your own account/group; no real-person likeness. | 4 |
| ⬜ | **Studio security settings:** API Services access for testing only; HTTP requests and third-party sales off unless required. | 6 |

---

## 5. Design decisions — 🟡 4 of 5 decided

1. ✅ **Session model:** **shared bosses** (decided 2026-10-05). Follow-up rules ✅ confirmed (2026-10-05): contribution-based full rewards, timed respawn (`docs/GAMEPLAY_RULES.md`).
2. ✅ **Encounter end:** **on defeat**; no round timer in v1 (decided 2026-10-05).
3. ✅ **Damage:** **hammer-driven** (decided 2026-10-05), implemented in `CombatRules`.
4. ✅ **Persistence library:** **ProfileStore** (official `lm-loleris/profilestore@1.0.3`, Apache-2.0) behind our `PlayerDataService` (decided 2026-10-05). Saved: score, stats (hits, bosses defeated), Stress Meter, equipped hammer.
5. ⬜ **Monetization scope for v1** (needed before Phase 5): none / cosmetic hammers via Developer Products / game passes?

---

## 6. Phased action plan

Each phase ends with the CLAUDE.md testing gate: `scripts/check.ps1` (format, lint, type-check, build), TestEZ specs, Studio playtest, multiplayer + security tests where remotes are involved, diff review, docs updated.

### Phase 0 — Fix the foundation — ✅ Complete
Goal: a clean clone builds, formats, lints, type-checks, and runs the test suite.

1. ✅ `.gitattributes` (LF), renormalize, StyLua. → P1-3
2. ✅ `luau-lsp` in `rokit.toml`, strict `.luaurc`, `globalTypes.d.luau` fetched by the check script. → P1-4
3. ✅ `Main.server.luau` / `Main.client.luau`; services/controllers are ModuleScripts; placeholders deleted. → P1-2
4. ✅ Empty-dir `$path`s made optional (kept as Folders). → P1-1
5. ✅ TestEZ dev-dependency, `private = true`, `test.project.json`, runner, first spec (4/4 passing in Studio). → P1-5
6. ✅ Delete `package.json`; fix `skills/` paths in README/CLAUDE.md (`ef7aefd`). → P3, P2-7
7. ✅ `scripts/check.ps1` · `.github/workflows/ci.yml` (Ubuntu runner, Rokit via `CompeyDev/setup-rokit` pinned by commit SHA, runs `check.ps1`; TestEZ stays local because CI has no Studio)

**Done when:** fresh clone passes all gates ✅, specs pass in Studio ✅, CI green on GitHub ✅.

### Phase 1 — Core architecture skeleton — ✅ Complete
1. ✅ `Shared/Types.luau`: `BossInstanceId`, `CombatFeedback`. Boss/hammer definitions stay exported from their config modules; boss instance state and `PlayerData` are added with the services that own them (Phase 2/3).
2. ✅ Config hardening: frozen tables, `List`/`ById`, `HammerConfig`, `CombatRules.computeHitDamage`, specs. → P2-2, P2-3
3. ✅ Service loader pattern (`init()` / `start()`): `Shared/Lifecycle`. Circular-require rule to enforce in review.
4. ✅ **RemoteController** (`src/server/controllers`): sender-present check, argument cap, per-player token bucket (`Shared/RateLimiter`), handler error containment, throttled reject log; payload checks via `Shared/Validate`. Table size/depth caps not needed: all payloads are scalar (documented). State checks belong to each handler (Phase 2).
5. ✅ `docs/REMOTE_CONTRACTS.md` rewritten; `RequestHammerHit(bossInstanceId)` takes a server-issued boss instance id. → P2-1
6. ✅ Specs: Validate (15), RateLimiter (7), RemoteController (5). 46/46 pass in Studio.

### Phase 2 — Vertical slice: one shared boss, full loop, no persistence — ✅ Accepted for now

**Status:** ✅ code · ✅ static checks · 🟡 specs (73/73 passed before the visual pass; 85 now) · 🟡 playtest round 1: boss was a plain block and the character didn't swing → fixed with a client-drawn cartoon boss + hammer Tool with swing; playtest round 2: no swing and no hit while holding the hammer → input now read directly (Tool.Activated kept as backup), Roblox slash animation played explicitly, "Get closer" hint, Studio-only drop diagnostics; playtest round 3: swing worked but looked like a one-way jab → procedural wind-up/strike/follow-through swing on arm, elbow and waist joints, hit sent at impact, other clients replay the strike, `HitCooldown` 0.25 → 0.45 s to match the swing; playtest round 4: hits landed but the arm didn't move (Transform override lost to the Animator, or non-Motor6D joints) → swing now rotates joint base offsets (Motor6D.C0 / AnimationConstraint attachment) that the Animator never writes, with a Studio warning if no shoulder joint is found; playtest round 5: arm swung but the hammer pointed back along the forearm at the shoulder (grip at the wrong handle end) → grip flipped so the hammer extends past the fist, bigger head, `HitReach` 12 → 9 so hits only count where the hammer visibly reaches, grip-direction spec; playtest round 6 (design feedback): the hammer should rest on the shoulder, be out in front only when hitting, then return → `SwingPose.REST` carry pose applied to every holder (`HammerPoseController`), wrist joint (`RightGrip`) added to the swing, impact at 50 %, specs encode rest/impact hammer directions; accepted by the user ("okay for now"). Open: `docs/PLAYTEST.md` checks 9–17 (2–3 players, abuse) not yet run; run before release (`docs/PLAYTEST.md` checks 1–17)

Server: `SessionService` (join/leave, per-player state), `BossService` (spawns shared boss instances with server-issued ids, authoritative HP, per-player damage contribution, respawn after defeat), `CombatService` (validates hit: boss instance alive, live character, reach, cooldown; damage via `CombatRules`), `StressService` (stress from config formula, P2-4).
Client: `InputController` (UserInputService: click/tap/gamepad R2·X, ignoring GUI-processed input), `GameplayController`, `UIController` (boss name, HP bar, Stress Meter, score, Victory Card), `FeedbackController` (hit flash, damage numbers, camera shake, defeat fade; presentation only).
Flow: input → client cooldown sanity → `RequestHammerHit` → server validation → state update → `CombatFeedback` (all clients) → defeat → contributors rewarded (`BossDefeated`) → Victory Card → boss respawns with a new instance id.

**Specs:** stress formula, defeat transition (exactly once even with simultaneous hits), contribution tracking, cooldown rejection, out-of-range rejection, hits after defeat rejected, cleanup when a player leaves mid-fight.
**Playtest:** 1 player and 2–3 players hitting the same boss on a local server; autoclicker / remote-spam test.

### Phase 3 — Persistence — ✅ Complete

**Status:** ✅ code · ✅ static checks · ✅ 108/108 specs in Studio · ✅ save playtest: user reported no errors or warnings (2026-10-05)

`PlayerDataService`: schema v1 (`docs/DATA_SCHEMA.md` made real), defaults, validation, migration pipeline (`v0→v1` test), session locking, autosave, `BindToClose`, retry/backoff within budget, **load failure = kick with friendly message, never overwrite**. Erasure script.
**Specs:** migration, corrupt-data rejection, failed-load path never saves. **Manual:** Studio with API access on, rejoin, two-server simulation.

### Phase 4 — Rewards, progression & content — 🟡 Implemented, verification pending

**Status:** ✅ code · ✅ static checks · ⬜ 137 specs in Studio · ⬜ playtest (`docs/PLAYTEST.md` checks 23–32). Decisions (2026-10-05): score + coins, bosses unlock in order, hammers bought with coins, all five bosses at stations. Deferred: global leaderboard (OrderedDataStore) and audio (needs licensed assets).

`RewardService` (coins/score only on server-confirmed defeat; idempotent per encounter id), boss unlocks, hammer ownership/selection (server-validated), all 5 bosses with cartoon reactions, `AudioController`, particles, mobile-friendly UI, leaderboard (OrderedDataStore, throttled).
**Specs:** reward granted exactly once per defeat; locked boss / unowned hammer requests rejected.

### Phase 5 — Monetization (optional, per decision #5) — ⬜
`PurchaseService`: idempotent `ProcessReceipt` backed by PlayerDataService receipt history, server-side game-pass checks, `PolicyService` gating. **Security tests:** replayed receipts, purchase during data-load failure, rejoin mid-purchase.

### Phase 6 — Hardening & release — ⬜
Security/abuse pass, performance (MicroProfiler, remote traffic, memory per player), mobile device test, Maturity & Compliance questionnaire, asset licensing audit, `docs/RELEASE.md` with rollback plan, private beta → public.

---

## 7. Immediate next steps

1. **You:** run `build/tests.rbxl` (expect 137 passed) and `docs/PLAYTEST.md` checks 23–32.
2. PR + CI + merge `feat/phase4-progression`.
3. Before release: `docs/PLAYTEST.md` checks 9–17 (multiplayer, abuse).
