# Major Update: Test Plan

_Written 2026-10-09 (Phase 0). Results are recorded as ✅ passed · ❌ failed · ⬜ untested ·
⛔ blocked, with date and who ran it. Never mark a row passed without running it._

## 1. How tests run here
| Kind | How | Note |
|---|---|---|
| Static gate | `scripts/check.ps1` | format, lint, strict type-check, build |
| Unit specs (TestEZ) | Studio: open `build/tests.rbxl`, F8 | the CLI runner (`check.ps1 -Tests`) is blocked on this machine (port 50312 is Windows-reserved) |
| Playtest | Studio Play / Test → Clients and Servers (2–4 clients) | rows go in `docs/PLAYTEST.md` |
| Data / cross-server | a separate **test place** with API access on | never against live player data |
| Device | Studio Device emulator: 1920×1080, 1366×768, tablet, phone portrait and landscape | `docs/UI.md` |

## 2. Phase 0 baseline
| # | Item | Result |
|---|---|---|
| B1 | `scripts/check.ps1` | ✅ 2026-10-09 (Claude) |
| B2 | Full spec suite in Studio, record the count | ✅ 2026-10-09 (owner): **533 passed, 0 failed, 0 skipped**. The first run had 531 passed and 2 failed, both outdated specs (a phone text-scale cap and a non-preset 2-hour event length), fixed the same day |
| B3 | Polish-pass playtest `PLAYTEST.md` 110–214 | ✅ reported done by the owner (2026-10-09) |
| B4 | MicroProfiler / Developer Console on a 4-client Team Test: client frame time in the lobby, at a boss fight and on campus; server heartbeat; memory; instance count; network in/out kB/s | 🟡 polish round (2026-10-10): `Services/PerfProbeService` and `Controllers/PerfProbeController` print a `[Perf]` line every 15 s in Studio only (server: heartbeat rate and worst frame, memory, Workspace instances and parts, players, network, StreamingEnabled; each client: fps, average and worst frame, memory, network, instances, position). Run a Team Test, stand ~30 s in each place; the numbers are read from Studio's log files. Not recorded yet |
| B5 | `Workspace.StreamingEnabled` value in the built place | 🟡 the project doesn't set it; the probe's server line prints the built value. Not recorded yet |

## 3. Per-phase tests

### 3.1 Phase 2a: offices
Unit (`tests/Unit/Shared/FurnitureRules.spec.luau`, `tests/Unit/Server/PlayerDataSchema.spec.luau`):
- fits in the room at each rotation; wall margin; overlap; entry zone; 60-item cap; `placed ≤ owned`
- `parseLayout` drops unknown, out-of-range, overlapping and over-owned entries and keeps the rest
- v8 → v9 migration keeps every v8 field, adds the starter kit, `Settings` defaults and an empty layout
- sanitize: broken `Settings` values fall back to defaults; `Furniture` counts clamped to whole numbers
- slot assignment: free slot found; none free → nil, no error

Security (`tests/Security/`, a new folder: add it to the test project file):
- every `Office.*` remote: wrong types, NaN/inf, huge numbers, extra args, unknown item keys,
  index out of range, edits from outside your room, edits in someone else's room → refused, nothing changed
- rate limit: a burst over `RemoteLimits.Office` is refused

Playtest (2 clients): join → own empty office with a starter kit · place, rotate, move, remove,
rejoin → layout kept · visit A → B · B sets Private → A is sent back within 1 s · Friends-only
between non-friends refused · A can't edit B's room · leaving frees the slot · gamepad and phone
edit mode.

### 3.2 Phase 4: pickleball
Unit (`PickleballRules`, `BallFlight`):
- scoring: only the server scores; 11 win by 2 (11–9 ends, 11–10 continues, 13–11 ends)
- singles serve side by score parity; doubles 0-0-2 start, server 1 → 2 → side-out
- faults: net, out, line in, serve on the kitchen line, wrong service court, double bounce,
  two-bounce rule broken, kitchen volley
- `BallFlight`: the same inputs give the same path; bounce points; net contact
- Elo: equal ratings ±16 at K 32; doubles uses team averages; rating never below 0
- caps: 10/day, 3 per opponent set, day rolls over at 00:00 UTC

Security:
- `Rec.Swing` out of reach, out of turn, too fast, with a bad aim (NaN, out of range) → refused
- racing `Rec.Accept` for the last spot → exactly one wins
- accepting your own challenge, or a second challenge while in one → refused
- fee: can't afford at start → cancelled, others refunded; no coins created or lost
- the same match id rewarded twice → second grant ignored

Playtest (2 and 4 clients): challenge notice reaches everyone and is hidden by the setting · Accept
→ teleport to the court with a paddle and no hammer · full game to 11 · doubles rotation as rules ·
leave before the first point → refund · leave mid-match → forfeit · rematch · result card amounts
match the coins and furniture received · spectator kept off the court · hammer back after the match.

Live (test place with API access): two servers, rating written to the season store; season end
→ frozen top 10 → prize granted once on the next join, not again after rejoining.

### 3.3 Regression (every phase)
Hammer purchase and equip · boss hit, crit, defeat, rewards split · Stress Meter and Zen · Level and XP
bar · leaderboards · Bag, gifts, pets · events · Executive Elevator · office doors · admin panel.
Use `docs/PLAYTEST.md` rows 1–214 as the checklist, abbreviated to the sections touched.

### 3.4 Performance (Phases 2a, 3, 4)
Repeat B4 with all office slots filled with 60 items and both courts active. Accept if client frame
time stays within 10 % of the baseline on the reference device, and pickleball network stays under
5 kB/s per player (one event per shot).
