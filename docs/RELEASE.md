# Release Runbook

Flow (CLAUDE.md release skill): Development → Internal Playtest → QA → Release Candidate → Production → Monitoring.
v1 sells nothing (Phase 5 skipped), so there is no purchase flow to verify.

## 1. Release candidate gate (all must pass)
| # | Check | How | Owner |
|---|---|---|---|
| 1 | Static gates | `scripts\check.ps1` passes; CI green on `master` | Dev |
| 2 | Unit/integration specs | `build\tests.rbxl` → F8 → `[Tests] PASSED: <all>` | Dev |
| 3 | Solo playtest | `docs/PLAYTEST.md` 1–8, 18–21, 23–38 | QA |
| 4 | **Multiplayer playtest** | Studio **Test → Clients and Servers**, 2–3 players: `PLAYTEST.md` 9–13, 22, 39–41 | QA |
| 5 | **Abuse playtest** | `PLAYTEST.md` 14–17, 31–32, 42 (server Output) | QA |
| 6 | Performance | See §2 | Dev |
| 7 | No P0/P1 defects open | crash, data loss, exploitable rewards, broken core loop | Lead |
| 8a | Leaderboard | Board shows "All servers, all time" on a live/API-enabled server |
| 8 | Data compatibility | Live players load cleanly: schema migrations v0→v3 are spec-covered; never deploy a server that can't read the live schema | Dev |
| 9 | Docs current | `GAMEPLAY_RULES`, `REMOTE_CONTRACTS`, `DATA_SCHEMA`, `ACTION_PLAN` match the build | Dev |

## 2. Performance checks (Studio, 3-player test server)
- **MicroProfiler** (Ctrl+F6) on a client during heavy swinging: frame time stays under ~16 ms;
  `BossVisualController` / `SwingAnimator` work per frame stays small.
- **Developer Console (F9) → Memory**: no steady growth over 10 minutes of play (leaks).
- **Network**: `RequestHammerHit` is at most about 2/s per player (cooldown); `CombatFeedback` per hit.
- **Server Stats**: script activity well below 100 % with 3 players hitting.

## 3. Roblox settings (Creator Hub / Game Settings)
### Security (Game Settings → Security)
| Setting | Value | Why |
|---|---|---|
| Enable Studio Access to API Services | Off by default; turn on only while testing saving on a test place | Prevents Studio sessions writing live data by accident |
| Allow HTTP Requests | **Off** | The game makes no HTTP calls |
| Allow Third Party Sales / Teleports | **Off** | Not used |

### Experience questionnaire (Maturity & Compliance)
Answer honestly; these are the facts about the current build:
- **Violence:** players hit cartoon monsters with toy hammers. No blood, no gore, no realistic
  injury, no weapons other than cartoon hammers. Defeated monsters spin and shrink away.
  Expected outcome: mild, cartoon-style violence.
- **Blood / gore / crude humour / romance / alcohol / gambling:** none.
- **Real people / political content:** none. All bosses are fictional everyday annoyances
  (Deadline Boss, Meeting Master, Reply-All Boss, Production Bug, Monday Monster).
- **Social / chat:** standard Roblox chat only; the game adds no player-written text.
- **Paid random items:** none (nothing is sold).

### Places / audience
- Start **private / friends-only** for a beta, then make public.
- Device support: PC, mobile and console input are implemented (click, tap, gamepad R2);
  verify on a phone (Studio device emulator plus a real device) before going public.

### Monetization (Phase 8, see docs/STORE.md)
- [ ] All Developer Products created; ids in `StoreConfig.PRODUCT_IDS`; Creator Hub prices match the store table
- [ ] Questionnaire updated: **paid random items** (Mystery Hammer) declared
- [ ] Mystery Hammer odds visible before purchase; hidden for PolicyService-restricted players (test with a restricted test account, or temporarily force `checkMysteryAllowed` to false)
- [ ] Test purchase of one boost and the Mystery Hammer in a published test place; rejoin shows them kept
- [ ] `StoreAdminConfig.AdminUserIds` holds only intended admins; `StudioTesterIsAdmin` only affects Studio

