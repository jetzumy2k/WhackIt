# Synthesis Machine

Added 2026-10-19. A chrome-and-glass machine in the lobby, beside the Hammer Vending Machine.
Players put several items in and get one better item out, for a coin fee.

Code: `Config/SynthesisConfig` (recipes, fees, pool), `Shared/SynthesisRules` (pure, unit-tested),
`Services/SynthesisService` (server, every check), `Lib/SynthesisMachineBuilder` (the machine),
`Controllers/SynthesisController` (window), `Controllers/SynthesisMachineController` (machine
animation). A Synthesis Pick in the 🎒 Bag also opens the window.

## Where
In the lobby on the stairs' west side, 10 studs north of the Hammer Vending Machine, facing into the
lobby like it (`ArenaConfig.SynthesisMachine`, (25.6, 0, 6), yaw 90). There's a floating
"⚗️ SYNTHESIS MACHINE" nameplate (visible from 90 studs), a sign on its crown and an **E —
Synthesize** prompt (gamepad X, tap on mobile). The two prompts are far enough apart that only one
shows at a time. You can browse the window anywhere, but SYNTHESIZE only works at the machine (the
server checks you're within 14 studs and alive).

## Recipes (owner decisions 2026-10-19)
| Recipe | In | Out | Result | Fee |
|---|---|---|---|---|
| `boost_30m` | 3 Bag boosts of 30 min | 1 boost of 1 h | All one kind: that kind, **guaranteed**. Mixed kinds: a **random** kind (XP, Damage or Crit Damage, 1 in 3 each) | 150 coins |
| `boost_1h` | 6 Bag boosts of 1 h | 1 boost of 5 h | the same rule | 600 coins |
| `egg_common` | 4 Common Eggs | 1 Rare Egg | guaranteed | 300 coins |
| `egg_rare` | 4 Rare Eggs | 1 Mythical Egg | **off**: the Mythical egg stays Robux/admin-only | (1,200) |
| `supply_swap` | 4 of the same office supply (in storage, not placed) | 1 **different** supply | random among the other 5 (equal odds) | 200 coins |

- **Boost strength.** Each kind's strengths are ranked weakest to strongest (XP 10/20/25 %,
  Damage 3/5/10 %, Crit Damage 3/5/10/15/20 %). The result takes the **weakest rank put in**, so
  mixing in one strong boost never upgrades weak ones. Only the length grows, never the percent.
  Example: 3 × +5 % Damage (30 min) → +5 % Damage (1 h). +25 % XP, +10 % Damage and +3 % Crit
  (all 30 min) → one of +10 % XP, +3 % Damage or +3 % Crit for 1 h.
- **No free boost time.** 3 × 30 min (90 min) → 60 min; 6 × 1 h → 5 h. Boosts in the Bag already
  add up when used, so the machine is for changing kind and tidying the Bag. It never creates time.
- **Hammers: none.** Shop hammers are one-time unlocks with no rarity tiers, and Mystery Hammers are
  unique paid items with their own rolled stats, so there's nothing to combine. The Hammers tab says
  so.
- **Office supplies:** paddle rack, ball bucket, standing fan, mini fridge, snack machine, neon CALM
  sign. Trophies and contest prizes are never used. Placed furniture is never touched.
- **No loops.** Nothing turns an output back into its inputs, every recipe gives fewer items than it
  takes, and the swap never returns the supply you put in.

## Synthesis Pick (5 Robux, owner approval 2026-10-19)
`StoreConfig` product `synthesis_pick` (Kind `SynthesisPick`). Buying one puts it in the Bag through
the normal receipt path (`PurchaseService`: idempotent per PurchaseId, granted only once saved). On
a **random** recipe (mixed boosts, Supply Swap), the player can spend 1 Pick together with the coin
fee to choose which of the listed results they get. Guaranteed recipes never use one. A Pick isn't
random, isn't giftable and has no store tab: it's bought from the machine's window ("Want a
specific result?"). **Hidden until its Developer Product id is pasted** into
`StoreConfig.PRODUCT_IDS.synthesis_pick` (see docs/PRODUCT_IDS.md). Admins can give Picks through
Admin → Rewards → Item.

## The window
Tabs ✨ Boosts · 🥚 Eggs · 📦 Office Supplies · 🔨 Hammers.
1. **Synthesis chamber:** an orb that shakes while the machine works and opens in the result tier's
   colour (the last result stays on show), and tiles for your coins and Synthesis Picks.
