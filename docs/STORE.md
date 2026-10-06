# Robux Store

Optional monetization, added in Phase 8. Players buy **timed boosts** and the **Mystery Hammer**
with Robux (Developer Products). Everything the store sells can also be earned or matched through play:
coins buy hammers, and Zen gives a free damage and crit buff. The leaderboard stays fair because
**Score is never boosted**. XP boosts only change Player Level.

Code: `Config/StoreConfig` (catalogue), `Shared/BuffRules`, `Shared/HammerRules`,
`Shared/StoreSchedule`, `Services/BuffService`, `Services/StoreService`, `Services/PurchaseService`,
`Config/StoreAdminConfig` (server only), `Controllers/StoreController` (client UI).

## Catalogue and suggested prices (Robux)
Every boost comes in three lengths of **play time**: 30 minutes, 1 hour or 5 hours.

| Boost | 30 min | 1 hour | 5 hours |
|---|---|---|---|
| +10 % XP | 15 | 25 | 99 |
| +20 % XP | 25 | 45 | 149 |
| +25 % XP | 35 | 59 | 199 |
| +3 % Damage | 15 | 25 | 99 |
| +5 % Damage | 25 | 45 | 149 |
| +10 % Damage | 45 | 79 | 249 |
| +3 % Crit Damage | 10 | 19 | 79 |
| +5 % Crit Damage | 15 | 25 | 99 |
| +10 % Crit Damage | 25 | 45 | 149 |
| **Mystery Hammer** (permanent) | 199 | | |

Why these prices: 30-minute boosts sit at impulse prices (10–49 R$). Longer boosts give a better
rate per minute, so the 5-hour packs are about 30–40 % of the 30-minute rate. Damage boosts cost more
than crit-damage boosts of the same percent because they apply to every hit, whereas crit damage only
applies on crits (5 % base chance, 10 % in Zen). The Mystery Hammer is priced like a permanent
cosmetic plus stat item.

The store shows the **live Creator Hub price** (`GetProductInfoAsync`). The prices above are only
fallbacks and suggestions.

## Rules
- **Boosts count down only while you're in the game.** A 5-hour boost gives 5 hours of play.
- **Same kind again:** time adds up and the strongest percent applies to the combined time. Banked
  time is capped at 50 hours (`StoreConfig.MaxBuffSeconds`).
- XP boost multiplies XP from defeats. Score and coins are not boosted.
- Damage boost multiplies hit damage. Crit Damage boost adds to the crit multiplier
  (base crit +50 %).
- **Mystery Hammer:** waits unopened in the Bag. When the player taps **Open**, its stats are rolled
  once and it's theirs forever: equipped straight away and listed under "Hammers".

  | Stat | Range | Odds |
  |---|---|---|
  | Damage | 20–35 (whole numbers) | each value 1 in 16 = 6.25 % |
  | Crit damage | +5 % to +10 % | each value 1 in 6 ≈ 16.7 % |

  The odds are shown in the store before buying, as Roblox requires for paid random items. Players
  whose `PolicyService` info has `ArePaidRandomItemsRestricted` (or whose lookup fails) never see the
  Mystery tab, and the server refuses to prompt it for them.

## Bag and gifts (2026-10-06)
Nothing bought is used automatically any more. Everything goes into the player's **Bag** (button
above Store), saved with their data (`Bag`, schema v6), and the player decides when to use it:
- **Use** on a boost starts it (or adds its time to the same kind already running, as above);
- **Open** on a Mystery Hammer rolls, adds and equips it.

The Bag also collects **gifts** from friends and **custom-boss drops** (docs/ADMIN.md).
Purchases made before this change were already applied and stay that way.

### Gifting
Every boost has a **Gift** button next to Buy. The Mystery Hammer can't be gifted: it's a paid
random item, and Roblox requires checking the *recipient's* PolicyService rules, which isn't possible
for an offline friend.
1. The buyer picks one of their Roblox friends (online or offline) from the friend list.
2. The server checks they really are friends (`Player:IsFriendsWithAsync`) and that the product is on
   sale, records the choice in the buyer's data (`PendingGift`), and opens the normal purchase prompt.
   The buyer pays as usual.
