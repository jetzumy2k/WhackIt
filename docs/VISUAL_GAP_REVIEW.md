# Visual gap review (2026-10-10)

Requested by the owner after Phase 3a: "the actual structure is like a 2 story building … you did not
follow the improvements in MAJOR_GAME_UPDATE.md, specifically the buildings, characters and creatures,
the recreational building, and other GUI improvements."

The spec makes visual polish, GUI, animation and accessibility **core requirements, not a final
decoration pass** (§2.9). Phases 1-5 and 3a delivered the systems (offices, pickleball, quests, events,
missions, the elevator) but treated the look as secondary. This review lists the gaps against §4.1-4.4,
§5 and §8, from the code (builders, visuals, controllers), so the overhaul can be planned and checked.

## 1. Buildings and campus (§4.1, §5)
| Spec | Today | Gap |
|---|---|---|
| Modern multi-storey headquarters | `OfficeBuilder`: a 2-storey box (roof at y 29). Floors 3 (CEO) and 4 (Department Heads) are boxes on the north half of the roof with plain walls | No tower silhouette, no curtain-wall facade, no floor bands or lit windows, no crown/rooftop, no entrance canopy or HQ signage. From outside it reads as 2 storeys plus a lump |
| Distinct floors and departments, lighting and signage per floor | Every storey uses the same slate walls and carpet; floor 4 adds an amber strip and one sign | No per-floor theme (materials, colour, lighting preset, wayfinding) |
| Reception, elevators, stairs, corridors, meeting rooms, lounges, social spaces, shared workspaces | Reception desk, stairs, corridors, one elevator shaft | No meeting rooms, lounges, break room, open-plan shared workspace, lobby atrium features |
| Rooftop lounge | Not built (planned 3b) | — |
| Believable materials | `SmoothPlastic` almost everywhere; a few Glass / Fabric / Metal | No concrete, marble, wood grain, brushed metal, terrazzo; no `MaterialVariant`s; no `Lighting` preset (Future lighting, Atmosphere, Bloom, ColorCorrection) owned by the game |
| Modular floor plans and room templates | Rooms are code functions (office, executive suite) | Needs a small library of room templates (meeting room, lounge, workspace, washroom-free corridor kit) reused per floor |

## 2. Recreation building (§8)
| Spec | Today | Gap |
|---|---|---|
| A dedicated modern recreation building | `CourtBuilder`: 2 open-air courts on a pad, a low fence, benches, a sign | No building: no walls/roof or open-sided pavilion, entrance, lobby, scoreboard wall, spectator stand, lighting rig, locker/lounge area |

## 3. Characters and boss creatures (§4.2)
| Spec | Today | Gap |
|---|---|---|
| Eye direction, blinking, facial expressions | `BossVisual`: static eyes and pupils, **fixed angry brows and a grumpy mouth** | No blinking, pupils don't track, no expression changes (surprised on approach, dizzy on hits, happy on defeat). The fixed angry face leans aggressive, against "not frightening" |
| Idle, walking, turning, looking, interaction | `BossVisualController` + `BossMotion`: idle bob, sway, shuffle, turn to face, look around, fidgets | Bosses never walk; no squash-and-stretch on the body; limbs barely move |
| Anticipation, follow-through, weight; hit reactions; cartoon defeat | Lean-back hop, wobble, spin-and-shrink defeat | Reactions are rigid-body moves; no anticipation or overshoot, no limb flail, no confetti/stars defeat moment |
| Readable silhouettes, quality shapes | Built from blocks and balls (`Part` primitives) | No meshes; silhouettes are basic |

## 4. GUI design system (§4.3, §4.4)
| Spec | Today | Gap |
|---|---|---|
| One set of components and tokens | `UiTokens` + `PanelKit` (Phase 1), used by Pickleball, Quests, Missions, Social/Player Panel, Tower, Admin | **Not used** by the HUD (`UIController`), Bag, Store, Hammer Shop, Events chip, Leaderboard, Level-up, Announcement cards, Store machine, Office doors. Two visual languages on screen at once |
| HUD | Stress bar plus a single text line "Lv · Score · Coins · Zen" | No stat chips with icons, no XP bar, no coin pop / count-up, no grouped top bar |
| Reward reveals, unlock moments | A notice card (text) | No animated reveal (icon, burst, count-up, item card), no floor/room unlock moment |
| Icons | Emoji in text | No consistent icon set |
| Inventory grids | Bag and furniture as lists | Grids with item cards |

