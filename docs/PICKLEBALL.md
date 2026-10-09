# Pickleball

Added 2026-10-10 (major update Phase 4, `docs/MAJOR_GAME_UPDATE.md` §21.1-21.2, decisions D3-D6 in
`docs/UPDATE_IMPLEMENTATION_PLAN.md`). Players challenge each other to standard pickleball at the
Recreation Center, for coins, office supplies and a seasonal rating. Nobody hits anybody: it's a ball
game between players, in the same cartoon style as the rest of the campus.

Code: `Config/PickleballConfig` (every number), `Shared/PickleballRules` (scoring, line calls, faults,
rating, caps, supplies; unit-tested), `Shared/BallFlight` (the ball's path; unit-tested),
`Lib/CourtBuilder` (the center), `Services/RecreationService` (challenges, matches, rewards),
`Controllers/PickleballController` (cards, panel, score bar, controls, the ball).

## The Recreation Center
- North of the office building, x -60..60, z -200..-140 (decision D3). The campus boundary moved from
  z -130 to z -210 to make room; a walkway runs north from the loop behind the building. Skyline blocks
  that would now stand on the grounds aren't built (the others stay exactly where they were).
- **Two courts** side by side (centres x ±24, z -170), each 20 × 44 studs with 7-stud kitchens, a net
  (34-36 in), a 7-stud run-off with a low fence, benches on the outer side and a board at the far end
  showing the match. An invisible wall in the net's plane keeps everyone on their own side.
- **The sign** between the courts, with a "Pickleball" prompt (E), opens the Pickleball panel.
- About 30 anchored parts per court; nothing moves, so the center costs nothing per frame.

## Finding a match
| Step | What happens |
|---|---|
| Challenge | Pickleball panel → **Challenge: Singles** or **Challenge: Doubles**. You need the 10-coin fee (not charged yet), no other challenge or match, and 30 s since your last challenge |
| Notice | Everyone else gets a card "🏓 <Name> wants a Singles match!" with **ACCEPT** (Settings → *Hide challenge notices* turns the cards off), and a "🏓 n OPEN" chip top-left opens the panel |
| Accept | Singles: the first to accept plays. Doubles: **Join A** or **Join B** (the card's ACCEPT takes any free place); it starts at 4. Two players can't both get the last place |
| Expiry | 60 s for singles, 90 s for doubles; the challenger can cancel, joiners can leave |
| Courts | When full, the match starts on a free court; if both are busy it waits in line ("#1 in line") |

The panel is also on 🏢 Social → 🏓 Pickleball. It has three tabs: 🏓 Play (your rating and record,
start a match, open challenges), 📖 How to play and 🏆 Prizes.

## A match
- At the start everyone pays the fee and is moved onto the court; the hammer is put away and a
  paddle handed over; everyone walks at 18 (no sprint). Office trips are refused until it ends.
- **Controls:** click / tap 🏓 / R2 swings; Q / **Soft** / L2 hits softly (dinks and lobs); E / **Hard** /
  R1 drives. Aim with the mouse at a spot on the other side (touch and controllers aim where the
  camera looks). A yellow ring shows where the ball will bounce.
- **The score bar** (bottom centre) shows both sides' points, the called score ("3-5" or "3-5-1"), who
  serves, what just happened ("Into the net! Side out.") and the time left. **Forfeit** (top right)
  needs two taps.
- Players are put back in place before every serve. An idle server serves automatically after 15 s.

### Rules (standard pickleball, §21.1)
- One game to **11, win by 2**; only the serving side scores.
- The serve goes diagonally, past the kitchen and its line. Singles: from the right on an even score,
  from the left on an odd one. Doubles: both partners serve before a side-out, except the first
  serving team ("0-0-2"); the serving pair switch courts after each point; the score is called serving
  team, receiving team, server number. The receiver stands diagonally opposite the server.
- **Two-bounce rule:** the serve and its return must each bounce before being hit.
- **Kitchen:** no volleys while standing in it (its line counts as in it). A bounced ball may be hit there.
- **Faults:** into the net; out (a ball on a line is in; a serve on the kitchen line is a fault); a
  serve into the wrong court; two bounces; a volley that breaks the two-bounce or kitchen rule.
- Simplified for the game: either partner may return a serve that lands in the right court (players
  are placed so the correct receiver stands there), and a ball the server can't serve within 15 s is
  served for them.

### The ball (server-owned)
The server works out every shot: the aim (clamped to the other side; a serve to the diagonal service
court), a speed from the power (14-48 studs/s along the ground), and a spread: up to 1.5 studs for a
hard shot plus up to 4.5 for a stretched one (the ball 3-6 studs away). The path is plain physics
(gravity 40; a bounce keeps 80 % of the vertical and 85 % of the horizontal speed), so the server and
every client compute the same path from four numbers (`Rec.Shot`). Line calls, the net, the bounces
and the score are the server's alone. A hit counts only from the side the ball is on, with the ball
within 6 + 1.5 studs horizontally and at most 9 up, checked when the swing arrives and up to 0.2 s
before (players see the ball a little late). A swing that misses changes nothing.

### Leaving
- Before the first point: the match is cancelled and every fee refunded.
- After it: the leaver's side loses (a doubles partner may play on alone, always placed to serve or
  return, or forfeit). The leaver gets no coins or supply, and the loss counts for their rating; it's
  saved just before their data is released (`PlayerDataService.beforeRelease`).
- Forfeit works the same, but the player stays in the game.
- 20-minute limit: the side ahead wins; a tie is cancelled with refunds.

## Prizes
| | Singles | Doubles (each player) |
|---|---|---|
| Entry fee (at the start) | 10 coins | 10 coins |
| Winner | 60 coins | 60 coins |
| Loser | 20 coins | 20 coins |
| Office supply | one roll each (below) | one roll each |

The fee is a coin sink, not a pot: no coins pass between players. **Caps:** 10 rewarded matches per
player per UTC day, and 3 against the same opponents. After that a match is **friendly** (no fee, coins,
supply or rating change) for everyone in it; players are told when it starts.

**Office supplies** (Special furniture, `PickleballConfig.Supplies`; docs/OFFICES.md):

| Item | Winners | Losers |
|---|---|---|
| Paddle Rack | 24 % | 34 % |
| Ball Bucket | 24 % | 34 % |
| Standing Fan | 20 % | 22 % |
| Mini Fridge | 14 % | 7 % |
| Zen Bonsai | 8 % | 3 % |
| Snack Machine | 5 % | - |
| Neon CALM Sign | 4 % | - |
| Golden Hammer Trophy | 1 % | - |

## Rating and seasons
- **Elo** (decision D5): everyone starts each season at 1000, K = 32. In doubles each player's change
  uses their team's average against the other team's. An even match moves both sides by 16.
- **Seasons** (decision D6): 4 weeks, starting Mondays 00:00 UTC. A new season resets the rating and the
  season's wins and losses; all-time totals stay.
- **Not built yet (Phase 4b):** the seasonal leaderboard (an ordered DataStore per season) and the
  top-10 season prizes. The saved data already holds what they need (`Recreation.SeasonId`,
  `SeasonClaims`), so they need no new migration.

## Security (docs/REMOTE_CONTRACTS.md "Rec")
Clients send a mode, a challenge id and a team, or an aim and a power; never a position, a score, a
fault, a winner or an amount. Every remote is rate-limited; seats are taken without yielding; rewards
are paid once per match id (`ProcessedMatches`); swings from players the movement guard flags are
ignored. The ball is drawn by the client but called by the server.

## Saved data (schema v12, docs/DATA_SCHEMA.md)
`Recreation` (rating, season, wins and losses, today's counters), `ProcessedMatches`, `SeasonClaims`.

## Performance
- Server: no per-frame work. Each shot schedules at most three timers (net, bounce, second bounce);
  the court guard checks positions twice a second, only on courts with a match.
- Client: one RenderStepped connection, only while a ball is moving; it disconnects itself.
- Network: one small message per shot to everyone, and state messages to the players at each serve
  and rally end. **Not yet measured** (deferred performance baseline, `docs/UPDATE_TEST_PLAN.md` B4).
