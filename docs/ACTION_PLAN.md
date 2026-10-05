# WHACK IT OUT! — Progress Review & Action Plan

_Review date: 2026-10-05 · Baseline: `master` @ `a49f30d` + uncommitted working-tree changes_

---

## 1. Where the project stands

**Stage:** toolchain scaffold. No gameplay code exists yet.

| Area | Status | Notes |
|---|---|---|
| Toolchain (Rokit: Rojo 7.7.1, Wally 0.3.2, StyLua 2.5.2, Selene 0.32.0) | ✅ Installed | `luau-lsp` (type checker) missing |
| Rojo project / instance tree | ⚠️ Builds locally, **fails on fresh clone** | See P1-1, P1-2 |
| Shared config | 🟡 Started | `GameConfig`, `BossConfig` (5 fictional bosses) |
| Shared types | 🟡 Stub | `PlayerStats` only |
| Remotes | 🟡 Declared in `default.project.json` | `Combat.RequestHammerHit`, `Combat.CombatFeedback`, `Round.RoundState`; no server handlers |
| Server services (Boss, Combat, Stress, PlayerData, Reward, Purchase, Session, RemoteController) | ❌ None | Only a "health check" print script |
| Client controllers (Input, Gameplay, UI, Feedback, Audio) | ❌ None | Only a "health check" print script |
| UI screens | ❌ None | `src/gui/screens` empty |
| Tests (TestEZ) | ❌ None | `tests/` empty, TestEZ not installed, no runner |
| Docs | 🟡 Templates | `DATA_SCHEMA`, `REMOTE_CONTRACTS`, `DEVELOPMENT_WORKFLOW` are examples, not contracts |
| CI | ❌ None | |

**Content-rule check:** all five bosses (Deadline Boss, Meeting Master, Reply-All Boss, Production Bug, Monday Monster) are fictional everyday annoyances with no real people, groups, or political references. ✅ Keep it that way in art direction too: render them as cartoon monsters/objects, not as human "bosses/managers", and keep hit reactions squash-and-stretch, no blood.

---

## 2. Verification actually performed

| Check | Command | Result |
|---|---|---|
| Build (local working tree) | `rojo build -o out.rbxl` | ✅ Pass |
| Build (simulated fresh clone: tracked + untracked files only) | `rojo build` | ❌ **Fail** — `File $path: src/server/controllers` not found |
| Format | `stylua --check src` | ❌ **Fail** — 5 files differ (CRLF line endings vs `line_endings = "Unix"`) |
| Lint | `selene src` | ✅ 0 errors / 0 warnings |
| Type check (`--!strict`) | — | ⛔ Not possible: `luau-lsp` not installed |
| Tests | — | ⛔ None exist |
| Instance tree (sourcemap) | `rojo sourcemap` | ⚠️ `ServerScriptService.Services` is a **Script**, not a Folder |

---

## 3. Findings (by severity)

P0 = crash/data loss/security catastrophe · P1 = major failure / blocks next phase · P2 = standards violation · P3 = cleanup

### P1 — fix before writing gameplay code

> **Status 2026-10-05: P1-1 … P1-5 fixed (uncommitted).** `scripts/check.ps1` passes on the working tree and on a simulated fresh clone. Unit specs exist but have **not yet been executed**: run-in-roblox's fixed port 50312 is in a Windows-reserved range on this machine, so run `build/tests.rbxl` in Studio (F8). See `docs/DEVELOPMENT_WORKFLOW.md`.

