# Remote Contracts

Every RemoteEvent between client and server. The client only **requests**; the server
validates and decides every result (damage, HP, score, rewards, defeat).

## Rules for all client -> server remotes
Bind through `RemoteController.bind` (`src/server/controllers/RemoteController.luau`).
It applies, in order, before the handler runs:

1. **Sender present:** requests from players who already left are dropped silently.
2. **Argument cap:** more arguments than `maxArgs` (trailing `nil`s count) → reject.
3. **Rate limit:** per-player token bucket from `RemoteLimits` (server-only config) → reject.
4. **Error containment:** handler errors are caught and logged; the connection survives.

Inside the handler, every argument is `unknown` and must pass `Shared/Validate`
(`string`, `id`, `number`, `integer`, `boolean`: these reject wrong types, NaN, ±inf,
out-of-range values, over-long strings and malformed UTF-8). On failure call
`RemoteController.reject(player, remoteName, reason)` and return. Rejections are
logged at most once per player every 5 s (`RemoteLimits.RejectLog`).

Most payloads are scalar arguments. The admin remotes that take a table (`CreateBoss`,
`SetDropRates`, `Moderate`, `Events`) read only known keys, check each value's type and range, and
bound every list (for example at most 11 hammer ids in an event).

Abuse thresholds live in `ServerScriptService.Config.RemoteLimits`, not `ReplicatedStorage`,
so clients can't read them.

**Naming (2026-10-10):** never name a remote (or its folder) after an Instance member such as
`Remove`, `Destroy`, `Clone`, `Name` or `Parent`. `Remotes.Office.Remove` returned the deprecated
`Instance:Remove` method instead of the RemoteEvent, which stopped the server from booting (every
door stayed locked). `scripts/check.ps1` ("Remote names") now fails on any such clash.

---

