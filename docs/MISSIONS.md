# Team Missions

Added 2026-10-10 (major update Phase 5b, `docs/MAJOR_GAME_UPDATE.md` §10; decisions D11-D13 in
`docs/UPDATE_IMPLEMENTATION_PLAN.md`). A team of 2-4 players goes to a mission room and clears a short
chain of boss waves before the clock runs out. The bosses are the usual fictional annoyances; they
never attack and nobody takes damage.

Code: `Config/MissionConfig` (missions, waves, numbers), `Shared/MissionRules` (boss health and ids,
placement, who counts, the daily cap, the saved record; unit-tested), `Lib/MissionRoomBuilder` (the
rooms), `Services/MissionService` (teams, runs, rewards), `Services/BossService` (mission bosses),
`Controllers/MissionController` (cards, the window, the mission bar, the result card).

## Missions (provisional)
| Mission | Waves (bosses × health, for 2 players) | Time |
|---|---|---|
| ☕ Monday Survival | 2 × Snoozed Alarm (300) → 2 × Kick-off Meeting (450) → The Monday Monster (1,500) | 10 min |
| 📧 Reply-All Storm | 3 × Reply-All (250) → 3 × Reply-All Reply (350) → The Inbox Overflow (1,600) | 10 min |

Health scales with the team: +40 % per player above 2 (3 players ×1.4, 4 players ×1.8). The bosses
borrow existing boss looks and shouts.

## Playing
1. 🏢 **Social → 🤝 Team Missions** → **Open a team** for a mission. Everyone else gets a card
   "🤝 <name> needs a team for ☕ Monday Survival!" with **JOIN** (Settings → *Hide challenge notices*
   hides these too), and the team is listed in the window.
2. With 2+ players the leader presses **Start mission**; a full team (4) starts by itself. A team
   closes after 2 minutes if it doesn't start. If all 3 rooms are busy, try again in a moment.
3. The team is teleported to a mission room. After 5 s the first wave appears. Defeat every boss of a
   wave; the next comes 4 s later. A bar at the top shows the wave, the bosses left, the time and
   everyone's hits; **Leave mission** (two taps) goes back to the lobby.
4. After the last wave (or when time runs out) everyone sees the result and goes back to the lobby 8 s
   later.

Only the team can hit its bosses (the server refuses anyone else's hits). Each boss defeat pays the
normal boss rewards (score, coins, XP, stress relief, the usual drop chance) and counts for quests and
the Event of the Day like any defeat. A reset character is put back in the room. A player in a team or
mission can't start pickleball or go to an office, and the other way round.

## The mission reward (cleared missions only)
| | |
|---|---|
| Coins | 400 |
| XP | 1,000 |
| Office supply | one roll (winners' pool) |
| Pet egg | 20 % chance of a Common Egg into the Bag |

- **Who counts:** players still in the room with at least **5 hits** on the mission's bosses and at
  least **a quarter of the team's average** hits. Hits, not damage, so a low-level player swinging as
  often as a high-level one counts the same, and standing around doesn't.
- **Daily cap:** 3 rewarded missions per player per UTC day. After that missions are for fun (boss
  rewards as usual, no mission reward). Players are told why on the result card.
- A player who leaves gets nothing more from the run; the others carry on.

## Security (docs/REMOTE_CONTRACTS.md "Mission")
Clients send a mission id (open), a team id (join) or nothing (leave, begin). Hits are counted from the
server's own accepted hits (`BossService.onHit`), defeats from `BossService`; the reward is paid once
per run per player by the server. Every remote is validated and rate-limited; the last team place is
taken without yielding.

## Saved data (schema v15, docs/DATA_SCHEMA.md)
`Missions = { DayKey, DayRewarded, Cleared }`.

## Performance
3 static rooms far from the campus (about 8 parts each). Bosses only exist during a run. Hit counts go
to the team at most every 2 s, and only when they changed. No per-frame work on the server; the client
updates its bar once a second.