| # | Finding | Evidence | Fix |
|---|---|---|---|
| P1-1 | **Fresh clone can't build.** Git doesn't track empty dirs, so `src/server/controllers` and `src/gui/screens` vanish and Rojo errors on the missing `$path`. Blocks CI and any collaborator. | `default.project.json` lines for `Controllers`, `Screens` | Remove those entries until they hold real modules, or put a real module in each. |
| P1-2 | **Wrong script topology.** `src/server/services/init.server.luau` turns the whole `Services` folder into a Script; `HealthCheckService.server.luau` then runs as a child Script. Services must be ModuleScripts loaded by **one** server bootstrap. Same problem pattern on the client: `src/client/init.client.luau` isn't mapped at all (dead file). | sourcemap: `Services (Script) > HealthCheckService (Script)` | One `Main.server.luau` bootstrap in ServerScriptService that requires services (`ModuleScript`s) in a deterministic order (`init` → `start`). One `Main.client.luau` in StarterPlayerScripts doing the same for controllers. Delete the `init.*` and health-check scripts. |
| P1-3 | **Format gate fails.** CRLF files vs StyLua `Unix`. `core.autocrlf=true` will keep reintroducing it. | `stylua --check` diff on 5 files | Add `.gitattributes` with `* text=auto eol=lf`, renormalize, run `stylua src`. |
| P1-4 | **`--!strict` is unenforced.** Selene doesn't type-check; no `luau-lsp`. Three files aren't even `--!strict` (`Hello.luau`, both `init.*`). | file headers | `rokit add JohnnyMorganz/luau-lsp`, run `luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau src`. Add `.luaurc` with `"languageMode": "strict"`. |
| P1-5 | **No test harness.** CLAUDE.md requires TestEZ; it isn't a dependency and there's no runner. | `wally.toml [dependencies]` empty | Add `TestEZ = "roblox/testez@0.4.1"` under `[dev-dependencies]`, map `Packages`/`DevPackages` and `tests/` in a separate `test.project.json`, add a Studio test bootstrap (or `run-in-roblox`) so specs actually execute. Note: TestEZ is archived upstream; it still works, but keep the option of Jest-Lua open. |

### P2 — standards violations to fix during Phase 0/1

| # | Finding | Fix |
|---|---|---|
| P2-1 | `RequestHammerHit` contract takes `{ bossId }` from the client. The server should already know the player's active encounter from `SessionService`; accepting `bossId` is unnecessary attack surface. | Payload: none (or an opaque encounter id the server issued). Server looks up the encounter and validates range/cooldown itself. |
| P2-2 | Config tables are mutable and `BossConfig` is a list with no lookup or validation. Typos/duplicate ids would surface at runtime. | `table.freeze` all config; expose `BossConfig.ById`; add a unit test asserting unique ids and positive, finite numbers. |
| P2-3 | Damage rules are duplicated/ambiguous: `GameConfig.DefaultHitDamage` vs `BossDefinition.HitDamage`. "HitDamage" on a boss reads like damage the boss deals. | Decide the formula (e.g. `hammer.Damage × boss.DamageTakenMultiplier`), rename fields, document in `docs/GAMEPLAY_RULES.md`. |
| P2-4 | Stress Meter has no rules: no per-boss stress value, no formula linking HP loss to stress relief. | Add `StressReliefPerHit` / formula to config + docs. |
| P2-5 | Naming inconsistency: `Types.PlayerStats` uses camelCase fields; `DATA_SCHEMA.md` uses PascalCase. | Pick one convention for data fields (recommend PascalCase to match config) and apply everywhere. |
| P2-6 | Timed rounds (`RoundDuration = 60`, `Round.RoundState`) vs. the core loop in the gameplay skill (defeat → reward → replay) aren't reconciled. Is it per-player encounters or a server-wide round? | Design decision — see §5. |
| P2-7 | Docs reference `skills/` but skills live in `.claude/skills/`. CLAUDE.md's "preferred repository" layout (`src/ReplicatedStorage/...`) differs from actual (`src/server`, `src/client`, `src/config`). | Keep the actual layout (it's fine) and update CLAUDE.md/README to match. |
| P2-8 | Config lives in `ReplicatedStorage` (fine for display values), but nothing marks which values are server-only. | Rule: anything the client must not see (e.g. future anti-cheat thresholds, reward tables) goes in `ServerStorage`/server modules. |

### P3 — cleanup

- `package.json` is an unused npm stub → delete (no Node tooling in this project).
- ~~`wally.lock` says `registry = "test"`~~ — that's Wally's own output, not a defect. `private = true` added to `wally.toml`. ✅
- ~~`src/shared/Hello.luau`, empty `src/remotes/` → delete.~~ ✅
- ~~Health-check `print` banners → remove.~~ ✅
- `GameConfig.Version` duplicates `wally.toml` version → keep one source of truth.
- `Workspace.Gravity = 196.2` is the default → drop the override.
- Git: you're committing on `master` while `origin/main` exists. Pick one default branch, use feature branches per CLAUDE.md git-workflow skill.
- `.gitignore` is good; `WhackItRoblox.rbxl` is correctly ignored. Commit the current untracked `selene.toml`, `stylua.toml`, `wally.toml`, `wally.lock`.

