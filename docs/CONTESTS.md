# Office Design Contests

Added 2026-10-10 (major update Phase 6b, `docs/MAJOR_GAME_UPDATE.md` §11 Feature G; owner decisions
D18 and D19 in `docs/UPDATE_IMPLEMENTATION_PLAN.md`). Every week has a theme; players enter with their
office, everyone votes, and the best designs win trophies. Built on the Office Showcase
(docs/SHOWCASE.md): entries are snapshots, shown in the same read-only copy rooms, with the same
reports and moderation.

Code: `Config/ContestConfig`, `Shared/ContestRules` (pure, unit-tested), `Services/ContestService`,
`Controllers/ContestController` (the 🏆 Contest tab and the star bar), the copy-room hooks in
`Services/ShowcaseService` (`registerKind`), three prize items in `Config/FurnitureConfig`.

## The week (UTC)
| Days | What happens |
|---|---|
| Monday-Friday | **Entries.** 🏆 Contest → **Enter with my office**: a copy of your office as it is now (Level 5, at least 5 pieces of furniture). **Update my entry** any time (every 5 min at most); votes can't exist yet. |
| Saturday-Sunday | **Voting.** **⭐ Vote now** takes you to a random entry. A star bar shows ⭐1-⭐5 (after 5 seconds of looking) and **⏭️ Next**. |
| Monday 00:15 | **Results** frozen; prizes paid when entrants join (or within 5 minutes if they're online). |

## Themes (rotate weekly, `ContestConfig.Themes`)
| Theme | Furniture that fits |
|---|---|
| 🧘 Zen Retreat | Small Plant, Tall Plant, Round Rug, Floor Lamp, Bean Bag, Zen Fountain, Aquarium, Zen Bonsai |
| 💻 Tech Startup | Computer Desk, Server Rack, Big Screen TV, Standing Desk, Whiteboard, Printer, Arcade Machine, Bean Bag |
| ☕ Cozy Café | Coffee Station, Sofa, Lounge Chair, Office Rug, Floor Lamp, Small Plant, Mini Fridge, Snack Machine |
| 🕹️ Game Room | Arcade Machine, Big Screen TV, Bean Bag, Sofa, Giant Stress Ball, Snack Machine, Neon CALM Sign, Mini Fridge |
| 👔 Executive Suite | Office Chair, Bookshelf, Filing Cabinet, Office Rug, Coat Rack, Executive Desk, Golden Hammer Statue, Golden Hammer Trophy |
| 🏓 Sports Club | Water Cooler, Giant Stress Ball, Motivational Poster, Big Screen TV, Coat Rack, Paddle Rack, Ball Bucket, Champion Plaque |

Every theme has at least 4 free (Basic) items, so the full theme bonus never needs rare furniture.
The Contest tab ticks the theme items your office already has.

## Fair voting and scoring (D19)
- You only rate entries **dealt to you at random**: not your own, not ones you voted for this week,
  not ones you hid by reporting. You can't pick a friend's entry.
- **30 entries a day**, and every dealt entry uses one, voted or skipped, so skipping until a friend's
  entry appears doesn't work. Each entry once per week. Level 5+ to vote.
- You must be inside the entry for **5 seconds** before the stars work, and the vote only counts for
  the entry dealt to you while you stand in it.
- **Score** = a fair (Bayesian) average of the stars, as if every entry started with 5 votes of 3 stars,
  so a few 5-star votes from friends can't beat many honest votes, **plus a theme bonus** of up to
  +0.5 stars: different theme items used ÷ 4, worked out by the server from the entry's furniture.
- Entries need **3 votes** to be ranked. Reported entries in review don't get dealt and can't place.

## Prizes (`ContestConfig.Prizes`)
| Place | Coins | XP | Furniture (Trophies) |
|---|---|---|---|
| #1 | 2,000 | 3,000 | Design Star Trophy |
| #2-3 | 1,000 | 1,500 | Top Design Plaque |
| #4-10 | 500 | 800 | Design Ribbon |
| Everyone else who entered | 150 | 300 | none |

An entry a moderator removed gets nothing. Prizes are paid once (saved `Contest.Claimed`), up to 3
finished weeks back. Last week's top 3 show in the Contest tab with **Visit**.

## Moderation
As in the Showcase: 🚩 Report in an entry hides it (and that player's showcase office) for you and,
after 3 reporters, puts it in review. Admins see contest entries in the 🛡️ Review tab ("🏆 … Entry")
and can **Approve** or **Remove** from the entry's copy (Feature is for the Showcase only). Actions are
in the admin history (action "Contest").

## How it's stored
- DataStore `DesignContest`: `Entry_<week>_<UserId>` (a Showcase snapshot + week, theme id, theme fit,
  votes, star sum; every change one `UpdateAsync`), `Results_<week>` (the top 10, frozen once, only
  if missing).
- OrderedDataStores `Contest_Entries_<week>` (entry time), `Contest_Score_<week>` (score × 10,000 once
  ranked), `Contest_Review_<week>`.
- Votes are added up per server and saved every 60 s (and at shutdown).
- Player data v17 `Contest`: weeks entered, prizes paid, this week's voted entries, today's dealt count.

## Testing in Studio
With API access off, entries and votes stay in that server ("🧪 Studio test"). Admins in Studio get a
**⏩ Next phase** button in the Contest tab that moves that test server's contest clock forward:
entries → voting → the next Monday after the results freeze (prizes are checked right away). It is
refused in a live game. With only a couple of test players no entry reaches 3 votes, so everyone gets
the participation prize.

## Not in 6b
- Contest titles or nameplate frames (the prizes are furniture, coins and XP).
- Sharing a contest result card outside the game (Feature H).
- A per-theme leaderboard history beyond last week's top 3.
