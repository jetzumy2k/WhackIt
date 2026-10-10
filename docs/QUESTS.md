# Quests

Added 2026-10-10 (major update Phase 2b, `docs/MAJOR_GAME_UPDATE.md` §7; decisions D7-D9 in
`docs/UPDATE_IMPLEMENTATION_PLAN.md`). Light little jobs around the office that point players at
everything the game has (bosses, Zen, offices, pickleball, pets), with coins, XP and office supplies.

Code: `Config/QuestConfig` (every quest and number), `Shared/QuestRules` (windows, drawing, counting,
claims, saved-state checks; unit-tested), `Services/QuestService` (counting, claims, rewards),
`Controllers/QuestController` (the button, the window, the reward card).

## What players see
- A **📋 Quests** button at the end of the HUD column, with a red badge counting quests ready to claim.
- A "📋 Quest complete: … Claim it in 📋 Quests." toast when one finishes.
- The **Quests** window:
  - **📅 Daily:** 3 quests, the time to the next reset (00:00 UTC), **🎲 Swap quest** on an unfinished
    one (once a day), and **🎁 All three done**: a bonus for claiming all three.
  - **🗓️ Weekly:** 3 bigger quests, reset on Mondays 00:00 UTC (the same day pickleball seasons start);
    each also gives an office supply.
  - **🎓 Getting started:** a 4-step chain, one step at a time.
- **Claim!** pays and shows a "📋 QUEST COMPLETE!" card with the coins, XP and any office supply.

## Quests (`Config/QuestConfig`, all provisional)
| Getting started | Coins | XP |
|---|---|---|
| 1. Whack your first boss | 50 | 150 |
| 2. Bring your Stress Meter down to 0 (Zen) | 100 | 300 |
| 3. Place a piece of furniture in your office | 100 | 300 |
| 4. Defeat 5 more bosses | 200 | 600 |

Every step can be done alone (no pickleball or visiting, which need other players).

| Daily (3 drawn) | Coins | XP | Min level |
|---|---|---|---|
| Defeat 3 bosses | 120 | 300 | |
| Defeat 8 bosses | 220 | 600 | 3 |
| Reach Zen | 120 | 300 | |
| Reach Zen twice | 200 | 500 | 3 |
| Earn 400 coins from bosses | 120 | 300 | |
| Play a pickleball match | 150 | 350 | |
| Place 2 pieces of furniture in your office | 100 | 250 | |
| Visit another player's office | 100 | 250 | |
| **Bonus:** claim all three | 200 | 500 | |

| Weekly (3 drawn, + an office supply each) | Coins | XP |
|---|---|---|
| Defeat 40 bosses | 700 | 2,000 |
| Reach Zen 6 times | 600 | 1,800 |
| Earn 5,000 coins from bosses | 700 | 2,000 |
| Play 5 pickleball matches | 700 | 2,000 |
| Win 3 pickleball matches | 800 | 2,200 |
| Visit 3 other players' offices | 500 | 1,500 |
| Hatch a pet | 500 | 1,500 |

The office supply is a roll from the pickleball losers' pool (`PickleballConfig.Supplies.Loser`). Quests
needing other players can be swapped (daily) or left; the others always add up to a full set.

## Rules
- **What counts** (the server decides; clients never report progress):

  | Event | Counted by | When |
  |---|---|---|
  | DefeatBoss, EarnCoins | `CombatService` | a boss defeat you qualified for, and its coins |
  | ReachZen | `StressService` | a rewarded Zen (the same one that pays 100 coins) |
  | PlayMatch, WinMatch | `RecreationService` | a rewarded pickleball match (not a friendly one) |
  | PlaceFurniture | `OfficeService` | a piece placed in your office |
  | VisitOffice | `OfficeService` | arriving in another player's office |
  | HatchPet | `PetService` | a pet hatched |

- Progress stops at the target. A quest pays **once**: the claim marks it claimed before paying, in the
  session-locked saved data.
- **Resets:** a new day's or week's quests are drawn when a player joins, on any quest event or request,
  and once a minute for everyone in the server. A **finished but unclaimed** quest that a reset replaces
  is still paid ("Unclaimed quest rewards from the last reset were added for you."). Unfinished progress
  is lost at the reset.
- **Swap:** one unfinished daily quest a day, for one not already on the list (progress starts over).
- **Bonus:** once a day, after all three daily quests are claimed.
- Level requirements (`MinLevel`) keep the bigger daily quests away from brand-new players.
- XP from quests counts towards the Player Level like any XP (the level-up card and coins as usual).

## Security (docs/REMOTE_CONTRACTS.md "Quests")
Clients send only a kind and an index (claim) or an index (swap); both are validated and rate-limited.
Progress comes only from server results. Rewards are paid by the server from `QuestConfig`.

## Saved data (schema v13, docs/DATA_SCHEMA.md)
`Quests`: the day's and week's keys and quests (`{Id, Progress, Claimed}`), swaps used, the bonus, the
tutorial step and its progress. Existing players start at tutorial step 1.

## Performance
No per-frame work. One check a minute per server for resets; events change a few numbers and send at
most one `Profile.Sync` per player per frame.

## Later (Phase 2c)
New non-combat activities from §7: delivering coffee to NPC coworkers, collecting scattered office
supplies, sorting documents, a small IT puzzle. They add new events and quests here.