2. **How it works:** open until your first synthesis, collapsed after.
3. **Recipe buttons** when a tab has more than one recipe (3 × 30 min → 1 h, 6 × 1 h → 5 h).
4. **1 · Choose items (n / N):** a card per eligible item you own ("You have 5", or "3 in storage"
   for supplies) with ＋ Add / － Remove and a "n selected" badge; ✨ Auto-fill (a single stack first,
   so the result is guaranteed) and 🧹 Clear selection.
5. **2 · Preview:** what you put in (each with －), then ✅ GUARANTEED · result, or 🎲 RANDOM · one of
   these, 1 in N each, with every possible result listed. With a Pick: 🎲 Random or a button per
   result. The fee, a ⚠️ line saying exactly what's missing ("Add 1 more eligible item", "You do not
   own enough of this item", "These items cannot be combined", "Synthesis costs 150 coins", …), and
   the big **SYNTHESIZE · fee** button, lit only when the recipe is valid, affordable and you're at
   the machine ("📍 Walk up to the machine" otherwise).
6. **All recipes** list.

After SYNTHESIZE, the items stay in the window until the server answers. On success the orb reveals
the result and a card announces it (a celebration for Rare and better). On failure the ⚠️ line shows
the server's reason and nothing was used. If no answer comes in 6 s, the button unlocks again.

Elsewhere: a one-time tip per recipe and session when you **newly** have everything for one
("⚗️ Ready to synthesize: …"; nothing on joining), and the window closes when your character dies.

## The machine
About 50 parts: plinth, chrome pillars with energy strips, an OUTPUT window with an orb, a ledge
with 4 input sockets, a glass chamber with a glowing core, two rings of light around it, and a crown
with the sign. One soft light (no shadows) and two small particle emitters in the core.

Idle (client): the rings turn slowly in opposite directions, the core breathes and the strips
pulse, each one a repeating tween (no per-frame scripts). After every synthesis the server bumps the
model's `SynthesisPlays` attribute (with `SynthesisTier`), so **everyone nearby** sees the sockets
light one by one, the core swell and burst into sparks in the tier's colour (12 sparks for Common up
to 70 for Legendary), and the OUTPUT orb glow for a few seconds. Reduced motion: colours only.

## Safety and data
- `Synthesis.Synthesize(recipeId, selection, pick?)`: the client names a recipe, the items
  (key → count, at most 8 keys, counts 1–100) and optionally a pick. **The client never names an
  output.** `SynthesisRules.plan` works out every possible result from the recipe and the items, and
  the server rolls among them with its own `Random`. A pick must be one of those results and needs a
  Pick in the Bag.
- Checks, in order: payload shape; data and session loaded; 1.5 s cooldown; alive and at the
  machine; recipe exists and is on; every item fits it; owned (supplies: unplaced copies only);
  exact count; result exists and has room; the pick; the fee. Then coins spent, items (and Pick)
  taken, result added, **in one step with no yield**, so two requests (double taps, two remotes
  fired at once) can't use the same items. Rate limit `RemoteLimits.Synthesis` (burst 3, 1/s).
- If anything errors part-way, the Bag, office storage and coins are put back exactly as they were
  and the player is told "Synthesis is currently unavailable. Your items have not been consumed."
- Saving: the whole profile is one table saved by ProfileStore, so a crash or failed save before
  the next save loses the whole synthesis (items come back) and never half of it. Leaving after a
  synthesis saves it like any other change.
- History: every synthesis is logged ("Item" / "Synthesize": recipe, items in, result, random or
  picked, fee).
- Player data v21 `Synthesis`: syntheses done (`Total`, drives the first-time guide) and Picks used.
  The version bump also stops servers still on v20 from loading the data and dropping the Pick item
  they don't know.

## Balance ideas that need the owner's OK
- Turn on `egg_rare` (4 Rare → 1 Mythical, 1,200 coins): the first no-Robux Mythical egg.
- Raise or lower fees (`SynthesisConfig`); every recipe and fee is config.
- A pet recipe (e.g. 3 Common pets → a Rare Egg) would need rules for equipped, arena and showcase
  pets first.
- Hammer ideas, if wanted later: a Mystery Hammer re-roll (2 → 1 freshly rolled) changes paid-item
  behaviour, so it needs an explicit decision.
