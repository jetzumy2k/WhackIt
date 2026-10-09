# Major Update: UI/UX Design Spec

_Written 2026-10-09 (Phase 0). Builds on what exists: `Lib/PanelKit`, `Lib/Responsive`,
`docs/UI.md`. Everything stays built in code (no StarterGui assets, no image uploads)._

## 1. Design tokens (`Lib/UiTokens`, Phase 1)

The values below are **today's values** from `PanelKit`/`Responsive`. Phase 1 only gives them names,
so existing screens don't change.

| Token | Value | Use |
|---|---|---|
| `Color.Window` | 26, 29, 41 | panel background |
| `Color.Header` | 34, 38, 55 | panel header |
| `Color.Nav` | 31, 34, 49 | sidebar / tab strip |
| `Color.Card` | 40, 44, 63 | cards, rows |
| `Color.Field` | 52, 57, 80 | inputs, inner wells |
| `Color.Text` / `Muted` / `Heading` | 240,242,248 / 170,176,198 / 255,214,120 | text |
| `Color.Primary` / `Good` / `Danger` / `Neutral` / `Disabled` | 70,140,230 / 70,175,95 / 205,75,80 / 78,84,108 / 70,72,84 | buttons and states |
| `Font.Body` / `Bold` / `Title` | GothamMedium / GothamBold / FredokaOne | |
| `Text.Body` / `Small` | 17 / 15 px (× 0.85 on phones, never below 11) | |
| `Size.Row` | 46 px | minimum tap height |
| `Motion.Open` / `Hover` | 0.12 s / 0.08 s | panel scale-in, button feedback |
| `Motion.Card` | show 0.22 s Back-Out, hide 0.15 s Quad-In | notification and result cards |

Implemented in Phase 1 (2026-10-09): `Color`, `Font`, `Text`, `Size`, `Radius` (Button 8, Tile 10,
Card 12, Window 16), `Space` (4/8/12/16/24) and `Motion`. The remaining tokens below come with the
first screen that uses them (Phase 2a).

Planned: `Layer` z-order (HUD 1, Chip 5,
Panel 10, Modal 20, Notice 30, Toast 40); `Color.Gold/Silver/Bronze` for rankings (copied from the
Hall of Calm board); `Color.Valid/Invalid` for furniture previews (Good / Danger at 50 % transparency).

## 2. Components (Phase 1)

| Component | States | Notes |
|---|---|---|
| Button (exists) | normal, hover, pressed, selected, disabled (with reason tooltip) | gamepad selection ring = the hover look |
| Icon dock button (exists) | + badge count | one new button: 🏢 **Social** |
| Confirm dialog (new) | open, busy (waiting for server), error | in the Modal layer; B / Esc = Cancel |
| Tooltip (new) | hover on desktop, long-press on touch, shown when selected on gamepad | ≤ 2 lines |
| Progress bar (new) | animated fill, label; instant with reduced motion | quests, career, match score |
| List row with action (exists as PanelKit row) | + avatar thumbnail slot | Office Directory, challenges |
| Grid card (exists as PanelKit grid) | owned count, placed count, locked | furniture inventory |
| Empty / loading / error / locked panels (new) | | one short sentence + one action |
| Notification card (exists) | + action button (exists) | used for challenges, with **Accept** |
| Chip (exists in EventController) | count | 🏓 Challenges (n) |

## 3. Screens

### 3.1 Social page (Player Panel)
Sections: **My Office** (Go / Return, privacy picker Public · Friends · Private), **Offices** (Office
Directory), **Pickleball** (Phase 4). Opened by the 🏢 Social dock button or the Menu.

### 3.2 Office Directory
```
┌ Offices in this server ──────────────────────┐
│ [avatar] Mia_123     Public      [ Visit ]   │
│ [avatar] BenTheDev   Friends     [ Visit ]   │  ← disabled + tooltip "Friends only"
│ [avatar] Rita        Private     [ —     ]   │
│ (empty) "You're the only one here. Invite a  │
│          friend!"                            │
└──────────────────────────────────────────────┘
```
Your own row sits first with **Go to my office**. The list updates on join/leave/privacy change,
reusing its rows (no rebuild).

### 3.3 Office edit mode (own office only)
- Bottom strip: category tabs (Desks & chairs · Tech · Plants & storage · Decor · Trophies), item
  cards "Desk ×2 (1 placed)".
- Selecting an item shows a **preview** that follows the mouse or a touch drag, snapped to the 1-stud
  grid. It's tinted Valid or Invalid, with the reason under it ("Blocks the door", "Overlaps Plant",
  "All placed").
- Controls: Rotate (R / LB-RB / ⟳ button), Place (click / A / ✓), Cancel (Esc / B / ✕),
  Move and Remove when a placed item is selected. Buttons are at least 46 px for touch.
- The server's answer is final: a refused edit undoes the preview and shows a toast with the reason.

### 3.4 Pickleball
- **Challenge panel:** Singles / Doubles toggle, "Entry fee: 10 coins", rewards "Win 60 · Play 20 +
  office supply", today's rewarded matches "3 / 10", a **Challenge server** button (disabled with a
  reason when coins are short, on cooldown or already in one), and the open challenges with
  **Accept** (team picker for doubles).
- **Notice:** "🏓 Mia wants a Singles match! [Accept]". Doubles: "🏓 Ben wants Doubles (2 of 4)".
- **Match HUD:** top-centre score (singles "4 – 2", doubles "4 – 2 – 1"), serve-side arrow, a
  fault banner in words for 1.5 s ("Kitchen volley!", "Out!", "Two bounces!"), a small
  "Leave match" button with a confirm.
- **Result card:** WIN/LOSS, score, coins, office supply revealed (card flip; fade with reduced
  motion), rating change, **Rematch** (both must accept) and **Back to campus**.

## 4. Responsive rules (extends `docs/UI.md`)
- New panels use `PanelKit.window` and `Responsive.fitPopup`; nothing new is pinned to the screen
  edges except the match HUD (top-centre, clear of the Stress Meter and the jump button).
- During a match, the hammer HUD hint and Sprint button are hidden.
- In edit mode on phones, the inventory strip replaces the dock buttons, and the preview controls sit
  above the thumbstick area.

## 5. Gamepad
Opening any panel selects its first control. D-pad / left stick moves selection, A activates,
B closes or cancels, LB/RB switches tabs (and rotates furniture in edit mode). Pickleball: R2 swing,
left stick aim.

## 6. Reduced motion (Settings, Phase 1)
On: panels and cards appear without scale/slide, progress bars jump, no camera shake on hits, no
reward-reveal flip, background tweens (vending machine pulse, NPC idles) keep running because
they're slow and small. Hit sparkles stay (they're short and small). Nothing is ever conveyed by
motion alone.

## 7. Sound
Built-in sounds only (as today): soft click on button press (exists on the vending machine), a ping
for a challenge notice (once, not repeated), and a paddle "pock" on accepted hits. Played locally, at most one at a time per type.
