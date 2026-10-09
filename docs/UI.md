# Responsive UI

Added 2026-10-08. Every screen of the game is built in code (there are no StarterGui assets), so
screen-size rules live in two places: `Lib/Responsive` for HUD buttons, popups and text sizes, and
`Lib/PanelKit` for the Admin and Player panels. Nothing here changes gameplay.

## Screen types (`Responsive.classify`)
| Type | Rule | Examples |
|---|---|---|
| Phone | short side under 500 px | phones in either orientation; small desktop windows |
| Tablet | touch screen, short side 500+ | iPad landscape / portrait |
| Desktop | no touch, short side 500+ | 1920x1080, 1600x900, 1366x768 |

## Layout rules
- **Icon buttons (2026-10-08, `Responsive.iconButton`):** every HUD button is an icon with a short
  label. On desktops and tablets the icon sits left of the label (140x48 / 130x46); on phones it's
  a compact 54x46 tile with a tiny caption, which is its tooltip. The buttons are grouped:
  - **top-left:** ☰ Menu (main navigation) with 🎵 Music beside it (utility; 🔇 when muted);
  - **the column:** 🛡️ Admin (admins only) on top, then 🎒 Bag (shows "Bag (3)"), 🛒 Store and
    🔨 Hammers. On desktop it's bottom-right; on touch screens it's top-right, because Roblox's jump
    button owns the bottom-right corner, and in portrait it starts below the score and boost lines.
    Hidden buttons close the gap.
- **Sprint (touch only):** just left of the jump button.
- **Popups (Store, Hammers, Bag):** 96 % x 90 % of a phone screen, their normal share elsewhere.
  Their minimum size never exceeds the screen. Store tabs scroll sideways when they don't fit.
- **Admin and Player panels (PanelKit):** a sidebar on wide windows and a scrolling tab strip on
  narrow ones (under 640 px). Short windows (under 440 px tall, i.e. phones in landscape) get a
  slimmer header without the subtitle and a slimmer tab strip, so more of the page shows. Pages
  always scroll and never shrink.
- **Notification card (announcements, event notices):** top-centre under the HUD lines. Width is
  42 % (desktop), 62 % (phone landscape) or 92 % (phone portrait), with a 560 px maximum, and it
  grows with the text. It never covers the middle of the screen.
- **Events chip:** under the Menu button, only while events run. Its list is at most half the screen
  tall.
- **Victory Card:** 62 % x 36 % on phones so its several lines stay readable.
- **How-to-play hint:** fades out after 20 s on phones, freeing the bottom of the screen.

## Text
- **Phones read slightly smaller text (2026-10-08):** `Responsive.textScale()` is 0.85 on phones. It
  applies wherever text is capped (`Responsive.capText`, so every popup, the HUD and PanelKit
  captions) and to PanelKit paragraphs, section titles and tile labels, never below a readable
  11-12 px. Titles stay the biggest text in each window.
- Labels and buttons that used `TextScaled` now have a **cap** (`Responsive.capText`). They shrink
  to fit (down to 11 px) but never grow past a readable size: 22 for row names, 20 for buttons, 30
  for titles. Before this, a wide row on a big phone made its text huge.
- PanelKit buttons and one-line row labels shrink to fit their box (`PanelKit.setTextSize`) instead
  of clipping, for example "Moderate" in a narrow phone row. Paragraph text keeps a fixed, readable
  size and wraps.
- Notes in the Store and Bag grow taller when their text wraps onto more lines.
- Text shown from other players or admins (announcements, event names) has `RichText` off.

## Design tokens (2026-10-09, `Lib/UiTokens`)
Colours, fonts, text sizes, row height, corner radii, spacing and motion durations have names, so
new screens match the old ones. They are the values PanelKit always used (`PanelKit.Colors` *is*
`UiTokens.Color`), so no existing screen changed. Full list: `docs/UI_UX_DESIGN_SPEC.md` §1.

## PanelKit pieces (2026-10-09)
Besides windows, sections, rows, buttons, text, stat tiles and grids:
| Piece | Use |
|---|---|
| `toggle(parent, label, description, value, onChange)` | an On / Off switch row (Settings page); `set` corrects it without calling `onChange` |
| `progressBar(parent, accent)` | a bar with text over it; eases to each value (instant with Reduced motion). The Profile page's "Lv 4 → Lv 5" bar |
| `notice(parent, kind, message, actionLabel?, onAction?)` | 📭 Empty, ⏳ Loading, ⚠️ Error or 🔒 Locked card with at most one button (loading pages, no pets, no events) |
| `tooltip(object, text)` | a hint above a control: on hover, while selected with a gamepad, and for 2 s after a touch long-press. Use on unclipped controls (HUD buttons); the Menu button has one |
| `confirmDialog(window, accent)` | "Are you sure?" with [Cancel] [Confirm]; the Admin panel's confirmations use it |

## Settings (2026-10-09)
Player Panel → **Settings**. Each switch is saved with the player's data (`Settings`, schema v9) and
follows them to every server; a change shows at once and the server's next sync confirms it
(`SettingsController` → `Settings.Set`, docs/REMOTE_CONTRACTS.md). Settings are cosmetic.
| Setting | Default | Effect |
|---|---|---|
| Reduced motion | Off | see below |
| Music | On | the existing music switch (kept on this device only, as before); shown only when there is music |

Adding a setting: an entry in `Config/SettingsConfig` and the code that reads it
(`SettingsController.get(key)`). Saved data needs no migration.

### Reduced motion
On when the player's switch is on **or** Roblox's own Reduced Motion setting is on
(`GuiService.ReducedMotionEnabled`). Then:
- Player and Admin panels, dialogs and notification cards appear and disappear without zooming;
- the Stress bar and progress bars jump to their new value;
- hits don't shake the camera, and sprinting doesn't zoom the camera out.

Unchanged: button hover feedback, hit sparkles and floating damage numbers (small and short), and the
slow decorative loops (vending machine, NPCs) and the short egg-hatching wobble. Nothing in the game is shown by motion alone.
Code asks `UiTokens.reducedMotion()` or wraps a `TweenInfo` in `UiTokens.motion(info)`.

## Gamepad (2026-10-09, `Lib/GamepadNav`)
| Button | Does |
|---|---|
| Y | opens / closes the Player Panel |
| D-pad / left stick | moves between controls in an open panel |
| A | presses the selected control |
| B | closes the panel opened last (a confirm dialog first, as Cancel) |

When a panel opens with a gamepad in use, its first control is selected, never its close X. In
a confirm dialog **Cancel** is selected first, so pressing A by habit never confirms. When a page is
rebuilt the selection moves back to the panel's first control, and switches update in place so the
selection stays put. Covered: the Player and Admin panels, the Hammer Shop, the Store (and its gift
picker) and the Bag. Mouse, touch and keyboard players never get a selection highlight.

## Checking a layout
Studio → Test → **Device** emulator, then each of: 1920x1080, 1600x900, 1366x768, a small window, a
tablet (landscape and portrait) and a phone (landscape and portrait). Look for overlap, clipping,
text overflow, buttons off screen, broken scrolling, unreadable text and hidden controls
(docs/PLAYTEST.md "Responsive UI, announcements, bundles, Mystery Hammer, events").
`tests/Unit/Client/Responsive.spec.luau` checks the screen types and that the touch layouts keep
the button column clear of the jump button.
