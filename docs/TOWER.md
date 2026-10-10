# The Office Tower

Added 2026-10-10 (major update Phase 3a, `docs/MAJOR_GAME_UPDATE.md` §5; decisions D14-D16 in
`docs/UPDATE_IMPLEMENTATION_PLAN.md`). The headquarters gains a 4th floor with a new boss tier and one
elevator that serves every floor, with a floor panel showing what's where and what's still locked.
The Rooftop Lounge (Phase 3b) comes next.

Code: `Config/ArenaConfig` (`Tower`, `DepartmentFloor`, the Principal offices), `Config/BossConfig`
(the Principal tier), `Lib/OfficeBuilder` (the 4th floor and the elevator doors), `Shared/TowerRules`
(floors, access, arrivals; unit-tested), `Services/TowerService` (rides, the 4th-floor guard),
`Services/ExecutiveService` (the Executive Floor guard), `Controllers/TowerController` (the panel).

## Floors
| # | Floor | What's there | Who may go |
|---|---|---|---|
| 4 | Department Heads (y 45) | 5 Principal bosses | Level 30+ |
| 3 | Executive Floor (y 30) | The CEO | the CEO is unlocked: every ground and Senior boss beaten once (unchanged) |
| 2 | Senior Floor (y 15) | 5 Senior bosses (Level 10+ each) | everyone (also by the stairs) |
| 1 | Lobby & Offices | the lobby, the Hall of Calm, 5 office bosses | everyone |

The 4th floor stands on the Executive Floor's roof, over the same north half of the building: five
offices in the same columns as below and a corridor with a window wall over the campus, amber accent
lights and a "FLOOR 4 · DEPARTMENT HEADS" sign. It is reached only by the elevator.

## The elevator
- One shaft at the **west end of the corridor**, with a door on every floor (x -85, z -10). A sign in
  the ground corridor just west of the lobby points to it ("← ELEVATOR · ALL FLOORS").
- Every door has an **Elevator** prompt (E) that opens the **floor panel**: every floor top first,
  with its number, name and contents; "📍 You are here"; **Go to floor N** for floors you may visit;
  and for a locked floor a bar with what's missing ("🔒 Reach Level 30 (you're Level 22)",
  "🔒 Defeat every boss once (3 to go)").
- The server checks every ride (`Tower.Ride`): a known floor, the player standing at an elevator door,
  not already on that floor, and access from saved data. Refused rides get a toast saying what's
  missing. Arriving on the Executive Floor still spikes stress to 100 %.
- The old "Ride up" / "Ride down" prompts on the 2nd and 3rd floor doors are replaced by the panel.
- Guards: anyone on the 4th floor without Level 30 is sent to the Senior floor; anyone on the
  Executive Floor without access is sent down, as before. An admin's boss-access bypass opens every
  floor.

## The Principal tier (4th floor)
| Boss | HP | Damage taken | Score | Coins | Unlock |
|---|---|---|---|---|---|
| Principal Deadline Boss | 2,600 | 1.0 | 1,800 | 200 | Lv 30 + 1 defeat of Senior Deadline Boss |
| Principal Meeting Master | 2,800 | 1.0 | 2,100 | 230 | Lv 30 + 1 defeat of Senior Meeting Master |
| Principal Reply-All Boss | 3,300 | 1.1 | 2,400 | 260 | Lv 30 + 1 defeat of Senior Reply-All Boss |
| Principal Production Bug | 3,900 | 1.2 | 2,800 | 300 | Lv 30 + 1 defeat of Senior Production Bug |
| Principal Monday Monster | 4,800 | 1.4 | 3,300 | 360 | Lv 30 + 1 defeat of Senior Monday Monster |

Each is tougher (more HP per point of damage) than every Senior boss and pays more than its Senior
version; they're a little bigger (×1.15), darker, crowned, with their own signs and lines, and share
their junior's personality. Numbers are provisional.

**The CEO is unchanged:** the Principal tier is listed after the CEO and flagged `PostCeo`, so it
isn't needed to unlock the CEO and isn't counted in the CEO's health (still 37.5 × the toughest
ground or Senior boss).

## Security (docs/REMOTE_CONTRACTS.md "Tower")
The client sends only a floor id; position, access and the move are the server's. Rate-limited.

## Performance
About 60 more anchored parts (5 offices and the floor shell). No per-frame work; the 4th-floor guard
checks positions once a second like the Executive guard.
