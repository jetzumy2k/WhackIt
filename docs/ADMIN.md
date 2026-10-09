# Admin panel

Added 2026-10-06. Admins get a purple **Admin** button above the Store button, or press **F2**. The panel
(redesigned 2026-10-07, `Lib/PanelKit`) is a wide window with a sidebar (a tab strip on top on
narrow screens and phones): **Dashboard, Players, Bosses, Events, Drop Rates, Announce, Rewards,
History, Moderation** (Events, Announce, Rewards and History added 2026-10-08). Each page is a
set of cards; some long ones start folded (click a card's title to open or fold it). Pages scroll
instead of shrinking their text, and keep their scroll position when the server sends an update.
Close with X or F2. Admins can also open it from the Player Panel's Game page.

**Dashboard** (read only): server players / max, uptime, place version and server id; custom
bosses in use, how many players have admin damage, the current buff drop chance (Lucky or normal);
and everyone in the server with their level and score, each with **Manage** (opens Players with
them selected) and **Moderate** (opens Moderation with them selected). Store opening hours
stay in the Store panel's Admin tab (docs/STORE.md).

**Who is an admin** (`Lib/AdminAuth`, one rule for the whole game): the experience owner (or the
owner of the group that owns it), every UserId in `StoreAdminConfig.AdminUserIds`, and in Studio
playtests the local tester while `StoreAdminConfig.StudioTesterIsAdmin` is on. The server checks
this on every request; the panel being visible means nothing to the server.

Every accepted action prints an `[Admin] <name> (<id>) ...` line in the server log. Remote payloads
and checks are in docs/REMOTE_CONTRACTS.md ("Admin remotes"). Limits are in
`src/server/config/AdminConfig.luau` and `src/config/CustomBossConfig.luau`.

## Your boss access: bypass (Players tab, 2026-10-08)
**Turn bypass ON** opens every office door and lets you fight every boss, including the CEO through
the Executive Elevator, whatever your level or unlocks. It's for you only and lasts this session.
Your saved progress isn't changed, and normal players keep the normal requirements. The server keeps
its own flag (`BuffService.hasBossBypass`), and both the hit check (`CombatService`) and the elevator
(`ExecutiveService`) ask it. The client only reads the `AdminBypass` attribute to draw the doors open.

## Players tab
Pick anyone in your server with the `<` `>` arrows (yourself by default).

| Tool | What it does | Saved? |
|---|---|---|
| Set level | Sets XP to the minimum for that level (1 to 500). Lowering a level can re-lock Senior bosses unless they're admin-unlocked. Score and the leaderboard are untouched. | Yes |
| Set damage | Every hit does exactly that much damage (no crits, ignores boss toughness). **Hits with admin damage earn nothing**: no score, coins, XP, unlocks or buff drops for that boss life, and the Victory Card says so. "Normal" (or 0) turns it off. | No: ends when the player leaves |
| Unlock / Remove unlock | Opens one boss for that player even without the defeats or level it needs. "Unlock all" opens every boss including the CEO and the Executive Floor. "Reset admin unlocks" removes only admin unlocks; unlocks the player earned stay. | Yes (`AdminUnlocks`, schema v5) |

## Bosses tab: custom bosses
**Fictional everyday annoyances only.** The content rules in CLAUDE.md apply: no real people,
public figures, protected groups or real-world conflicts. Names go through Roblox text filtering
and a filtered (changed) name is refused.

- **Create boss here:** name (1 to 30 characters), look (the model, colours and shouts of one of the
  10 office bosses), **respawn** (see below), HP (10 to 1,000,000), score reward (0 to 10,000) and
  coin reward (0 to 2,000).
  The boss appears **where you stand**: the server finds the floor under your character. It must be
  at least 14 studs from every other boss, so one swing can't reach two.
- **Move here** moves it to where you now stand. **Delete** removes it (click twice to confirm).
- Up to 20 custom bosses. They're saved in DataStore `CustomBosses` and show up in **every server**
  within a few seconds (MessagingService), or within 5 minutes if a message is missed.
- **Respawn** (added 2026-10-07):
  - **Respawns** (`Continuous`): back at full HP 5 s after every defeat, like the office bosses.
  - **One time** (`Once`): the first defeat in **any** server ends it. It's saved as defeated, no
    server spawns it again, and the list shows it as "defeated". A server that was already fighting
    it when another server won may still finish that fight (and reward it). A defeated boss still
    uses one of the 20 slots until you **Delete** it.
  - Bosses saved before this option existed keep respawning.
- In the game they're open to everyone, take normal damage, and share score and coins by damage like
  any boss. They don't count toward unlocking office bosses.
- **Buff drop:** every player who dealt at least 10 % of its HP gets one random 30-minute store
  boost **in their Bag**, picked evenly from the boost strengths the store sells (each XP / Damage /
  Crit Damage strength with a Developer Product id; all of them if none is on sale yet). They use it
  when they like, like a bought one. The Victory Card shows
  "BONUS DROP: +10% XP boost (30 min), in your Bag!".

Note: high score or coin rewards on an easy custom boss let players farm Score, which also feeds the
global leaderboard. Keep rewards in line with the office bosses (docs/GAMEPLAY_RULES.md).

## Drops tab: office boss buff drops
Added 2026-10-07. Sets the chance that beating an **office boss** drops a random 30-minute store boost
into each qualifying player's Bag (custom bosses always drop one). Chances are probabilities from 0 to 1
(0.30 = 30 %); each roll uses a random chance between Min and Max of the range in effect.

| Field | Default | Meaning |
|---|---|---|
| Normal Min / Max | 0.0005 / 0.10 | chance range most of the time |
| Lucky Min / Max | 0.10 / 0.30 | chance range during the Lucky window |
| Every (minutes) | 120 | how often the Lucky window starts, counted in UTC from midnight (10 to 1440) |
| Lasts (minutes) | 10 | how long it stays on (1 to Every - 1) |

The tab shows whether the Lucky window is on now and how long until it changes. **Save for all
servers** stores the values in DataStore `DropRates` and every server picks them up within seconds
(or within 5 minutes if a message is missed). **Reset to defaults** (click twice) goes back to
`src/config/DropRateConfig.luau`. In Studio without API access, saving fails with a toast.

## Events tab (2026-10-08)
Create, schedule, stop and review events that run in **every server**: XP events, outdoor boss
events, boss drop events and Hammer Shop sales. Full rules are in docs/EVENTS.md.
- **Running and scheduled:** each event with its status, what it does, its times in your local time
  and a countdown, and **Edit**, **Start now** (scheduled), **Stop** / **Cancel** and **Force remove**,
  each confirmed with "…?" [Cancel] [Confirm] (docs/EVENTS.md "Admin actions"). There's also an
  **Egg Hunt** type for scheduled egg spawning (docs/PETS.md).
- **Create event:** type, optional name (filtered; left empty, the server names it, for example "2X
  EXPERIENCE"), **Start now** for a preset length or **Schedule** with start and end, then the type's
  settings. Several events can run together; same-kind events never stack (the highest XP
  multiplier and the biggest discount apply).
- **Event history** (folded): the last 20 events that ended: what each did, start, actual and planned
  end, how long it ran, who created it, status (Completed / Stopped / Cancelled / Removed), who
  stopped it and when, and **Delete**.
- **World eggs** (pets, docs/PETS.md): when the next scheduled egg is due and how many are out in
  this server. **SPAWN EGG NOW** places one (Common, Rare or Mythical) at a random safe spot in
  **this** server and announces it. There are no admin tools for players' pets or eggs.

## Announce tab (2026-10-08)
Type a message (one line, up to 200 characters), pick how long it shows (5, 10, 15 or 30 s) and
**SEND ANNOUNCEMENT**. Everyone in **this server** sees a "📢 ANNOUNCEMENT" card at the top-centre
of their screen. It closes on its own or with OK, works on phones, and never covers the whole
screen.
- The server cleans the text (one line; invisible and control characters removed), then Roblox's
  text filter runs once and **each player gets the version filtered for their own account**
  (`GetNonChatStringForUserAsync`). Normal messages arrive as typed; words Roblox blocks for a
  player (stricter for under-13 accounts) show as ### for that player only. Roblox requires this
  filtering for any text one user shows to others, so it can't be turned off in a live game.
  Markup isn't interpreted.
- **Studio playtests** show the message exactly as typed: only you and your testers see it, and
  Studio's filter hashes nearly everything. The same goes for custom boss and event names typed in
  Studio; in a live game those are still checked by the strict all-ages filter and refused if it
  changes them, because every player sees the same name.
- One announcement per admin every 10 s (`AdminConfig.AnnouncementCooldownSeconds`), on top of the
  normal admin rate limit.
- Non-admins firing `Admin.Announce` are rejected and logged; nothing is shown.

## Rewards tab (2026-10-08)
Give a player **in this server** something the game already has:

| Reward | Limits | Goes to |
|---|---|---|
| Coins | 1-100,000 | `SessionService.addCoins` (leaderstats too) |
| XP | 1-10,000,000 | `SessionService.addXp` (level-ups and bonuses as usual) |
| Store item | 1-50 of any store item: boost, bundle (as its boosts), egg, Mystery Hammer | the player's **Bag** (`BagRules.grant`) |
| Hammer | any coin hammer they don't own yet | `OwnedHammers` |
| Pet | any species; its buffs are rolled like a hatched pet's | `PetService.grantPet` (first pet is equipped) |

Optional **reason** (one line, up to 100 characters, admins only). **GIVE REWARD** asks "Give … to
…?" first. The server re-checks admin rights, the target, every limit and the catalogues
(`AdminService.onReward`), and the player gets a toast. Every reward, and every failure (for example
"already owns that hammer"), is written to the admin log and to the player's history with date and
time, admin, target name and UserId, type, amount and item, reason and status. Offline players can't
be rewarded yet (their data is only safe to change on the server that holds it).

## History tab (2026-10-08)
- **A player's history:** pick someone in the server, or type any username (offline players too).
  Filter by type (admin actions, purchases, boosts used, items opened, eggs, pets, event rewards)
  and period (24 h, 7 days, 30 days, all). Press **LOAD**, then page with **< Newer / Older >**
  (20 per page, newest first).
- **Admin log:** every admin action on a UTC day (today, yesterday, up to a week back), filterable
  by action (rewards, events, set level and damage, unlocks, bypass, other).

What's recorded (`Services/HistoryService`), all on the server:
- admin rewards and every admin action;
- Robux purchases and gifts, with product and purchase id;
- boosts used;
- Mystery Hammers opened and bundles unpacked;
- eggs found and incubated;
- pets hatched, equipped and put away;
- items won from drop events.

Boss hits and defeats aren't recorded: there are far too many, and the leaderboard and save already
track progress.

Storage: DataStore `PlayerHistory`. Each player gets their last 200 entries (`Player_<UserId>`), and
admin actions go in one key per UTC day with up to 500 entries (`Admin_<YYYYMMDD>`), so no key grows
without limit. Writes are queued and saved every 30 s and on shutdown. Reads include anything still
queued. In Studio without API access, history stays in that server.

## Moderation tab
Bans use Roblox's own ban system (`Players:BanAsync`), so they:
- apply to **every server** of the experience and kick the player right away;
- also catch their **alt accounts**;
- only work in a **published** game (in Studio the panel shows "Ban failed").

| Field | Notes |
|---|---|
| Player | Someone in your server, or type a **username** (it wins when filled in) to ban someone offline |
| Length | 1 hour, 1 day, 3 days, 7 days, 30 days (a suspension) or Permanent |
| Reason | Shown to the banned player. Only fixed texts: Cheating or exploiting, Harassing other players, Inappropriate behavior, Breaking the game rules |
| Note | Private, up to 200 characters, kept in the ban history in the Creator Hub, never shown to players |

You can't ban yourself, the owner or another admin. **Unban** lifts a ban early. Ban history is also
visible in the Creator Hub (your experience, Moderation).