## `Combat.RequestHammerHit`: client -> server
| | |
|---|---|
| Purpose | "I swung at this boss." |
| Arguments | `bossInstanceId: string`, the server-issued id of a spawned boss (`Types.BossInstanceId`). **Not** a `BossConfig` id, and never damage, HP or position. |
| `maxArgs` | 1 |
| Validation | `Validate.id(bossInstanceId, RemoteLimits.MaxIdLength)`: 1–64 chars of `[A-Za-z0-9_-]` |
| Rate limit | `RemoteLimits.RequestHammerHit`: burst 10, refill 8/s (flood guard only) |
| Server checks (`CombatService`) | player has a session and loaded data; not flagged by `MovementGuardService`; the boss is **unlocked for this player** (`ProgressionRules.isBossUnlocked`, including the Senior bosses' Player Level requirement); at least `HitCooldown − HitCooldownGrace` since the player's last **accepted** hit (`CombatRules.isOffCooldown`); boss instance exists and is not defeated; live character **holding a hammer Tool** (tagged `HammerId`) whose root is within `GameConfig.HitReach + HitReachGrace` of the boss (`CombatRules.isInReach`; the client checks the exact `HitReach`, the grace absorbs movement during network lag). The Tool only gates the swing: damage comes from the session's `EquippedHammerId`, so editing the Tool changes nothing. The handler never yields, so checks and the state change are atomic. |
| Effect | damage = `CombatRules.computeHitDamage(equipped hammer, boss)`; HP reduced (overkill not credited); damage credited to the player's contribution; stress relieved by `StressRules.reliefForHit(applied)`. On the defeating hit: rewards (see `BossDefeated`) and respawn after `BossRespawnDelay` with a **new** instance id. |
| Response | `Combat.CombatFeedback` on success. Nothing on rejection (no oracle for probing). |
| Failure | invalid payload / rate limited → `reject` + drop. Cooldown or reach failures are normal play → drop without logging. |

## `Combat.CombatFeedback`: server -> client
| | |
|---|---|
| Purpose | Presentation only: HP bar update, hit effects, defeat effects. Clients must not derive rewards from it. |
| Payload | `Types.CombatFeedback`: `{ BossInstanceId, Health, MaxHealth, Damage, HitterUserId, Defeated, Crit }` (crits are rolled by the server) |
| Recipients | all clients (`FireAllClients`). With few bosses this is cheapest; revisit per-proximity sending if boss count grows. |
| Client handling | treat as untrusted for logic, display only; ignore unknown `BossInstanceId` |

## `Combat.BossDefeated`: server -> client
| | |
|---|---|
| Purpose | Victory Card for each player who damaged the defeated boss. |
| Payload | `Types.BossDefeated`: `{ BossInstanceId, BossId, Rewarded, ScoreAwarded, CoinsAwarded, StressRelieved, UnlockedBossIds, SharePercent, LastHit, BossName, BuffDropText?, EventDropText?, AdminDamage }`. `BuffDropText` is set when the boss dropped a store boost for this player (custom bosses always, office and event bosses by the current drop rates, `DropRateService`); `EventDropText` lists items won from active drop events (docs/EVENTS.md), already in the Bag; `AdminDamage` means the player hit this boss with admin-set damage and got nothing. `Rewarded` means the player qualified (≥ 10 %); every contributor gets score/coins |
| Recipients | every contributor still in the server, once per defeat |
| Rewards | granted by `RewardService` **before** sending, only to players whose contribution ≥ `MinRewardDamageShare × MaxHealth`: `ScoreReward`, `CoinReward`, `DefeatStressRelief`, and +1 to that boss's defeat count (which can unlock the next boss, listed in `UnlockedBossIds`). Granted at most once per player per boss life (`BossState.markRewarded`). Non-qualifiers get `Rewarded = false`. |
| Client handling | display only |

## `Mood.ZenAchieved`: server -> all clients
| | |
|---|---|
| Purpose | Announce a Zen moment (a player's stress reached 0 while armed) |
| Payload | `Types.ZenAchieved`: `{ UserId, DisplayName, ZenLevel, BonusCoins }` |
| When | inside `StressService.relieve`, after the bonus coins and Zen Level are granted on the server |
| Client handling | display only: your own Zen → big card; anyone else's → toast |

## `Profile.Saved`: server -> one client
| | |
|---|---|
| Purpose | Show "Progress saved" briefly after ProfileStore saves the player's data |
| Payload | none |
| When | ProfileStore `OnAfterSave` for that player |

## `Notify.Toast`: server -> one client
| | |
|---|---|
| Purpose | Short message for the player (e.g. why the Executive Elevator won't go up) |
| Payload | `string` (≤ 120 characters; longer messages are ignored by the client) |

## `Notify.Announcement`: server -> all clients in one server (2026-10-08)
| | |
|---|---|
| Purpose | An admin's server announcement (docs/ADMIN.md "Announce") |
| Payload | `{ Text: string, Seconds: number }`: text already cleaned (`Shared/AnnouncementRules`) and Roblox-filtered **for this recipient** (`GetNonChatStringForUserAsync`; as typed in Studio playtests); seconds one of `AnnouncementConfig.Durations` |
| When | only after `Admin.Announce` passes every check |
| Client handling | display only (`AnnouncementController`): re-checked (string ≤ 300 bytes, valid UTF-8, seconds clamped 3-60), shown with `RichText` off, queued |

## `Events.State`: server -> client (2026-10-08)
| | |
|---|---|
| Purpose | Events running right now (docs/EVENTS.md) for the Events chip, the Player Panel and Hammer Shop sale prices |
| Payload | `{ Events = { { Id, Name, Type, StartTime, EndTime, Summary, Percent?, HammerIds? } } }` (unix seconds; `Percent` / `HammerIds` for sales) |
| When | to a player on join; to everyone when the set of active events changes (start, end, create, stop, reload) |
| Client handling | display only; parsed with `EventRules.parsePublic`. The server charges and rewards from its own events, never from this |

## `Events.Notice`: server -> all clients (2026-10-08)
| | |
|---|---|
| Payload | `{ Kind: "Started" \| "Ended", Name, Summary }` |
| When | an event starts or ends while this server runs (not for events already running when the server started) |
| Client handling | display only: the notification card |

## Office (docs/OFFICES.md, 2026-10-09)
| Remote | Direction | Payload | Server checks / handling |
|---|---|---|---|
| `Office.Go` | client -> server | `userId: number?` (nil = own office); `maxArgs` 1, `RemoteLimits.OfficeTravel` (burst 3, 0.5/s) | `Validate.integer` (else rejected); that player is in this server with a room; privacy: Public, Friends (`IsFriendsWithAsync`, cached per pair) or the owner. Otherwise a toast. Teleports to the room's arrival spot (`MovementGuardService.noteTeleport`) |
| `Office.Return` | client -> server | none; `maxArgs` 0, `RemoteLimits.OfficeTravel` | only if the sender stands in an office room; teleports to the lobby spawn |
| `Office.Place` | client -> server | `itemKey: string, x: number, z: number, r: number`; `maxArgs` 4, `RemoteLimits.Office` (burst 8, 3/s) | key in `FurnitureConfig` (else rejected); whole x, z within ±20 and r one of 0/90/180/270 (else rejected); sender stands in **their own** room; `FurnitureRules.check` (walls, door, overlaps, 60-item cap, Special items owned). A refusal is a toast + `Profile.Sync`. Adds `{Id = NextOfficeItemId, ...}` to `OfficeLayout`, redraws the room |
| `Office.Move` | client -> server | `itemId: number, x, z, r`; `maxArgs` 4, `RemoteLimits.Office` | id a whole number (else rejected); same position checks; the entry must exist (else just a re-sync); checked ignoring itself |
| `Office.RemoveItem` | client -> server | `itemId: number`; `maxArgs` 1, `RemoteLimits.Office` | id a whole number; own room; removes the entry if it exists |
| `Office.SetPrivacy` | client -> server | `"Public" \| "Friends" \| "Private"`; `maxArgs` 1, `RemoteLimits.OfficeTravel` | one of the three (else rejected). Saved; the directory is re-sent; the guard (every 1 s) sends visitors no longer allowed to the lobby |
| `Office.Directory` | server -> all clients | `{ SlotCount, Offices = { { UserId, Name, Username, Privacy, Slot } } }` | when an office is assigned or freed or a privacy changes, and to each player when their data loads; display only |

Prompt (no RemoteEvent): each office door's **Back to lobby** (any player in that room).

## Pets (docs/PETS.md, 2026-10-08)
| Remote | Direction | Payload | Server checks / handling |
|---|---|---|---|
| `Pets.Equip` | client -> server | `petId: string` (`""` puts the pet away); `maxArgs` 1, `RemoteLimits.Shop` | `Validate.id` + `pet_<n>` (else rejected); must be one of the player's pets (else just a re-sync). Sets `EquippedPetId` and the `PetSpecies` / `PetRarity` attributes |
| `Pets.Incubate` | client -> server | `eggKey: string, incubatorIndex: number?`; `maxArgs` 2, `RemoteLimits.Shop` | key must be an egg product and index 1-6 if sent (else rejected); egg in the Bag; nothing incubating already; fewer than `MaxPets` pets; the player within 14 studs of that incubator (or of the nearest free one when no index), and it is free. Takes the egg, rolls the pet and saves the times in one step (no yield) |
| `Pets.ChooseEgg` | server -> client | `incubatorIndex: number, eggKeys: {string}` | after the player used an incubator's prompt holding several kinds of egg; the client shows a picker and answers with `Pets.Incubate` |
| `Pets.Hatched` | server -> client | `{ PetId, Species, Rarity, Buffs, Equipped }` | to the owner when their egg hatches; display only |

Prompts (no RemoteEvent; `Triggered` gives the server the real player): the incubator's **Place Egg**
and a world egg's **Claim Egg** (claimed and removed in the same step it's granted, so only the first
claim wins; claimer within 14 studs; data loaded).

`Notify.Announcement` may carry an optional `Title` (≤ 60 characters, e.g. "🥚 NEW EGG FOUND!"),
used only by server-made announcements.

## Executive Elevator (ProximityPrompt, not a RemoteEvent)
`ProximityPrompt.Triggered` gives the server the real player, so there is no client payload to
validate. "Ride up" checks `ProgressionRules.isBossUnlocked("the_ceo", …)` on the server before moving
the player (and spiking stress); "Ride down" always works. `ExecutiveService` also returns anyone found
on the Executive Floor without access.

## `Shop.BuyHammer`: client -> server
| | |
|---|---|
| Purpose | Buy a hammer with coins |
| Arguments | `hammerId: string`, optional `shownPrice: number` (2026-10-08: the price the shop displayed); `maxArgs` 2 |
| Validation | `Validate.id` + must exist in `HammerConfig` → otherwise `reject`; `shownPrice`, when sent, an integer 0..2^31 → otherwise `reject` |
| Rate limit | `RemoteLimits.Shop`: burst 5, refill 2/s |
| Server checks | data loaded; price = `EventService.hammerPrice` (the hammer's price less any active Hammer Shop sale, docs/EVENTS.md); refused quietly if that is **higher** than `shownPrice` (a sale just ended); `ProgressionRules.checkPurchase(…, price)` = `Ok` (exists, not already owned, enough coins); `SessionService.trySpendCoins` never lets coins go negative. The handler never yields, so double-clicks can't buy twice. A lower `shownPrice` can only cause a refusal: the client never sets the price |
| Effect | coins − price, hammer added to `OwnedHammers`, and it's equipped |
| Response | `Profile.Sync` after every request, success or not |

## `Shop.EquipHammer`: client -> server
| | |
|---|---|
| Purpose | Hold a different owned hammer |
| Arguments | `hammerId: string`; `maxArgs` 1; same validation and rate limit as `BuyHammer` |
| Server checks | data loaded; `ProgressionRules.ownsHammer` |
| Effect | `EquippedHammerId` saved; the held Tool is swapped (`HammerService.reequip`). Damage follows the saved id |
| Response | `Profile.Sync` |

## `Settings.Set`: client -> server (2026-10-09)
| | |
|---|---|
| Purpose | Turn a player setting on or off (docs/UI.md "Settings") |
| Arguments | `key: string, value: boolean`; `maxArgs` 2 |
| Validation | `SettingsRules.parseChange`: `Validate.id` (≤ 32 characters) and a key listed in `Config/SettingsConfig`; `Validate.boolean` → otherwise `reject` |
| Rate limit | `RemoteLimits.Settings`: burst 5, refill 1/s |
| Server checks | data loaded (otherwise ignored) |
| Effect | `Settings[key] = value`, saved with the profile. Settings are cosmetic: none changes damage, rewards or access |
| Response | `Profile.Sync` |

## Level (docs/GAMEPLAY_RULES.md "Level rewards", 2026-10-09)
| Remote | Direction | Payload | Server checks / handling |
|---|---|---|---|
| `Level.SetCosmetic` | client -> server | `kind: "Trail" \| "Glow" \| "Office", id: string` (`""` = default); `maxArgs` 2, `RemoteLimits.Settings` | `LevelRewardRules.parseChoice`: known kind and `""` or a known id (else rejected); the player's level unlocks it (else ignored, a UI race). Saves `Cosmetics`, sets `TrailStyle` / `GlowStyle` (re-equips the hammer for a new trail), repaints the office for a theme (`OfficeService.applyTheme`); `Profile.Sync` |
| `Level.LevelUp` | server -> one client | `{ FromLevel, ToLevel, Coins }` | sent when XP reaches levels never rewarded before and their coins are paid (`SessionService.addXp`); display only (the level-up card) |

## Rec: pickleball (docs/PICKLEBALL.md, 2026-10-10)
| Remote | Direction | Payload | Server checks / handling |
|---|---|---|---|
| `Rec.Challenge` | client -> server | `mode: "Singles" \| "Doubles"`; `maxArgs` 1, `RemoteLimits.Rec` (burst 4, 0.5/s) | known mode (else rejected); data loaded; not already in a challenge or match; 30 s since the player's last challenge; can pay the fee (10 coins) unless today's rewarded matches are used up. Opens a challenge that expires after 60 s (singles) / 90 s (doubles); `Rec.Challenges` to everyone |
| `Rec.Accept` | client -> server | `challengeId: string, team: 1 \| 2 \| nil`; `maxArgs` 2, `RemoteLimits.Rec` | `Validate.id` and `Validate.integer` (else rejected); the challenge is open, not the sender's own, not full; the sender isn't in another challenge or match and can pay. The seat is checked and taken without yielding (two accepts can't both get the last place). Full: the match starts on a free court, or waits in line |
| `Rec.Cancel` | client -> server | none; `maxArgs` 0, `RemoteLimits.Rec` | the challenger cancels the challenge for everyone; anyone else leaves it (a full one waiting for a court opens again with a new expiry) |
| `Rec.Forfeit` | client -> server | none; `maxArgs` 0, `RemoteLimits.Rec` | only from a player in a match. Before the first point: the match is cancelled and every fee refunded. After: that player's side loses for them (no coins or supply, rating and day counters as a loss); a doubles partner may play on alone |
| `Rec.Swing` | client -> server | `u: number, v: number, power: number` (aim across [-1, 1], aim deep [0, 1], power [0, 1]); `maxArgs` 3, `RemoteLimits.RecSwing` (burst 6, 4/s) | numbers in range (u, v within ±2, then clamped by the rules; else rejected); the sender plays a match on this server, isn't flagged by `MovementGuardService`, and 0.5 s since their last swing. Serve: only the server's swing counts (launched from behind the baseline on their side). Rally: only a player on the side the ball is on, with the ball within reach (6 + 1.5 studs horizontally, at most 9 above the court, checked now and up to 0.2 s back). Faults by the hit (two-bounce rule, kitchen volley) end the rally; otherwise the server works out the next flight (aim + spread) and broadcasts it. A miss changes nothing |
| `Rec.Challenges` | server -> all clients | `{ Challenges = { { Id, Mode, HostUserId, HostName, Teams = { { {UserId, Name} }, {...} }, TeamSize, ExpiresAt, QueuePosition } }, FreeCourts }` | on every change, and to each player when their data loads; display only (cards, chip, panel) |
| `Rec.MatchState` | server -> match players | `{ MatchId, Court, Mode, Phase, Teams, Points, Serving, ServerNumber, ServerUserId, ReceiverUserId, Callout, Message, EndsAt, Friendly, Winner }` | at the start, before each serve, after each rally and at the end; display only (score bar). Spectators read the court's board |
| `Rec.Shot` | server -> all clients | `{ Court, Launch: Vector3, Velocity: Vector3, T0 }` (court-local; server time) or `{ Court, Clear = true }` | each shot; every client draws the same path (`Shared/BallFlight`). Line calls never come from the client |
| `Rec.Result` | server -> one client | `{ MatchId, Won, Reason, Friendly, Points, Team, Coins, Supply, RatingChange, Rating }` or `{ MatchId, Cancelled = true, Reason }` | once per match id per player (`ProcessedMatches`); display only (result card) |

## `Store.RequestPurchase`: client -> server
| | |
|---|---|
| Purpose | Ask for Roblox's purchase prompt for one store product |
| Payload | `productKey: string` (a `StoreConfig` key, max `RemoteLimits.MaxIdLength`) |
| Server checks | known key; product has a Developer Product id; store open (`StoreService.isOpen`); Mystery Hammer only if PolicyService allows paid random items for this player. Rate limit `RemoteLimits.Shop` |
| Result | `MarketplaceService:PromptProductPurchase`. **Delivery is only by `ProcessReceipt`** (`PurchaseService`, see `docs/STORE.md`), never by this remote. A refusal re-sends `Store.State` |

## `Store.RequestGift`: client -> server
| | |
|---|---|
| Purpose | Buy a boost for a Roblox friend (docs/STORE.md "Bag and gifts") |
| Payload | `productKey: string, recipientUserId: number` |
| Server checks | known key; not the Mystery Hammer (rejected); recipient a whole positive number and not the buyer; store open and product on sale; `Player:IsFriendsWithAsync(recipient)` must be true (otherwise rejected and logged); buyer's data loaded. Rate limit `RemoteLimits.Shop` |
| Result | sets the buyer's `PendingGift`, then `PromptProductPurchase`. Delivery is only by `ProcessReceipt`, into the friend's gift inbox |

## `Bag.Use`: client -> server
| | |
|---|---|
| Purpose | Use one item from the player's Bag |
| Payload | `productKey: string` |
| Server checks | known `StoreConfig` key (else rejected); the Bag holds at least one (else just re-sync the UI). Rate limit `RemoteLimits.Shop` |
| Result | removes one and, in the same step, starts the boost (`BuffService.grantTimed`) or opens the Mystery Hammer (rolls its two bonuses once, adds and equips it); toast + `Profile.Sync`. Bundles are unpacked when granted, so the Bag never normally holds one; a whole one found there is unpacked into its boosts |

## `Store.AdminSetMode`: client -> server
| | |
|---|---|
| Purpose | Admin opens, closes or schedules the store for every server |
| Payload | `{ Mode: "On" \| "Off" }` or `{ Mode: "Schedule", StartsAt: number, EndsAt: number }` (unix seconds) |
| Server checks | sender is an admin (decided by the server: owner, `StoreAdminConfig.AdminUserIds`, Studio tester); payload parsed by `Shared/StoreSchedule.parse` (finite numbers, ends after it starts, in the future, within a year). Non-admins are rejected and logged |
| Result | applied locally, saved to DataStore `StoreSettings`, published on MessagingService `StoreSettings`; admin gets a toast |

## `Store.State`: server -> one client
| | |
|---|---|
| Payload | `{ Open, MysteryAllowed, IsAdmin, Mode, StartsAt, EndsAt }` |
| When | on join, whenever settings change or a schedule boundary passes, after a refused purchase request |
| Client handling | display only (show or hide the Store button, tabs and Admin tab); the server re-checks everything on each request |

## Admin remotes (`Remotes.Admin`, docs/ADMIN.md)
All client -> server admin remotes share these checks, on top of the common rules above: sender is an
admin (`Lib/AdminAuth`, cached on join; non-admins are rejected and logged), rate limit
`RemoteLimits.Admin` (5 burst, 1/s), at most 3 arguments. Problems an admin can fix (bad number,
player left) come back as a `Notify.Toast`; malformed payloads are rejected and logged. Every
accepted action prints an `[Admin]` line.

| Remote | Payload | Server checks | Result |
|---|---|---|---|
| `SetLevel` | `userId: number, level: number` | integer level 1..`AdminConfig.MaxSetLevel` (500); target in this server with loaded data | `Xp = LevelRules.scoreForLevel(level)` (saved); Level attribute + `Profile.Sync` |
| `SetDamage` | `userId: number, damage: number` | integer 0..`MaxSetDamage` (1,000,000); target in this server | `BuffService` damage override for this session (0 clears). Hits use exactly that damage, never crit, and mark the boss life `AdminBoosted` for that player, who then gets **no** reward for it |
| `SetUnlock` | `userId: number, bossId: string or "*", unlocked: boolean` | known `BossConfig` id or `"*"`; target in this server | edits `AdminUnlocks` (saved); `"*"` + false clears them all. Earned unlocks are never removed |
| `CreateBoss` | `{ Name, LookId, MaxHealth, ScoreReward, CoinReward, RespawnMode }` | `CustomBossRules.parseSpec` (name 1-30 chars, look from `CustomBossConfig.LookIds`, integer bounds, `RespawnMode` exactly `"Continuous"` or `"Once"`); name passes `TextService` filtering unchanged; **position is where the admin's character stands** (raycast to the floor), at least `MinSpacing` (14 studs) from every boss; at most 20 custom bosses | saved with `UpdateAsync` to DataStore `CustomBosses`, spawned here, other servers told via MessagingService `CustomBosses` |
| `EditBoss` | `action: "Move" or "Delete", bossId: string` | custom boss id; Move uses the admin's position with the same spacing check | saved and synced like `CreateBoss` |
| `SetDropRates` | `{ NormalMin, NormalMax, LuckyMin, LuckyMax, LuckyEveryMinutes, LuckyLastsMinutes }` or `"Reset"` | `DropRateRules.parse`: chances are finite numbers 0..1 with min <= max per range; Every is an integer 10..1440 minutes; Lasts an integer 1..Every-1 | saved with `SetAsync` to DataStore `DropRates` (`"Reset"` removes the key, so `DropRateConfig.Default` applies); other servers told via MessagingService `DropRates` |
| `Announce` (2026-10-08) | `text: string, seconds: number` | `AnnouncementRules.seconds` (one of 5 / 10 / 15 / 30); `AnnouncementRules.clean` (≤ 800 bytes in, one line, control and invisible formatting characters removed, 1-200 characters out); one per admin every `AdminConfig.AnnouncementCooldownSeconds` (10 s, claimed before the filter yields); `TextService:FilterStringAsync` once, then each recipient gets `GetNonChatStringForUserAsync(theirUserId)` (live; a failed filter sends nothing; Studio playtests send the text as typed) | `Notify.Announcement` to every player in **this** server, each with their own filtered text; `[Admin] … announced (… s, N players)` log line |
| `Events` (2026-10-08) | `{ Action: "Create" \| "Update", EventId? (Update), Type, Name?, DurationSeconds? or StartsAt + EndsAt, Config }` or `{ Action: "Stop" \| "ForceRemove" \| "StartNow" \| "DeleteHistory", EventId }` | `EventRules.parseSpec`: known type; settings only from `EventConfig`'s lists and ranges (multiplier, boss look, location, quantity 1-4, drop boss and item, whole 1-100 % chance, whole 5-90 % discount, ≤ 11 known paid hammer ids); duration from the list, or whole unix times that start no earlier than 2 min ago and at most 90 days ahead, end after the start and last ≤ 14 days; a typed name (≤ 40 characters) passes `TextService` filtering unchanged; at most 12 events running or scheduled. Stop: a valid event id | saved with `UpdateAsync` to DataStore `Events`, applied here, other servers told via MessagingService `Events` (docs/EVENTS.md) |
| `Reward` (2026-10-08) | `{ UserId, Kind: "Coins" \| "Xp" \| "Item" \| "Hammer" \| "Pet", Key?, Amount?, Reason? }` | target in this server with loaded data; Coins 1-100,000, XP 1-10,000,000, Item a known `StoreConfig` key with 1-50, Hammer a coin hammer not yet owned, Pet a known species (pet count below `MaxPets`); Reason cleaned, ≤ 100 characters | grants through the existing systems (SessionService, Bag, OwnedHammers, PetService); toast to both; admin log + player history entry (success or failure) |
| `History` (2026-10-08) | `{ Mode: "Player", UserId? \| Username?, Type?, Days?, Page }` or `{ Mode: "Admin", DaysAgo, Action?, Page }` | page 1-100; type from `HistoryService.TYPES`; days 0-365; days ago 0-30; username resolved like Moderation | one page (20) of history to the admin on `Admin.HistoryResult` (server -> that admin only) |
| `Bypass` (2026-10-08) | `enabled: boolean` | — | the admin's own boss-access bypass for this session (`BuffService.setBossBypass`); sets the `AdminBypass` player attribute |
| `SpawnEgg` (2026-10-08) | `rarity: "Common" \| "Rare" \| "Mythical"` | known rarity (else rejected); at most `PetConfig.MaxWorldEggs` (3) eggs out; a free spot | places a world egg in **this** server and announces it (docs/PETS.md); `[Admin] … spawned a … world egg` |
| `Moderate` | `{ Action: "Ban" or "Unban", UserId?, Username?, Duration?, Reason?, Note? }` | target by UserId or a valid username (`GetUserIdFromNameAsync`); not yourself; Ban: not an admin/owner, `Duration` and `Reason` must be keys of `AdminConfig.BanDurations` / `BanReasons` (players only ever see the fixed reason text), `Note` up to 200 chars (private) | `Players:BanAsync` / `UnbanAsync` with `ApplyToUniverse = true` (alts included); fails with a toast in Studio |

`Admin.State` (server -> one client): `{ IsAdmin }` for everyone on join; admins also get
`{ CustomBosses, DropRates, DamageOverrides, MaxSetLevel, MaxSetDamage, BanDurations, BanReasons,
Events = { Events, History }, NextWorldEggAt, WorldEggs }`, re-sent when custom bosses, drop rates, damage overrides or events
change. Display only.

## `Profile.Sync`: server -> one client
| | |
|---|---|
| Purpose | The player's own progression for the UI (HUD, shop, locked bosses) |
| Payload | `Types.ProfileSnapshot`: `{ Coins, OwnedHammerIds, EquippedHammerId, BossDefeats, UnlockedBossIds, ZenLevel, Level, Xp, Buffs, MysteryHammers, AdminUnlocks, Bag, Pets, EquippedPetId, Incubation, Settings, Cosmetics, Furniture, OfficeLayout, OfficePrivacy, Recreation }` |
| When | on data load, after every reward, purchase, equip, `Settings.Set`, `Office.*` edit and pickleball fee, refund or result |
| Client handling | display only; parsed defensively (`ProgressController`) |

## `Leaderboard.Snapshot`: server -> all clients (2026-10-07)
| | |
|---|---|
| Purpose | The leaderboard board's contents (docs/GAMEPLAY_RULES.md "Global leaderboard") |
| Payload | `{ Global, Note, Tabs = { Score, Xp, Coins }, Online }`; each list holds rows `{ UserId, Name, Score?, Xp?, Coins? }` (top 10 per tab; `Online` = players in this server with loaded data) |
| When | every `LeaderboardReadInterval` (60 s); to a joining player at once (last snapshot); to everyone ~2 s after joins, leaves and data loads |
| Client handling | display only; parsed defensively (`LeaderboardController`). There is no client -> server leaderboard remote. |

---

## Replicated state (server-written attributes)
Names live in `Shared/Attributes`. Only the server writes them; clients read them for display.

| Where | Attribute | Meaning |
|---|---|---|
| Boss `Model` under `Workspace.Bosses` | `BossInstanceId`, `BossId`, `Health`, `MaxHealth`, `Defeated`, `ShoutText`, `ShoutSeq` | live boss state for HP bars, target selection and the client-drawn monster's hit/defeat animations |
| Custom boss `Model` (admin-created) | `BossName`, `BossLook` | display name (already text-filtered) and the office boss whose look it borrows |
| Event boss `Model` (docs/EVENTS.md) | `BossName`, `BossLook`, `EventBoss` | as a custom boss, plus `EventBoss = true` |
| `Player` | `PetSpecies`, `PetRarity` | the equipped pet (unset = none); every client draws it (docs/PETS.md) |
| `Player` | `TrailStyle`, `GlowStyle` | the level-reward trail and Zen glow in use (`""` = default; only unlocked picks); the hammer trail and the Zen glow use them |
| `Player` | `RecMatch` | the pickleball match this player is in (unset = none): the client turns sprint off and shows the score bar; the server keeps its own record (docs/PICKLEBALL.md) |
| `Player` | `AdminBypass` | an admin's boss-access bypass is on (display only: their doors and labels; the server checks its own flag) |
| Incubator `Model` (`Workspace.PetCenter.Incubators`) | `IncubatorIndex`, `OwnerUserId`, `OwnerName`, `EggRarity`, `EndsAt`, `HatchedSpecies` | the egg on show and its end time (unix seconds); `HatchedSpecies` while it hatches |
| World egg `Model` (`Workspace.PetCenter.WorldEggs`) | `WorldEggRarity` | its rarity |
| Hammer `Tool` (server-created, in the character) | `HammerId` | marks the Tool as a hammer for the server's hand check |
| `Player` | `Stress` | the player's Stress Meter (also drives the server-drawn mood face and hammer glow) |
| `Player` | `Level` | Player Level from XP (HUD, "Lv N" head tag, Senior unlocks) |
| `Player` | `ZenBuffEnds` | `Workspace:GetServerTimeNow()` time the Zen buff ends (0 = none); HUD countdown only |
| `Player.leaderstats.Score`, `.Coins` (IntValue) | | lifetime score and coins (saved values, mirrored for display) |

## Movement sanity (`MovementGuardService`)
Reach is checked against the character's position, which Roblox lets each client simulate. The
server samples every character's root position every `MovementLimits.SampleInterval` (0.5 s); a
horizontal move faster than `MaxHorizontalSpeed` (50 studs/s; walking is 16) flags the player and
`RequestHammerHit` and `Rec.Swing` are ignored for `SuspectSeconds` (5 s). Respawns start fresh. This blocks teleporting
to a boss and large speed hacks; small boosts under the limit are an accepted v1 limitation. Sprint (`GameConfig.SprintSpeed` 26) stays well under the limit.

## Removed
- `Round.RoundState`: removed 2026-10-05; encounters end on defeat, there is no round timer.
