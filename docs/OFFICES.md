# Personal Offices

Added 2026-10-09 (major update Phase 2a, `docs/MAJOR_GAME_UPDATE.md` §21.3). Every player gets an
open-plan office of their own to furnish, and can visit the offices of other players in the server.

Code: `Config/OfficeConfig` (room, wing, limits), `Config/FurnitureConfig` (furniture catalogue),
`Shared/FurnitureRules` (placement, layouts, privacy; unit-tested), `Shared/FurnitureModel` (builds
an item from its parts, server and client), `Lib/OfficeWingBuilder` (rooms), `Services/OfficeService`
(rooms, slots, edits, visits, guard), `Controllers/OfficeController` (bar, edit mode, directory),
`Controllers/PlayerPanelController` (Social page, 🏢 Social button).

## Where offices are
- **The Office Wing** is a row of rooms high above the map and far from it (x 2000+, y 300), out of
  sight of the campus. Players get there and back by teleport; nothing on the existing map moved.
- **One room per player place** in the server: `Players.MaxPlayers` rooms (Game Settings, 12
  recommended), at most `OfficeConfig.MaxSlots` (50). A player gets the first free room when their
  data loads; it's cleared and freed when they leave. If no room is free (a full server with more
  players than rooms) they get a toast and no office this session.
- **A room** is 40 × 40 studs inside, 14 tall: carpet, walls, a long window on the back wall, a ceiling
  with one soft light (brightness 0.8, no shadows), a closed door with a **Back to lobby** prompt (E),
  and the owner's name over the door. About 15 parts. Outside the room is only sky, so the door never
  opens.

## Getting there
| From | How |
|---|---|
| Anywhere | **🏢 Social** (HUD column) or Menu → **🏢 Social** → **Go to my office** |
| Another player's office | Social page → **Offices in this server** → **Visit** |
| Back | **🚪 Lobby** on the office bar, **Back to the lobby** on the Social page, or the door's prompt |

Arrivals stand just inside the door, facing into the room. Respawning always puts you in the lobby.
In an office, a bar at the bottom says whose office it is, with **✏️ Edit** (your own office only)
and **🚪 Lobby**.

## Furniture
41 items in seven categories (`Config/FurnitureConfig`), each a few plain parts (at most 12, no uploads):

| Category | Items |
|---|---|
| Desks & chairs | Desk, Big Desk, Standing Desk, Office Chair, Lounge Chair, Sofa, Bean Bag |
| Tech | Computer Desk, Printer, Server Rack, Water Cooler, Coffee Station, Big Screen TV, Arcade Machine |
| Plants & storage | Small Plant, Tall Plant, Filing Cabinet, Bookshelf |
| Decor | Round Rug, Office Rug, Floor Lamp, Whiteboard, Giant Stress Ball, Coat Rack, Motivational Poster |
| Level rewards | Executive Desk (Lv 20), Aquarium (Lv 30), Zen Fountain (Lv 50), Golden Hammer Statue (Lv 100) |
| Office supplies | Paddle Rack, Ball Bucket, Standing Fan, Mini Fridge, Snack Machine, Neon CALM Sign (pickleball drops) |
| Trophies | Golden Hammer Trophy, Zen Bonsai, Champion Plaque, Design Star Trophy, Top Design Plaque, Design Ribbon (design contest prizes, docs/CONTESTS.md) |

- **Basic** items are **free and unlimited** (owner decision 2026-10-09): no grind for basic
  furniture. Only the room's 60-item cap applies.
- **Level** items are level rewards (docs/GAMEPLAY_RULES.md "Level rewards"): free and unlimited from
  their level on; the strip shows "🔒 Lv 30" until then. Placed ones stay (and can be moved) if an admin
  lowers the level; new ones need the level back.
- **Special** items (Office supplies, Trophies) are owned in counts (`PlayerData.Furniture`). They come
  from pickleball office-supply drops (docs/PICKLEBALL.md "Prizes") and admin rewards (Admin → Rewards
  → *Special office furniture*); quests (Phase 2b) will add more.
- **New offices start furnished:** a Computer Desk against the back wall, its chair and a small plant.
  An office emptied by its owner stays empty.

### Placement rules (`FurnitureRules.check`, the same on server and client)
- Whole-stud positions, turned 0 / 90 / 180 / 270 degrees (a quarter turn swaps width and depth).
- The footprint stays 1 stud from every wall.
- Nothing in the **entry zone** inside the door (10 × 7 studs), so nobody is boxed in on arrival.
- No overlaps (touching is fine). **Rugs** may lie under other furniture, but not under another rug,
  and nobody bumps into them.
