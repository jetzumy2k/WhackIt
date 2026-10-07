# Admin panel

Added 2026-10-06. Admins get a purple **Admin** button above the Store button, or press **F2**. The panel
(redesigned 2026-10-07, `Lib/PanelKit`) is a wide window with a sidebar (a tab strip on top on
narrow screens and phones): **Dashboard, Players, Bosses, Drop Rates, Moderation**. Each page is a
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