### Bag and gifts (see docs/STORE.md)
- [ ] One gift tested between two friend accounts in a published test place, with the friend online and offline (PLAYTEST 96-97)
- [ ] Bought items land in the Bag and are only used on Use / Open (PLAYTEST 63-67)

### Admin panel (see docs/ADMIN.md)
- [ ] Every custom boss has a fictional, harmless name (no real people or groups) and sensible rewards
- [ ] Ban and Unban tested once in a published test place with a second account
- [ ] Non-admin account can't see the Admin button and its remote calls are rejected (PLAYTEST 91)

## 4. Asset licensing audit (current build)
| Asset | Source | Licence status |
|---|---|---|
| Bosses, offices, hammers, faces, UI | Built from Roblox parts/GUI in code | Original to this project |
| Swing sound | `rbxasset://sounds/swordslash.wav` (ships with the Roblox client) | Roblox built-in content |
| Hammer glow | Roblox `PointLight` + `Sparkles` instances | Built-in engine effects |
| Fonts | Roblox `FredokaOne` | Roblox built-in |
| Offices, outdoors (terrain, trees, skyline) | Roblox Terrain + parts built in code | Original to this project |
| Spark burst, swing trail | Roblox `ParticleEmitter` (default texture) and `Trail` | Built-in engine effects |
| Background music | `MusicConfig.Tracks`: APM Music tracks from the Creator Store, publisher **APMOfficial** (Roblox's licensed music partner), each checked as asset type Audio on 2026-10-05: Lo-fi Chill A `9043887091`, Chill Jazz `1845341094`, Sunday In Bed `9047104336`, Poolside `9046863253`, Sunset Chill (Bed Version) `9046862941` | Licensed for use in Roblox experiences via Roblox's music partnership. Only add further tracks the same way (Audio, licensed publisher) |
| ProfileStore | `lm-loleris/profilestore@1.0.3` | Apache-2.0 (code dependency) |
| TestEZ | `roblox/testez@0.4.1` | Apache-2.0, dev-only, not shipped |

Before adding any uploaded asset (models, sounds, images): own it or hold a licence, upload it under
your own account/group, and add it to this table.

## 5. Publishing
1. Merge to `master` with CI green.
2. `scripts\check.ps1` → open `build\WhackItOut.rbxl` in Studio.
3. **File → Publish to Roblox** (to the experience's start place).
4. Note the published **version number** (Game Settings → or Creator Hub → Place → Version History)
   and the git commit in the release log (§7).
5. Smoke test on the live servers: join, hit a boss, defeat it, rejoin and check progress kept.

## 6. Rollback
- **Code/content:** Creator Hub → the place → **Version History** → restore the previous version,
  then **Shut Down All Servers** (or migrate to the latest update) so players move to it.
- **Data:** ProfileStore keeps players' data; a rollback is safe as long as the previous build can
  read the current schema. **Never roll back across a schema bump** (e.g. to a build before v3)
  once players have saved newer data: the older server would refuse that data and kick them
  ("saved by a newer version"). Fix forward instead.
- **Single player's data:** use ProfileStore's version history (`VersionQuery` / `GetAsync` with a
  version) from the Command Bar on a test place; see `docs/DATA_SCHEMA.md`.

## 7. Monitoring after release (first days)
- **Creator Hub → Analytics:** concurrent players, session length, retention, crash rate.
- **Error reports:** Creator Hub → **Error Report** for server and client script errors.
  Watch for `[PlayerData]` warnings (load failures) and `[Remote] rejected …` spikes (abuse attempts).
- **DataStore health:** ProfileStore load failures kick the player with a "please rejoin" message;
  a rise in those means DataStore trouble (check Roblox status).
- Keep a release log: date, place version, git commit, notes.

## 8. Known limitations (accepted for v1)
- Reach uses the client-simulated character position; `MovementGuardService` blocks teleports and
  large speed hacks, not small speed boosts below `MovementLimits.MaxHorizontalSpeed`.
- On newer animated (mesh) heads the drawn mood face sits on top of the original face.
- No global (cross-server) leaderboard and no audio beyond the built-in swing sound.
