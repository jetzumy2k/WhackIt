# Office Showcase

Added 2026-10-10 (major update Phase 6a, `docs/MAJOR_GAME_UPDATE.md` §11 Feature G; owner decisions
D17 and D20 in `docs/UPDATE_IMPLEMENTATION_PLAN.md`). Players share a snapshot of their personal office
(docs/OFFICES.md) with players in **every** server. Anyone can open a read-only copy, even while the
owner is offline, like it and report it. Weekly design contests (D18/D19) are Phase 6b.

Code: `Config/ShowcaseConfig`, `Shared/ShowcaseRules` (pure, unit-tested), `Lib/ShowcaseStore`
(DataStores, or a store in this server only), `Services/ShowcaseService`, `Controllers/ShowcaseController`,
the 🌟 Office Showcase section on the Social page (`PlayerPanelController`).

## For players
- **Open it:** 🏢 Social → 🌟 Office Showcase → **Open the Showcase** (or **My showcase**).
- **Tabs:** ⭐ Featured (picked by the moderators), 🆕 Newest, ❤️ Top this week (likes since Monday
  00:00 UTC), 🏢 My showcase. Each office is a card: the owner's avatar and name, how many pieces of
  furniture, ❤️ likes, 👀 visits, and **Visit**.
- **Visit:** you're taken to a copy of the office as it was when it was shared, with its theme. A bar
  at the bottom shows whose office it is, **❤️ Like**, **🚩 Report** and **🚪 Lobby** (the door works
  too). Nothing in a copy can be moved or taken.
- **Like:** once per office, while you're in it.
- **Share yours:** My showcase → **Share my office**. Needs Level 5 and at least 5 pieces of furniture.
  **Update** copies your office as it is now (every 5 minutes at most); likes and visits stay. **See it**
  opens your own copy; **Take my office out of the Showcase** hides it again.
- What others see: your furniture, your office theme and your Roblox display name. There is no
  player-typed text anywhere.

## Moderation (D20)
- **🚩 Report** asks for a reason (Inappropriate shapes or layout, Mean or offensive, Spam or empty,
  Something else). The office is hidden **for the reporter at once**, for good.
- When **3 different players** report an office it goes to **review**: hidden for everyone except its
  owner and admins. An office an admin approved needs **6** new reports.
- **Admins:** a 🛡️ Review tab lists offices in review (with the number of reports). Visit one and a
  second bar offers **✅ Approve** (shown again, reports cleared), **🗑️ Remove** (taken down, visitors
  sent out; the owner can't share again for 7 days, and then it waits for review), **⭐ Feature** and
  **Unfeature** (the Featured tab, 12 offices). Every action is in the admin history (Admin → History,
  action "Showcase"); reports are logged on the server.
- Sharing again never clears reports or a review.

## How it works
- **Snapshot** (DataStore `OfficeShowcase`, key `Office_<UserId>`): version, owner id and display name,
  the layout (copied from saved data on the server, never from the client), the theme id, published flag
  and time, likes, visits, moderation (`Ok` / `Review` / `Removed`), approved, the last 20 reporters,
  when it was removed. Every change is one `UpdateAsync`. Loading checks every field
  (`ShowcaseRules.sanitizeSnapshot`); furniture that can't stand where it is is dropped.
- **Lists** (OrderedDataStores keyed by UserId): `Showcase_Newest` (publish time), `Showcase_Top_<week>`
  (likes that week), `Showcase_Review` (time it went to review); `Featured` is a list in the snapshot
  store. A page asks for twice the page size (18) and drops hidden ones.
- **Budgets:** pages are cached 60 s and snapshots 120 s per server. Likes and visits are added up
  in the server and saved every 60 s (and at shutdown). A visit counts once per player per office per
  server session, as does the quest/event activity `VisitOffice`.
- **Copy rooms:** 8 rooms in a row at (2000, 300, 120), 60 studs apart, beside the Office Wing and
  outside every office slot. The same room serves everyone looking at the same office; a room nobody
  has stood in for 30 s is cleared. All full: "The Showcase is busy".
- **Studio:** with API access off the service uses a store in that server only (`ShowcaseStore.memory`)
  and the gallery says "Studio test". With API access on, Studio uses the real stores.

## Settings (`Config/ShowcaseConfig`)
| Setting | Value |
|---|---|
| MinLevel / MinItems | 5 / 5 |
| PublishCooldown | 5 min |
| PageSize / MaxFeatured | 18 / 12 |
| HideAfterReports | 3 (×2 once approved) |
| RemovedBlockSeconds | 7 days |
| MaxLiked / MaxHidden (saved per player) | 300 / 100 |
| MaxRooms / RoomIdleSeconds | 8 / 30 s |
| ListCacheSeconds / SnapshotCacheSeconds / FlushInterval | 60 / 120 / 60 s |

## Not in 6a
- Contests, votes and prizes (6b), several saved layouts per player, showcase cards to share (Feature H).
- A picture of the office in the gallery card (the card shows the owner's avatar).
- Reasons per report are logged, not stored on the snapshot.