---

## 4. Roblox platform compliance checklist (applies across phases)

These are Roblox-side requirements that this game will hit; each is mapped to a phase below.

- **Maturity & Compliance questionnaire** (Creator Hub): hammer-hitting cartoon targets is "violence" → answer honestly (expected: Mild — cartoon, no blood). No realistic injury, ragdoll gore, or damage decals. _(Phase 6)_
- **Community Standards / content:** fictional targets only (already true); no user-generated boss names or images without moderation. Any player-visible text from players must go through `TextService:FilterStringAsync`. _(all phases)_
- **Server authority:** FilteringEnabled is always on; every RemoteEvent is untrusted input. Never use client `Touched` or client-reported positions as proof of a hit — server checks character alive, distance to boss ≤ configured reach, cooldown, active encounter. _(Phase 1–2)_
- **DataStore rules:** `UpdateAsync` (not `SetAsync`) for player data; session locking to prevent dupes across servers; retries with backoff respecting `DataStoreService:GetRequestBudgetForRequestType`; `game:BindToClose` flush; never save defaults over an unloaded/failed profile; key format `Player_<UserId>`. _(Phase 3)_
- **Right-to-erasure:** keep data keyed by UserId only, and have a documented script to delete a user's keys when Roblox sends a deletion request. _(Phase 3)_
- **Monetization:** `MarketplaceService.ProcessReceipt` must be idempotent (record `PurchaseId` before granting, return `NotProcessedYet` on any failure); check game passes server-side with `UserOwnsGamePassAsync`; if any paid random items are ever added, gate with `PolicyService:GetPolicyInfoForPlayerAsync().ArePaidRandomItemsRestricted` and disclose odds. No pay-to-win pressure tactics. _(Phase 5)_
- **Policy-aware features:** use `PolicyService` before showing anything restricted by region/age (external links, paid random items). _(Phase 5)_
- **Cross-platform:** input via `ContextActionService` with touch, mouse/keyboard and gamepad bindings; UI scales with `UIScale`/`UIAspectRatioConstraint`; test on a phone-size emulator. _(Phase 2, 4)_
- **Assets:** original or properly licensed models/sounds/images only; audio uploaded under your own account/group; no real-person likeness. _(Phase 4)_
- **Studio security settings:** "Enable Studio Access to API Services" for testing only; HTTP requests and third-party sales off unless required. _(Phase 6)_

---

## 5. Decisions needed from you before Phase 2

1. **Session model:** per-player boss encounters (each player whacks their own boss instance — simplest, no griefing) **or** shared bosses that multiple players hit together? _Recommendation: per-player encounters for v1._
2. **Round timer:** keep `RoundDuration = 60` as a timed challenge, or remove timer and end on defeat? _Recommendation: end on defeat; timer is an optional later mode._
3. **Damage formula:** hammer-driven (`hammer.Damage × boss multiplier`) or boss-driven (fixed per boss)? _Recommendation: hammer-driven, so hammers are meaningful progression._
4. **Persistence library:** hand-written `PlayerDataService` on DataStoreService, or ProfileStore (Wally) with a thin `PlayerDataService` wrapper? _Recommendation: ProfileStore — battle-tested session locking; justified dependency under CLAUDE.md._
5. **Monetization scope for v1:** none / cosmetic hammers via Developer Products / game passes?

---

## 6. Phased action plan

Each phase ends with the CLAUDE.md testing gate: `stylua --check`, `selene`, `luau-lsp analyze`, TestEZ specs, Studio playtest, (multi-player + security tests where remotes are involved), diff review, docs updated.

### Phase 0 — Fix the foundation _(≈0.5–1 day)_
Goal: a clean clone builds, formats, lints, type-checks, and runs an (empty) test suite.