- At most **60** items. A Special item can only be placed as many times as it's owned; a Level item
  only from its level on.

### Office themes (level rewards)
Player Panel → 🏅 Levels → **Office theme** repaints your room's walls and carpet: Warm Wood (Lv 10),
Garden (Lv 40), Night Sky (Lv 60), Royal Gold (Lv 90), or the default slate. Visitors see it. Picked
with `Level.SetCosmetic("Office", id)`, checked by the server; shown only while your level unlocks it
(`OfficeService.applyTheme`).

### Edit mode (your own office)
**✏️ Edit** opens the furniture strip at the bottom: category tabs, a card per item ("Free" or "2 left"),
and **✓ Done**. The hammer is put away while editing, so a click never swings it.

| Do | Mouse / keyboard | Touch | Controller |
|---|---|---|---|
| Pick an item | click its card | tap its card | A on its card |
| Aim the preview | move the mouse | tap the floor | look (screen centre) |
| Turn | R or **⟳ Turn** | **⟳ Turn** | LB / RB |
| Set it down | click, or **✓ Place** | **✓ Place** | X |
| Select placed furniture | click it | tap it | X while looking at it |
| Move / turn / remove it | **✥ Move**, R, Delete or **🗑 Remove** | the buttons | the buttons |
| Stop | **✕ Cancel**, then **✓ Done** | same | B (cancel first, then leave) |

The see-through preview is green where it fits and red where it doesn't, with the reason ("Keep the
door clear.", "That overlaps the Sofa.", "Too close to the wall."). Placing keeps the same item in hand
to set down several. The server's answer is final: a refused edit shows its reason as a toast and the
room shows the saved layout. On phones the strip covers the bottom of the screen (thumbstick); tap
**✓ Done** to walk again.

## Privacy and visiting
Social page → **Who can visit**: **Public** (default, anyone), **Friends** (Roblox friends of the owner)
or **Private** (only you). The directory shows each office's setting; Private offices can't be picked.
- The server checks every visit when it starts (friendship asked from Roblox once per pair and cached).
- Every second a guard checks who stands in each room. Anyone no longer allowed in (the owner switched
  to Private or Friends, or left the server) is sent to the lobby with a toast.
- Visitors can look around but never edit: every edit must come from the owner standing in their own
  room.
- Offices of players in **other servers** can't be visited yet (planned for Phase 6, read-only).

## Saved data (schema v11, docs/DATA_SCHEMA.md)
`Furniture` (Special items owned), `OfficeLayout` (`{Id, Item, X, Z, R}` per placed item, room-local),
`NextOfficeItemId` (ids are never reused), `OfficePrivacy`. A layout is re-checked on every load
(`FurnitureRules.parseLayout`): entries that are unknown, out of the room, in the door, overlapping an
earlier one, beyond the cap or not owned any more are dropped; the rest are kept exactly. About 40
bytes per item, so a full office is under 3 KB.

## Security (docs/REMOTE_CONTRACTS.md "Office")
The client only sends an item key, whole numbers and ids. The server checks types and ranges, that the
key is in the catalogue, ownership, the placement rules, the cap, and that the sender stands in their
own room. It never accepts a model, a position in the world, an Instance or a price. Edits are
rate-limited (`RemoteLimits.Office`: burst 8, 3/s); trips and privacy changes more tightly
(`RemoteLimits.OfficeTravel`: burst 3, one per 2 s). Teleports go through
`MovementGuardService.noteTeleport`, so they never look like a speed hack.

## Performance
- Rooms are built once at server start; ~15 parts each (12 rooms: ~180 parts) far from the map.
  With instance streaming on, a room streams in when you arrive (`RequestStreamAroundAsync`) and each
  room streams as one piece (`ModelStreamingMode.Atomic`).
- Furniture: at most 60 items of at most 12 parts per room (~720 parts worst case per room). A room is
  redrawn from its layout after each edit, which edit rate limits keep rare.
- The client does no per-frame work outside edit mode. The preview follows the pointer with one
  RenderStepped connection that exists only while a preview is showing. Where you are is checked twice
  a second.
- **Not yet measured** (needs the deferred performance baseline, `docs/UPDATE_TEST_PLAN.md` B4).

## Admin
Admin → Rewards → *Special office furniture*: pick the item and an amount (1-50). It goes to the
player's furniture inventory, and the reward is logged like every other.
