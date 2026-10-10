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
| B4 | MicroProfiler / Developer Console on a 4-client Team Test: client frame time in the lobby, at a boss fight and on campus; server heartbeat; memory; instance count; network in/out kB/s | 🟡 polish round (2026-10-10): `Services/PerfProbeService` and `Controllers/PerfProbeController` print a `[Perf]` line every 15 s in Studio only (server: heartbeat rate and worst frame, memory, Workspace instances and parts, players, network, StreamingEnabled; each client: fps, average and worst frame, memory, network, instances, position). Run a Team Test, stand ~30 s in each place; the numbers are read from Studio's log files. ✅ First baseline 2026-10-10 (owner's PC, Studio): see "Baseline 2026-10-10" below |
| B5 | `Workspace.StreamingEnabled` value in the built place | ✅ 2026-10-10: **false** (the project doesn't set it). The audit's instance-streaming check stays open |


### Baseline 2026-10-10 (B4, `[Perf]` probe, owner's PC in Studio)
Two sessions after the polish round: a 1-player Play, and a 4-player Team Test (server + 4 clients
on the same PC). Lines are 15-s windows; the first window of each session includes loading.

| Measure | 1 player (Play) | 4 players (Team Test) |
|---|---|---|
| Server heartbeat | 60/s steady after loading (45/s while loading, worst frame ~1 s) | 60/s steady after loading (40-55/s while 4 joined, worst 1 s then 20 ms) |
| Workspace instances / parts (server) | 3,395 / 2,284 | 4,502 / 2,401 |
| Instances a client sees | 4,718 | 5,858 |
| Network per client | recv ~0, send 0.4-0.7 kB/s | send 0.4-1.8 kB/s; server send 1.4-1.5 kB/s (71 kB/s during the first join) |
| Client frame rate | 13-33 fps at the spawn | 6-43 fps (lobby 6-15, campus 35-43, tower 36) |
| Memory (whole Studio process) | ~2.9 GB | 1.6-2.1 GB per process |
| StreamingEnabled | false | false |

Reading: the server side is light (steady 60/s, ~2,400 parts, under 2 kB/s per player), well inside
Roblox limits. The **client frame rates are not a device baseline**: Studio was rendering the editor
and, in the Team Test, four clients and the server on one PC, under Future lighting. The lobby is the
slowest spot in both runs (the tower interior, many lights and the atrium). Next: check fps in the
published game on a real phone and PC (F9 Developer Console); if the lobby stays low, try
`Lighting.Technology = ShadowMap` and fewer PointLights in the atrium.

**Lobby experiment 2026-10-10** (1-player Play at the lobby spawn, the probe's Studio-only 🧪 Perf
button switching this client's effects, lights and shadows, 10-s windows):

| Mode | fps |
|---|---|
| Normal, while loading | 30.6 |
| Normal, loaded | **60.1** (the 60 fps cap) |
| No post effects | 61.7 |
| No room lights | 60.0 / 66.0 / 48.5 |
| No global shadows | 19.8 |

Reading: once loaded, the lobby reaches the 60 fps cap with everything on, and no single feature
raises it. The low readings (here 19.8 with shadows *off*, earlier 13-20 with everything on) don't
follow the settings, so they come from outside the game (Studio still loading, other programs). **No
graphics were cut.** Still to do: the published game on a real phone and PC (F9 Developer Console).

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
