# Developer Products still missing a Product ID

Generated 2026-10-08 from `src/config/StoreConfig.luau` (`PRODUCT_IDS`), updated 2026-10-19.

A store product with no Product ID stays **hidden** in the Store, and the server refuses to prompt
it. Nothing breaks while one is missing: the item just isn't for sale yet. **6 products** have no
id. The other 35 already have one (see the last section).

## How to add one
1. Creator Hub → your experience → **Monetization → Developer Products → Create a Developer
   Product**. Use the name and price below (the price is a suggestion; the Store shows the live
   Creator Hub price).
2. Copy the new product's **Product ID**.
3. In `src/config/StoreConfig.luau`, inside `PRODUCT_IDS`, add the key with that id (or uncomment its
   line), for example:
   ```lua
   crit_15_30m = 1234567890,
   ```
4. Run `scripts/check.ps1`. A spec stops the build if two keys share the same id.
5. Test the purchase in Studio (test purchases are free) and check the item arrives in the Bag.

## Missing Product IDs (6)

### Crit Damage boosts: top two tiers (6)
These are in the catalogue but were never given ids, so the store's **Crit Dmg** tab shows only
+3 %, +5 % and +10 % today.

| Key | Suggested product name | Suggested price (R$) | What the player gets |
|---|---|---|---|
| `crit_15_30m` | +15% Crit Damage Boost (30 min) | 39 | 1 boost in the Bag |
| `crit_15_1h` | +15% Crit Damage Boost (1 hour) | 69 | 1 boost in the Bag |
| `crit_15_5h` | +15% Crit Damage Boost (5 hours) | 219 | 1 boost in the Bag |
| `crit_20_30m` | +20% Crit Damage Boost (30 min) | 49 | 1 boost in the Bag |
| `crit_20_1h` | +20% Crit Damage Boost (1 hour) | 89 | 1 boost in the Bag |
| `crit_20_5h` | +20% Crit Damage Boost (5 hours) | 279 | 1 boost in the Bag |

## Already set up (35, no action needed)
| Group | Keys |
|---|---|
| XP boosts | `xp_10_30m`, `xp_10_1h`, `xp_10_5h`, `xp_20_30m`, `xp_20_1h`, `xp_20_5h`, `xp_25_30m`, `xp_25_1h`, `xp_25_5h` |
| Damage boosts | `dmg_3_30m`, `dmg_3_1h`, `dmg_3_5h`, `dmg_5_30m`, `dmg_5_1h`, `dmg_5_5h`, `dmg_10_30m`, `dmg_10_1h`, `dmg_10_5h` |
| Crit Damage boosts | `crit_3_30m`, `crit_3_1h`, `crit_3_5h`, `crit_5_30m`, `crit_5_1h`, `crit_5_5h`, `crit_10_30m`, `crit_10_1h`, `crit_10_5h` |
| Mystery Hammer | `mystery_hammer` |
| Bundles | `beginner_bundle`, `stress_reliever_package` |
| Pet eggs (paid random items: questionnaire must say yes) | `egg_common`, `egg_rare`, `egg_mythical` |
| Synthesis Pick (12 R$, not random) | `synthesis_pick` |