1. `.gitattributes` (LF), renormalize, `stylua src`. → P1-3
2. Add `luau-lsp` to `rokit.toml`, `.luaurc` strict, generate `globalTypes.d.luau`. → P1-4
3. Restructure scripts: `src/server/Main.server.luau`, `src/client/Main.client.luau`; services/controllers become ModuleScripts; delete health checks, `init.*`, `Hello.luau`. → P1-2
4. Remove `$path`s to empty dirs. → P1-1
5. Wally: TestEZ dev-dependency, `private = true`, `wally install`, map `Packages` in project; `test.project.json` + test bootstrap; one passing smoke spec. → P1-5
6. Delete `package.json`; fix docs paths. → P3, P2-7
7. Add a `scripts/check.ps1` (or Makefile-equivalent) that runs all gates; add GitHub Actions workflow running format/lint/type-check/build.

**Done when:** simulated fresh clone passes `rojo build`, `stylua --check`, `selene`, `luau-lsp analyze`; CI green.

### Phase 1 — Core architecture skeleton _(≈1–2 days)_
1. `Shared/Types.luau`: `BossDefinition`, `HammerDefinition`, `EncounterState`, `PlayerData`, remote payload types.
2. Config hardening: frozen tables, `ById` lookups, config validation spec. → P2-2
3. Service loader pattern (`init()` / `start()`), no circular requires.
4. **RemoteController** (server): single place that binds remotes, with reusable validators — player present, payload `typeof`, table size/depth caps, string length caps, `number` finite/non-NaN/in-range, per-player token-bucket rate limiter, state check hook. Unknown/invalid → drop + log (rate-limited logging).
5. Rewrite `docs/REMOTE_CONTRACTS.md` as the real contract table. → P2-1
6. Specs: validators (NaN, inf, huge, negative, wrong types, oversized tables), rate limiter.

### Phase 2 — Vertical slice: one boss, full loop, no persistence _(≈3–5 days)_
Server: `SessionService` (player join/leave, encounter lifecycle), `BossService` (spawn per-player boss, authoritative HP), `CombatService` (validates hit: active encounter, alive character, reach distance, cooldown; computes damage from config), `StressService` (stress from config formula).
Client: `InputController` (ContextActionService: click/tap/gamepad), `GameplayController`, `UIController` (Boss name, HP bar, Stress Meter, score), `FeedbackController` (hit flash, squash, camera shake — presentation only).
Flow: input → client cooldown sanity → `RequestHammerHit` → server validation → state update → `CombatFeedback` to that player → defeat → Victory Card → replay.

**Specs:** damage/stress formulas, defeat transition, cooldown rejection, out-of-range rejection, hits after defeat rejected, player leaving mid-encounter cleans up (no leaked connections/instances).
**Playtest:** 1 player and 2-player local server; autoclicker / remote-spam test.

### Phase 3 — Persistence _(≈2–3 days)_
`PlayerDataService`: schema v1 (`docs/DATA_SCHEMA.md` made real), defaults, validation, migration pipeline (`v0→v1` test even if trivial), session locking, autosave interval, `BindToClose`, retry/backoff within budget, **load-failure = kick with friendly message, never overwrite**. Erasure script.
**Specs:** migration, validation rejects corrupt data, failed-load path never saves. **Manual:** Studio with API access on, rejoin, two-server simulation.

### Phase 4 — Rewards, progression & content _(≈3–5 days)_
`RewardService` (coins/score on server-confirmed defeat only; idempotent per encounter id), boss unlock progression, hammer ownership/selection (server-validated), all 5 bosses with cartoon reactions, audio (`AudioController`), particles, mobile-friendly UI layout, leaderboard (OrderedDataStore, throttled).
**Specs:** reward granted exactly once per defeat; locked boss/unowned hammer requests rejected.

### Phase 5 — Monetization (optional, per decision #5) _(≈2 days)_
`PurchaseService`: idempotent `ProcessReceipt` backed by PlayerDataService receipt history, game-pass checks server-side, `PolicyService` gating. **Security tests:** replayed receipts, purchase during data-load failure, rejoin mid-purchase.

### Phase 6 — Hardening & release _(≈2–4 days)_
Security/abuse pass (security skill checklist), performance (MicroProfiler, remote traffic, memory per player), mobile device test, Maturity & Compliance questionnaire, asset licensing audit, release checklist + rollback plan in `docs/RELEASE.md`, private beta → public.

---

## 7. Immediate next step

Start **Phase 0**. It's mechanical, low-risk, and every later phase depends on a build/test gate that actually works. Answer the §5 decisions any time before Phase 2.