3. `ProcessReceipt` sees the `PendingGift` and writes the gift to the friend's **gift inbox**
   (DataStore `GiftInbox`, key `Inbox_<UserId>`), keyed by the buyer's `PurchaseId` so a retried
   receipt can't deliver it twice. The buyer gets "Gift sent to <name>".
4. The friend's server claims the inbox into their Bag when their data loads, right away if they're
   in the same server, within seconds if they're in another one (MessagingService topic `Gifts`), and
   every 5 minutes otherwise. They get "Gift from <name>: ... It's in your Bag!".

Claiming never loses or doubles a gift: the gift is added to the Bag and its id to `ClaimedGifts` in
one step, and it's removed from the inbox only after that save is confirmed (`GiftService`).

A plain **Buy** clears any `PendingGift`, and so does cancelling the gift's purchase prompt, so a
later purchase is never sent to a friend by mistake. Known limitation: if a buyer starts a second
gift of the **same** boost before the first receipt arrives (normally instant), both go to the
second friend.

## Purchase delivery (`PurchaseService`)
`MarketplaceService.ProcessReceipt` handles each receipt as follows:
1. Wait (up to 20 s) for the buyer's data. ProfileStore's session lock means only one server owns it.
2. If the receipt's `PurchaseId` is already in `ProcessedPurchases` (last 200 kept), don't grant again.
3. Otherwise put the product in the buyer's Bag (or, for a gift, in the friend's gift inbox; see
   above) and record the `PurchaseId`. Bag grants have no yield in between; gift delivery is safe to
   repeat because the inbox is keyed by `PurchaseId`.
4. Return `PurchaseGranted` only once a save containing that `PurchaseId` has reached the DataStore.
   Otherwise return `NotProcessedYet` so Roblox retries later.

Delivery **never** depends on the store being open: anything paid for is delivered.

## Admin: open, close or schedule the store
Admins see an **Admin** tab in the store. They can choose:
- **Open now** / **Close now**;
- **Schedule:** open from a start time until an end time (entered in the admin's local time, stored
  as UTC). The end time must be in the future and within a year.

The setting is saved in DataStore `StoreSettings` (key `Global`) and pushed to every server through
MessagingService topic `StoreSettings`. Servers also re-read it every 5 minutes. Until an admin saves a
setting, the store uses `StoreAdminConfig.DefaultMode` (`"On"`).

The server decides who is an admin (`Lib/AdminAuth`, shared with the Admin panel):
- the experience owner: the user, or the owner of the creator group;
- any UserId in `StoreAdminConfig.AdminUserIds`;
- the local tester in Studio (`StudioTesterIsAdmin`).

## Going live: setup checklist
1. Creator Hub → your experience → **Monetization → Developer Products**. Create one product per key
   (34 in total), for example "+10% XP Boost (30 min)", priced as in the table above.

   | Kind | Keys |
   |---|---|
   | XP | `xp_10_30m`, `xp_10_1h`, `xp_10_5h`, `xp_20_*`, `xp_25_*` |
   | Damage | `dmg_3_*`, `dmg_5_*`, `dmg_10_*` |
   | Crit Damage | `crit_3_*`, `crit_5_*`, `crit_10_*`, `crit_15_*`, `crit_20_*` |
   | Mystery Hammer | `mystery_hammer` |

   `*` stands for each of `30m`, `1h` and `5h`.
2. Paste each product id into `PRODUCT_IDS` in `src/config/StoreConfig.luau`. Products without an id
   stay hidden, so you can launch a few at a time.
3. Enable **Studio Access to API Services** to test the admin settings in Studio. Test purchases in
   Studio are free and go through the real `ProcessReceipt`.
4. Update the experience questionnaire: the game now has **paid random items** (Mystery Hammer).
5. Run the store checks in `PLAYTEST.md` (59 and later).