## 5. Constraint: art assets
Everything is built from primitives in code; the repo has **no meshes or textures** (only music ids).
Code can get much further than today (better shapes, built-in materials, MaterialVariants, lighting,
decals of text), but real high-fidelity models (furniture, boss bodies, building trim) need meshes made
in Blender or taken from the Creator Store, uploaded under the owner's account. Claude can't upload
assets or check licences; the owner decides which assets to use and provides their ids.

## 6. Proposed overhaul (to agree with the owner)
Visual work becomes its own track, done before Phase 6, each part with a Studio screenshot review:
- **V1 HQ tower:** a real multi-storey tower (full-height glass facade, floor bands, crown, entrance
  canopy, HQ sign), every floor with a theme and purpose, meeting rooms / lounge / shared workspace
  on the existing floors, the Rooftop Lounge (3b), and a game-owned lighting preset. Folds in PR #21.
- **V2 Recreation building:** a modern sports pavilion around the two courts (roof, glass sides,
  entrance, scoreboard wall, stands, lights, lounge).
- **V3 Boss creatures:** friendly expressive faces (blinking, pupils that track you, brows and mouths
  that change: curious, surprised, dizzy, happy), squash-and-stretch, limb follow-through, a short
  walk/pace in the office, a cartoon defeat burst. Bosses never attack.
- **V4 GUI unification:** every remaining screen moved onto PanelKit/UiTokens, a new HUD (stat chips
  with icons, XP bar, coin count-up), animated reward reveals and unlock moments, item grids.

## 7. Owner decisions (2026-10-10)
- **Art source:** code now, meshes later. Everything is rebuilt in code with better shapes, built-in
  materials and lighting; models will go through one asset table so uploaded meshes can replace them
  piece by piece.
- **Order:** V1 HQ tower first, then V2 recreation building, V3 boss creatures, V4 GUI.
- **PR #21** (elevator, Principal bosses) is folded into V1 and merged only when the tower looks right.

## 8. Progress
- **V1a (branch `feat/phase3a-tower`):** `Lib/TowerShellBuilder`: glass curtain wall with fins and a
  concrete band at every floor round the tower block up to the roof (y 60), parapets, the lit
  "WHACK IT OUT! HQ" crown sign and a mast; the podium wings closed in glass and fitted out as the
  **Break Room** (west: coffee bar, tables, sofa corner) and the **Meeting Room** (east: long table,
  screen, whiteboard), entered by new doorways from the ground corridor; an entrance canopy with the
  HQ name. Game lighting preset in `default.project.json`: **Future** lighting, Atmosphere, Bloom,
  ColorCorrection, SunRays. Specs added for the shell. `scripts/check.ps1` passes; **not yet seen in
  Studio** (screenshots needed).
- Next in V1: per-floor themes and wayfinding, a lobby makeover (atrium, reception, logo wall), a
  shared workspace and lounge on the upper storey, the Rooftop Lounge.
- **V1a look pass** (owner screenshots): neutral grading and warm-white lights (the amber turned
  everything olive under Future lighting), pale light panels, faint LED strips, Carpet material, a dark
  welcome sign, pendant shades fixed.
- **CEO at the top + Rooftop Lounge** (owner request): Executive Floor moved to the 4th floor, Department
  Heads to the 3rd; `Lib/RooftopBuilder` on the 5th with the Mission and Event Boards. Not yet seen in
  Studio.
- **Campus round** (owner: "looks like an on-going construction", empty coffee shop, courts hard to
  find): Recreation Center moved in front of the HQ under a pavilion (V2 started), Stress-Relief Zone
  behind; Coffee Corner rebuilt as the Calm Brew Café; skyline rebuilt as office blocks (lower, further
  out, off the street); paved apron and paved court base instead of raw concrete.
- **V1c interiors** (`Lib/InteriorBuilder`): lobby stone floor, reception front with sign, monitor and
  bell, lounge rug and tables, atrium pendant lights, a floor guide; framed joke posters on the ground
  and Senior corridors; per-floor corridor carpet colours (blue slate, plum, bronze, CEO red); wood
  slat wall in the Break Room, acoustic panels in the Meeting Room. Owner confirmed the campus round
  (pavilion, café, skyline) and a match under the pavilion roof (2026-10-10).
- **V3 boss creatures** (branch `feat/v3-boss-creatures`, on top of #21): `Shared/BossFace` (expressions,
  blinks, pupils, arm swing; unit-tested) and a rebuilt face in `Shared/BossVisual` (eyes with shine,
  closed-eye arcs, liftable brows, smile / "O" / wobbly mouths, blush; no angry brows or teeth),
  animated in `Controllers/BossVisualController` (expression per state, pupils follow you, arm swing and
  flail, confetti burst on defeat unless Reduced motion; only within 140 studs). Walking bosses and
  meshes are not done.
