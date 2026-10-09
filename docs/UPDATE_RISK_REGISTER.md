# Major Update: Risk Register

_Written 2026-10-09 (Phase 0). Severity: P0 = blocks release / data loss / exploit with real impact;
P1 = must fix before release; P2 = fix soon; P3 = accept or watch._

| Id | Risk | Sev | Phase | Mitigation | Check |
|---|---|---|---|---|---|
| R1 | A schema migration loses or resets existing data (v8 → v9+) | P0 | 2a, 4, 2b | New fields only, nothing renamed or removed; migration + sanitize specs from a real v8 snapshot; newer-schema refusal stays | migration specs; Studio save/rejoin with API access on a test place |
| R2 | Coin farming: two friends trade wins, or alts | P1 | 4 | The fee is a sink; the server pays rewards; 10 rewarded matches per day and 3 per same opponent set; Elo makes trading pointless for the rating | spec on the caps; abuse playtest |
| R3 | Wagering look: players paying each other coins | P1 | 4 | No pot. The fee goes nowhere and rewards are fixed by config, so no coins pass between players. Coins can't be bought with Robux | review of the reward code |
| R4 | Fake hits / scores in pickleball | P0 | 4 | The server owns the ball path, decides every hit (reach, turn, two-bounce, cooldown), and owns line calls and score. The client sends only "swing + aim", clamped | security specs; Studio abuse script |
| R5 | Speed hack under the global 50 studs/s guard wins rallies | P2 | 4 | Fixed match speed; court-specific movement check (e.g. > 24 studs/s for 1 s voids the swing) | spec + playtest |
| R6 | Lag makes pickleball feel unfair (hits judged on stale positions) | P1 | 4 | Grace margin on reach; the client draws the ball from the same flight data with the server time offset; tune in a live test with real latency | live test with ≥ 2 regions |
| R7 | Accept race: two players get the same spot | P1 | 4 | Check-then-set with no yield (audit §7.4) | spec on the challenge state machine |
| R8 | Leaving mid-match farms forfeit wins | P2 | 4 | Forfeit wins count toward the daily caps; repeated leavers get a 5-min challenge cooldown (P) | spec |
| R9 | Furniture duplication (placed + still in inventory twice) | P0 | 2a | Inventory isn't decremented on placement; instead `placed ≤ owned` is checked on every edit and on load (`parseLayout`) | spec |
| R10 | Placement exploits: outside the room, blocking the door, overlapping, too many | P1 | 2a | Server-side `FurnitureRules` on every edit, an entry zone, 60-item cap, approved templates only (client sends a key, never a model or path) | specs; Studio abuse script |
| R11 | Visiting a private office / editing someone else's | P0 | 2a | Edits only allowed for the owner inside their own room; visits checked when they start and every second while inside | two-client test |
| R12 | Server fuller than the slot count (MaxPlayers changed in settings) | P2 | 2a | Slot count read from `Players.MaxPlayers` at startup; if none is free, a "no office available" toast and no crash | spec with a mocked count |
| R13 | Performance: Office Wing (12 rooms × ~60 parts, plus up to 60 items × ≤ 12 parts per room: ~9,400 parts worst case) | P2 | 2a | Rooms far from the main map; streaming checked (audit §1); furniture templates kept small (≤ 12 parts each, spec-checked); measure | perf baseline vs after |
| R14 | HUD overload on phones | P2 | 1 | One "🏢 Social" button (audit F2); new entries live in the Player Panel | Device emulator check |
| R15 | Challenge notices annoy players | P2 | 4 | One notice per challenge, auto-hide, 30 s cooldown per challenger, Settings toggle to hide | playtest |
| R16 | Season prize granted twice or lost on a crash | P1 | 4 | Season result frozen once (`UpdateAsync` if missing); prize granted on join when the id isn't in `SeasonClaims`; both saved together in the profile | spec; test place with API |
| R17 | Spec count unconfirmed (526 `it` blocks vs last run 398) | P1 | 0 | Run the full suite in Studio before Phase 1 | Studio F8 |
| R18 | Moving the campus north boundary breaks position specs (event spots, campus clearance) | P2 | 4 | Only extend; re-run all `ArenaConfig`/`CampusBuilder`/`EventConfig` specs | specs |
| R19 | Player-typed text (office names, contest entries) needs filtering | P1 | 6 | First release has no player text (office name = display name); Phase 6 uses `TextService` like `AdminService` | review |
| R20 | Assets without known licences (animations, models, sounds) | P1 | all | Part-built and built-in sounds only unless an asset manifest entry (`docs/ASSETS.md`, to create when the first asset arrives) records source and permission | release checklist |
| R21 | Scope: 7 phases, each larger than past features | P1 | all | One phase at a time with its gate; phases can ship separately behind their own buttons | phase reports |
| R22 | Bosses become "attackers" through new content | P0 | all | Content rule spec-checked: no damage or attack paths from bosses; reviewed each phase | code review |
