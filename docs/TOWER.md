# The Office Tower

Added 2026-10-10 (major update Phase 3a, `docs/MAJOR_GAME_UPDATE.md` §5; decisions D14-D16 in
`docs/UPDATE_IMPLEMENTATION_PLAN.md`). The headquarters gains a 4th floor with a new boss tier and one
elevator that serves every floor, with a floor panel showing what's where and what's still locked.
The Rooftop Lounge (Phase 3b) comes next.

Code: `Config/ArenaConfig` (`Tower`, `DepartmentFloor`, the Principal offices), `Config/BossConfig`
(the Principal tier), `Lib/OfficeBuilder` (the 3rd floor and the elevator doors), `Lib/RooftopBuilder` (the 5th), `Shared/TowerRules`
(floors, access, arrivals; unit-tested), `Services/TowerService` (rides, the 3rd-floor guard),
`Services/ExecutiveService` (the Executive Floor guard), `Controllers/TowerController` (the panel).

## Floors
| # | Floor | What's there | Who may go |
|---|---|---|---|
| 5 | Rooftop Lounge (y 60) | deck, sofas, coffee cart, loungers, trees, string lights, telescope, the **Mission Board** and **Event Board** | everyone |
| 4 | Executive Floor (y 45) | The CEO, at the top | the CEO is unlocked: every ground and Senior boss beaten once (unchanged) |
| 3 | Department Heads (y 30) | 5 Principal bosses | Level 30+ |
| 2 | Senior Floor (y 15) | 5 Senior bosses (Level 10+ each) | everyone (also by the stairs) |
| 1 | Lobby & Offices | the lobby, the Hall of Calm, 5 office bosses, the Break Room and the Meeting Room | everyone |

**The CEO is at the top (owner request 2026-10-10):** the Executive Floor moved from the 3rd to the 4th
floor and Department Heads from the 4th to the 3rd, so the company's head sits above its department
heads. The 3rd floor stands on the 2nd floor's roof, over the north half of the building: five offices
in the same columns as below and a corridor with a window wall over the campus, amber accent lights and
a "FLOOR 3 · DEPARTMENT HEADS" sign. Floors 3-5 are reached only by the elevator.

### The Rooftop Lounge (5th floor, `Lib/RooftopBuilder`)
On the Executive Floor's roof inside the tower's parapet: an elevator house at the west end ("FLOOR 5 ·
ROOFTOP LOUNGE"), a wooden deck, a sofa corner with coffee tables and bean bags, a coffee cart under a
parasol, four loungers with umbrellas, trees in planters along the north edge, two lines of string
lights, a telescope looking towards the Recreation Center, and two boards: the **Mission Board** (E:
opens 🤝 Team Missions) and the **Event Board** (E: opens 🌟 Today). The crown sign stands on the south
parapet.

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
- Guards: anyone on the 3rd floor (Department Heads) without Level 30 is sent to the Senior floor; anyone on the
  Executive Floor without access is sent down, as before. An admin's boss-access bypass opens every
  floor.

## The Principal tier (3rd floor)
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
