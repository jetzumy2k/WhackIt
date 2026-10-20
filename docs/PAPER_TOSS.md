# Paper Toss Showdown

Added 2026-10-10 (recreation games 3/3, owner choice "Paper Toss Showdown"). Office basketball, one
player against a CPU coworker. A booth with a desk, a waste bin and a desk fan stands at the east end of
the Recreation Center entrance.

Code: `Config/PaperTossConfig`, `Shared/PaperTossRules` (pure, unit-tested), `Services/PaperTossService`
(the server owns every game), `Controllers/PaperTossController` (window and game screen), the booth in
`Lib/CourtBuilder`, a 🗑️ Paper Toss button on the Social page.

## Playing
1. Walk to the 🗑️ PAPER TOSS sign (prompt "Play") or 🏢 Social → 🗑️ Paper Toss.
2. Pick a coworker: 🧑‍💼 **Intern Izzy**, 👔 **Manager Max**, 👑 **CEO Cora** (beat each to unlock the next).
3. **5 rounds.** Each round the server places the bin (near, mid or far) and sets a desk-fan **breeze**.
   The game screen (the world dims behind it) shows the scoreboard (you vs the coworker), a little
   office with the bin, a breeze chip and a distance chip, then the **AIM** and **POWER** meters.
4. Each meter shows its target: a **gold zone** (swish) inside a **green zone** (in). Press **STOP**
   (or **Space**; **R2** / **X** on a gamepad) while the aim marker is in the zone, then again for the
   power bar. A stopped marker turns gold, green or red. Your paper ball arcs to where it lands, a big
   banner shows the result, then your coworker throws.
5. The zones move with the bin's distance (far bins need more power) and the breeze.
6. The **X** asks first: ▶ Keep playing or 🚪 Quit (no reward).

The meters sweep in 1.2 s (aim) and 1.05 s (power) one way across (`PaperTossConfig`; slowed from
0.9 / 0.8 on 2026-10-11 after owner feedback that the toss was hard to control). The zones are drawn
from the round the client already knows; the server still judges every throw.

| Result | How close to the ideal throw | Points |
|---|---|---|
| 🎯 Swish | within 0.05 | 3 |
| ✅ In | within 0.11 | 2 |
| 😬 Off the rim | within 0.15 | 0 |
| ❌ Miss | further | 0 |

Most points after 5 rounds wins; equal is a tie (no reward).

## Coworkers and rewards (`PaperTossConfig.Opponents`)
| Coworker | Accuracy (spread) | Win reward (first win today ×2) |
|---|---|---|
| Intern Izzy | 0.09 | 40 coins · 120 XP |
| Manager Max | 0.065 | 80 · 260 |
| CEO Cora | 0.045 | 150 · 500, and the first win each day also an office supply |

Up to **10 rewarded wins a day** (UTC). Your best score is saved and shown.

## Safety and data
- The client sends an opponent number, then two meter readings (0..1) per throw; the server makes the
  rounds, judges the throw, throws for the CPU and pays. Throws must be at least 1.2 s apart.
- The meters are drawn on the client, so a cheater could send perfect throws; the rewards are small and
  capped per day, so it isn't worth it (documented trade-off).
- Player data v20 `PaperToss`: opponents beaten, best score, today's wins, total wins.
