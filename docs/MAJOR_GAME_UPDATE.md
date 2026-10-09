# Whack It Out! — Major Game Update Specification

**Document:** `MAJOR_GAME_UPDATE.md`  
**Purpose:** Implementation-ready product and technical plan for Claude coding agents  
**Project:** Existing Roblox experience, *Whack It Out!*  
**Status:** Proposed specification — audit the repository before implementation. Owner decisions of 2026-10-09 (§21) override anything below that disagrees.

---

## 1. Product Vision

Evolve **Whack It Out!** into a polished, modern, social stress-relief experience combining humorous office-boss encounters, recreational competition, career progression, quests, personal office customization, and rotating events.

The game’s identity must remain clear:

> Come to Whack It Out! to release stress, laugh at ridiculous office situations, compete with friends, and enjoy a virtual world together.

This update must extend the existing game rather than rebuild it blindly. All implementation decisions must be verified against the actual repository and the existing `GAMEPLAY_RULES.md`.

## 2. Non-Negotiable Design Principles

1. **Bosses never attack, damage, or kill players.** Bosses remain funny targets with expressive personalities, humorous dialogue, and cartoon reactions.
2. Preserve existing hammer combat, server-side hit validation, contribution-based boss rewards, boss unlocks, player progression, Stress Meter, Zen system, existing hammers, coins, XP, buffs/pets where implemented, and leaderboards.
3. Do not reset or silently overwrite existing player data.
4. Recreational sports are friendly competitions, not combat systems.
5. Quests should be lighthearted, varied, and enjoyable—not a stressful job simulator.
6. Players must be able to enjoy solo gameplay; multiplayer should add value rather than become a mandatory gate for everything.
7. No essential gameplay progression may depend on Robux purchases.
8. Rewards should encourage participation, creativity, teamwork, and achievement. Avoid excessive power creep.
9. Visual polish, GUI quality, animation, accessibility, and performance are core requirements—not a final decoration pass.
10. Do not claim that a feature, API, test, or visual quality target is complete without evidence.

## 3. Existing Game: Audit Before Changing

Treat the existing `GAMEPLAY_RULES.md` and actual source code as the authority for current behavior. The documented game includes shared office bosses, server-authoritative combat, damage-share rewards, hammers, coins, XP, player levels, Stress Meter, Zen rewards, boss unlock progression, leaderboards, a two-storey office, an outdoor relaxation campus, and the CEO encounter.

Before implementation:

- Inspect the project tree, project configuration, source modules, assets, tests, and documentation.
- Read `GAMEPLAY_RULES.md` fully.
- Identify current server services, client controllers, shared modules, remote contracts, profile schema, data loading/saving, GUI systems, animation systems, map builders, inventory, pets/buffs, and admin/event tools.
- Trace existing combat, reward, stress, Zen, progression, hammer purchase, and leaderboard flows.
- Record which proposed features already exist in any form.
- Identify dependencies, risks, missing APIs, test coverage, and performance constraints.
- Do not assume a module or service exists from its proposed name alone.
- Reuse existing implementations where practical. Do not duplicate currencies, XP calculations, reward logic, or profile systems.

Create or update these audit documents as appropriate:

- `docs/UPDATE_ARCHITECTURE_AUDIT.md`
- `docs/UPDATE_IMPLEMENTATION_PLAN.md`
- `docs/UPDATE_RISK_REGISTER.md`
- `docs/UI_UX_DESIGN_SPEC.md`
- `docs/UPDATE_TEST_PLAN.md`

If the repository is unavailable or incomplete, report exactly what is missing and stop before making unsupported changes.

## 4. Visual Quality, World Art, and Animation

Target the highest practical visual fidelity Roblox can support for the intended art direction. “99.9% realism” is an aspiration, not a measurable guarantee. Prioritize coherent art direction, believable proportions, natural motion, readable silhouettes, high-quality materials, lighting, and stable performance.

The game should remain polished, expressive, approachable, and humorous. Do not make bosses frightening or aggressive.

### 4.1 Modern Office Campus

Expand the existing environment into a coherent campus containing:

- A modern multi-storey corporate headquarters.
- Distinct floors and departments.
- Existing boss offices placed according to the established progression rules.
- Reception, elevators, stairs, corridors, meeting rooms, lounges, and social spaces.
- A dedicated recreation building.
- Shared workspaces and player-owned office areas.
- A rooftop lounge or other meaningful destination where appropriate.
- The existing relaxation garden, coffee area, and outdoor campus.
- Believable landscaping, paths, signage, lighting, and seating.

Use modular floor plans, room templates, furniture models, materials, and lighting presets. Every area should have a purpose. Avoid large, empty floors added only to increase map size.

Verify collisions, navigation, spawn safety, accessible paths, and compatibility with instance streaming where applicable. Avoid excessive decorative parts, transparent surfaces, dynamic lights, particles, or geometry.

### 4.2 Characters and Boss Creatures

Preserve the established boss identities and humorous personalities. Improve:

- Idle, walking, turning, looking, and interaction animation.
- Anticipation, follow-through, weight, and smooth state transitions.
- Eye direction, blinking, facial expressions, and subtle head motion.
- Personality-specific idle gestures and fidgets.
- Responsive hit reactions and cartoon defeat animations.
- Consistent animation priorities and cancellation.
- Distance-aware sound and visual effects.
- R6/R15 compatibility wherever supported by the existing system.

Use authored rig animations and procedural secondary motion where appropriate. Inspect third-party assets before use. Do not assume asset IDs exist or are licensed.

**Bosses must never damage or attack players.**

### 4.3 GUI Design System

Establish reusable components and design tokens before building each feature separately.

Components should include:

- Buttons and icon buttons.
- Navigation tabs.
- Modal windows and confirmation dialogs.
- Tooltips and contextual help.
- Cards and lists.
- Progress bars and XP indicators.
- Quest and event panels.
- Inventory and equipment grids.
- Furniture placement controls.
- Leaderboards.
- Notifications and reward reveals.
- Loading, empty, error, locked, disabled, and success states.

Define consistent colors, typography, spacing, corner radii, borders, shadows, icon sizes, easing, animation durations, modal layering, and sound feedback.

Support desktop, mobile, and gamepad. Use responsive layouts, scalable dimensions, safe-area awareness, readable text, and practical interaction targets.

Provide a reduced-motion option. Avoid excessive flashing, persistent camera shake, or effects that obscure gameplay. Critical UI must remain usable with animations reduced or disabled.

### 4.4 Required UI Feedback and Animation

Use `TweenService` and existing animation infrastructure where suitable. Define behavior for:

- Panel entrance and exit.
- Button hover, press, selection, and disabled states.
- Animated progress updates.
- Quest completion and reward reveal.
- Floor and room unlocks.
- Inventory and furniture actions.
- Match results, score changes, and rankings.
- Event banners, countdowns, and completion.
- Zen feedback that preserves its existing identity.

Prevent conflicting tweens, duplicate UI instances, connection leaks, and unnecessary continuous animations. Reuse interface instances when practical.

## 5. Feature A — Multi-Storey Office Tower

Build a modern headquarters with themed floors and meaningful destinations.

Requirements:

1. Preserve the existing boss roster and unlock requirements.
2. Do not bypass existing ground-floor, Senior-floor, or CEO unlock conditions.
3. Provide clear elevator, staircase, corridor, and floor navigation.
4. Show locked floors with readable requirements and progress.
5. Use modular, reusable floor and room templates.
6. Give each floor a coherent visual theme, lighting, signage, and furniture.
7. Keep collision, spawn areas, and paths safe and usable.
8. Maintain performance as the map expands.
9. Ensure locked content does not prevent new players from enjoying available content.
10. Avoid creating empty floors without a gameplay, social, or progression purpose.

## 6. Feature B — Career Progression and Personal Offices

Add a career progression system that complements rather than silently replaces the existing combat level.

Possible configurable titles:

- New Employee
- Junior Specialist
- Department Specialist
- Team Lead
- Department Manager
- Executive

Requirements:

- Define clear requirements for every milestone.
- Allow progress from quests, boss encounters, recreation, and cooperative activities.
- Unlock appropriate office access, furniture, cosmetics, titles, and destinations.
- Keep career progression separate from combat XP unless an integration is explicitly designed and documented.
- Do not grant automatic combat damage bonuses for career rank.
- Avoid excessive repetitive grinding for basic furniture.
- Persist progression safely and migrate existing profiles without data loss.
- Display career progress clearly in the player profile and quest UI.

Players should progress from a shared workspace to a personal desk and eventually a private office. The server must enforce office ownership, access permissions, and placement permissions.

> **Superseded by §21.3:** every player has their own open-space office from the start. Career progress unlocks furniture, decorations and titles instead of the office itself.

## 7. Feature C — Quests, Inventory, Furniture, and Customization

Create a configurable quest system supporting appropriate tutorial, daily, weekly, career, and event quests.

Example objectives:

- Organize office documents.
- Deliver coffee to NPC coworkers.
- Collect scattered office supplies.
- Complete a fictional IT troubleshooting puzzle.
- Defeat a specified boss.
- Reach Zen.
- Complete a recreational match.
- Finish an activity with another player.
- Participate in a daily event.

Requirements:

- Configurable identifiers, prerequisites, objectives, progress, completion, and rewards.
- Server-validated progress and reward claims.
- Duplicate-claim prevention.
- Reconnect and partial-progress handling.
- Clear objectives and immediate feedback.
- Varied activities that do not all require combat.
- Reasonable reset windows and reward limits.
- Solo alternatives where appropriate.

### 7.1 Furniture Inventory

Potential item categories:

- Desks and chairs.
- Monitors, keyboards, and lamps.
- Plants, cabinets, shelves, and sofas.
- Posters, rugs, and decorative objects.
- Trophies and cosmetic items.

Players may place only items they own. Furniture must obey valid bounds, rotation rules, collision rules, and protected navigation areas.

Implement:

- Placement previews.
- Rotation, repositioning, removal, save, and cancel actions.
- Clear invalid-placement feedback.
- Layout persistence.
- Server-side ownership and placement validation.
- Approved model templates instead of arbitrary client-supplied objects.
- Protection against duplication, invalid transfers, and unauthorized editing.

The customization UI should provide previews, category filters, placement controls, and responsive mobile interaction.

## 8. Feature D — Recreation Center and Pickleball

Create a dedicated modern recreation building. Begin with one complete sport—pickleball is the proposed first activity—rather than releasing many incomplete sports at once.

### 8.1 Pickleball Gameplay

Implement:

- Readable court lines, net, paddles, ball, and score display.
- Singles first; doubles can follow after the first mode is stable.
- Matchmaking or a suitable queue.
- Match start, countdown, scoring, victory, cancellation, disconnect, and rematch flows.
- Responsive ball movement and paddle animation.
- Clear audio and visual feedback on valid contacts and points.
- Match HUD, score summary, and return-to-campus option.
- Spectator behavior that does not interfere with active matches.

Define serve order, legal bounces, fault rules, scoring format, and match completion before implementation.

Use a physics approach that balances responsiveness with server-authoritative scoring. Do not accept a client-reported hit or score without validation.

### 8.2 Recreation Rankings and Rewards

> **Superseded in part by §21.2:** there are no Recreation Tokens. Fees and rewards use the existing coins; the token amounts below no longer apply.

Create a separate Recreation Rating system. Do not merge it into the existing boss score or combat XP.

Requirements:

- Record legitimate completed matches.
- Prevent duplicate results.
- Define a rating update formula.
- Support weekly or seasonal leaderboard snapshots.
- Issue top-10 rewards once per season.
- Cap participation rewards to reduce farming.
- Handle ties, disconnects, cancellations, and incomplete matches explicitly.
- Test coordinated rating abuse and invalid match requests.

Suggested reward structure, to be balanced through playtesting:

| Placement | Example reward |
|---|---|
| 1st | Champion trophy, 500 Recreation Tokens, champion title |
| 2nd | Silver trophy, 350 Tokens, finalist title |
| 3rd | Bronze trophy, 250 Tokens |
| 4th–10th | Placement decoration and 150 Tokens |
| Valid participation | Small, capped token reward |

These values are provisional. Keep sports rewards focused on prestige and customization, not permanent combat damage advantages.

Possible rewards include paddle skins, sports cosmetics, office trophies, display cabinets, titles, and seasonal decorations.

## 9. Feature E — Daily Events and Rotating Activities

Create a data-driven daily-event system.

Possible events:

- Coffee Rush.
- Office Supply Hunt.
- Boss Celebration.
- Recreation Tournament.
- Zen Challenge.
- Cooperative Office Makeover.
- Seasonal office events.

Every event definition should specify its ID, schedule, objectives, eligibility, reward pool, and display settings.

Requirements:

- Consistent server-authoritative schedules.
- UTC as the canonical schedule, with suitable local display.
- Event progress, countdown, completion, and reward UI.
- Handling for late joins, reconnects, expiration, and server restarts.
- Idempotent rewards.
- A fun core experience outside event windows.
- No excessive punishment for missing a day.

Random reward pools may include eligible buffs, pets or pet cosmetics where implemented, office supplies, furniture, cosmetic tokens, and event decorations.

Define probabilities and eligibility when random rewards are used. Keep rewards within a configured economy budget. Do not make essential progress depend on rare drops.

## 10. Feature F — Cooperative Office Challenges

Create optional, lighthearted team activities, such as:

- Coffee Emergency: deliver several orders.
- Paperwork Panic: find and sort documents.
- IT Rescue: complete a fictional troubleshooting puzzle.
- Office Makeover: contribute to a shared decoration goal.
- Monday Survival: complete a sequence of humorous objectives.

Requirements:

- Meaningful actions for each participant.
- Server-validated progress.
- Rewards based on genuine contribution, not idle presence.
- Solo alternatives where practical.
- Graceful handling of joins and departures.
- Fairness for players with different combat levels.
- No boss attacks or player damage.

Rewards may include tokens, furniture blueprints, pet cosmetics, titles, and team decorations.

## 11. Feature G — Office Showcase and Community Awards

Allow players to visit eligible offices, admire designs, and participate in themed contests.

Requirements:

- Public/shared versus private office access settings.
- No unauthorized modification of another player's furniture or inventory.
- Clear owner identity and approved achievements.
- Multiple saved layouts if feasible.
- Themed design contests.
- Voting limits and duplicate-vote prevention.
- Protection against obvious vote manipulation.
- Transparent contest rules.
- Rewards for creativity and achievement, not popularity alone.
- Appropriate reporting and moderation pathways.

Rewards may include trophies, wall plaques, titles, nameplate frames, and seasonal decorations.

## 12. Feature H — Shareable Moments and Acquisition

Create polished, shareable moments from actual gameplay:

- Group boss victories.
- Funny boss defeat moments.
- Recreation championship results.
- Office showcase cards.
- Career milestone celebrations.
- Event completion announcements.

Requirements:

- Build summaries from server-confirmed results.
- Use supported Roblox capture, invitation, and social capabilities.
- Respect privacy settings and platform restrictions.
- Do not assume private friend-list access or proof of external sharing.
- Do not reward fabricated external-share claims.
- Measure acquisition using available, approved attribution and analytics.
- Never require disclosure of personal information.

## 13. Architecture and Server Authority

Inspect and extend the existing architecture rather than imposing a new one without evidence.

Possible responsibilities include:

- QuestService.
- InventoryService.
- FurnitureService.
- OfficeOwnershipService.
- CareerService.
- RecreationMatchService.
- RecreationRatingService.
- DailyEventService.
- CooperativeMissionService.
- OfficeShowcaseService.
- RewardService.
- AnalyticsService.

These names describe proposed responsibilities, not guaranteed existing modules. Reuse equivalent existing systems wherever practical.

The server owns authoritative rewards, scores, item ownership, office permissions, progression, match results, and event completion.

The client handles presentation, input, previews, and cosmetic effects. Validate every remote request for input shape, permission, range, state, ownership, prerequisites, cooldowns, and rate limits.

Never accept arbitrary client-supplied prices, rewards, scores, object definitions, or Instance paths.

For cross-server systems, select Roblox services according to their current capabilities and limitations. Use durable persistence for important player data and rewards. Treat temporary memory and message delivery as coordination tools, not as the sole record of a reward that must never be lost.

Implement retry behavior, deduplication, idempotency, and recovery from partial failure.

## 14. Player Data and Migration

Preserve existing profile data, including relevant existing currencies, XP, levels, hammers, buffs/pets, Zen progression, leaderboard statistics, and other established fields.

Potential new data includes career progress, furniture inventory, office ownership, saved layouts, quest completion, event claims, recreation ratings, match records, season claims, and showcase settings.

Requirements:

- Inspect the actual current profile schema first.
- Define migrations before changing schemas.
- Use safe defaults for new fields.
- Preserve old profile data.
- Handle partial failures and retries.
- Prevent duplicate reward claims.
- Avoid excessive saving.
- Test throttling, player departure, and server shutdown.
- Never claim data safety without testing relevant failure cases.

## 15. Performance and Asset Standards

Profile and budget:

- Client and server frame time.
- Memory and instance counts.
- Network traffic and remote request frequency.
- Physics, animation, particles, and lighting.
- Asset loading and GUI object count.
- Persistence request volume.

Use instance streaming where appropriate. Reuse templates, pool short-lived effects when justified, and avoid creating instances continuously for repeated hits or UI updates.

Inspect third-party assets before use. Use original or properly licensed models, textures, animations, and sounds. Do not assume arbitrary Toolbox assets are safe or licensed.

Maintain an asset manifest with asset purpose, source, permission status, and implementation location.

## 16. Phased Implementation

### Phase 0 — Audit and Baseline
Inspect the source, map dependencies, identify risks, document existing behavior, and establish available tests and performance baselines.

### Phase 1 — GUI Foundation and Visual Design
Establish UI tokens, reusable components, animation standards, responsive layouts, and world-design blueprints.

### Phase 2 — Quest, Inventory, Furniture, and Career
Implement validated quest progress, inventory, furniture placement, saved layouts, career milestones, and profile migration.

### Phase 3 — Modern Office Tower
Build modular floors, navigation, boss-office placement, unlock indicators, and validated access.

### Phase 4 — Recreation Center
Implement pickleball, match state, scoring, ratings, seasonal leaderboards, and rewards.

### Phase 5 — Daily Events and Cooperative Missions
Implement event definitions, schedules, objectives, team progress, reward handling, and recovery.

### Phase 6 — Office Showcase and Social Sharing
Implement visit permissions, design contests, voting safeguards, and shareable achievement cards.

### Phase 7 — Integration and Release Readiness
Run regression, multiplayer, security, data migration, accessibility, and performance testing. Prepare release and rollback procedures.

Implement one phase at a time. After each phase, report actual results and satisfy its acceptance gate before continuing.

## 17. Testing Requirements

Test:

- New and existing player profiles.
- Multiplayer boss interactions.
- Invalid and repeated remote requests.
- Duplicate quest claims.
- Unowned furniture placement.
- Invalid room bounds.
- Unauthorized private-office access.
- Match disconnects and invalid scores.
- Duplicate sports rewards.
- Event expiration and late joins.
- Failed or throttled data saves.
- Profile migration.
- Mobile and gamepad UI.
- Reduced-motion mode.
- Lower-end device performance.
- Regression of hammer purchases, combat, Stress Meter, Zen, progression, and leaderboards.

Use automated tests where supported and manual Roblox Studio playtests for visual quality and end-to-end behavior.

Clearly distinguish passed, failed, untested, and blocked tests. Never fabricate test results.

## 18. Acceptance Criteria

A feature is not complete merely because code compiles.

Every feature must have a defined player-facing purpose, complete gameplay flow, polished GUI, appropriate animation and sound, server authority, reward rules, failure handling, relevant tests, performance validation, and documentation.

The final update must preserve the game's original stress-relief purpose. Bosses must never attack or damage players.

## 19. Required Phase Reports

At the end of each phase, report:

1. What was inspected.
2. What was implemented.
3. Files created or changed.
4. Existing systems reused.
5. New configuration values.
6. Data migrations.
7. GUI and animation changes.
8. Security controls.
9. Actual test results.
10. Known issues and risks.
11. Performance observations.
12. The next phase and its prerequisites.

Keep the code modular, readable, maintainable, and consistent with repository conventions. Do not leave placeholders disguised as completed features.

## 20. First Action

Begin with Phase 0 only.

Inspect the repository and `GAMEPLAY_RULES.md`. Produce the architecture audit, dependency map, risk register, UI/UX specification, test plan, and phased implementation plan.

Identify exact files and systems that must change, features that can reuse existing implementations, and technical limitations.

Do not begin large-scale implementation until the audit is complete.

The goal is to make Whack It Out! a polished, modern, socially engaging stress-relief experience combining funny bosses, recreational competition, career progression, quests, personal office customization, daily events, and cooperative activities—without losing the identity of the original game.

## 21. Owner Decisions (2026-10-09)

These answers from the owner override earlier sections. Values marked *(provisional)* are suggestions to balance in playtesting and must live in config modules.

### 21.1 Pickleball: challenges, modes and rules

**Modes:** Singles (1 v 1) and Doubles (2 v 2), both released together.

**Finding opponents (server-wide challenge):**
1. A player opens the Pickleball panel (at the recreation building or from the Menu), picks Singles or Doubles and presses **Challenge**.
2. The server announces it to everyone in the server with the existing notification card: "🏓 <Name> wants a Singles match! [Accept]". For Doubles the card shows the open places ("2 v 2, 1 of 4 joined").
3. **Singles:** the first player to accept becomes the opponent, and the match starts.
   **Doubles:** each accepter picks a team that still has room (the challenger's team gets 1 more player, the other team 2). The match starts when all 4 places are filled.
4. The server holds the lock on places: two players accepting at once can't both get the last one. A player can't accept their own challenge or be in two challenges or matches at once.
5. A challenge expires after 60 s for Singles and 90 s for Doubles *(provisional)*. The challenger can cancel. Each player has one open challenge at a time, with a 30 s cooldown between challenges *(provisional)*, so there's no spam.
6. A Settings toggle lets a player hide challenge notices.
7. When the match starts, players are moved to a free court. If none is free, the challenge waits in a queue and shows its position. Start with 2 courts *(provisional)*.

**Rules: standard pickleball (USA Pickleball rulebook)**
- One game to **11 points, win by 2**. Only the serving side scores (side-out scoring).
- **Serve:** underhand, from behind the baseline, diagonally cross-court. It must clear the non-volley zone (the "kitchen") and its line and land in the diagonal service court. One attempt per serve.
- **Singles serve position:** the server serves from the right when their score is even, from the left when it's odd.
- **Doubles serving:** both partners serve before a side-out, except at the start of the game. The first serving team gets only one server ("0-0-2"). The score is shown as three numbers: serving team, receiving team, server 1 or 2.
- **Two-bounce rule:** the serve must bounce before it's returned, and the return must bounce before it's hit back. After that, volleys are allowed.
- **Non-volley zone:** the 7-foot area next to the net on each side. A player may not volley while standing in it or touching its line.
- **Faults:** ball into the net, landing out (a ball on a line is in, but a serve landing on the kitchen line is a fault), two bounces before a return, a volley from the kitchen, or a serve to the wrong court.
- **Court:** 20 × 44 studs (1 stud ≈ 1 ft), with the kitchen 7 studs deep on each side and the net 3 ft high at the sidelines and 34 in at the centre.
- **Roblox adaptation:** the server owns the ball (a deterministic flight path that the server simulates and the clients draw). A player swings, and the server accepts the hit only if the ball is within paddle reach at that moment. Aim is a client *request* that the server clamps to allowed angles and power. Line calls, bounces, faults and the score are server-only.

**Disconnects and cancellations:**
- If anyone leaves before the first point is scored, the match is cancelled and every fee is refunded.
- If someone leaves after that, their team forfeits. In Doubles, the remaining partner may finish alone or forfeit. The leaver gets no consolation prize.
- If a match hits a 20-minute limit *(provisional)*, the side ahead wins. A tied match is cancelled with refunds.

### 21.2 Fees and rewards: existing coins only

There is **no new currency**. Pickleball uses the existing `Coins`, through `SessionService.trySpendCoins` / `addCoins`.

| Item | Singles | Doubles (per player) |
|---|---|---|
| Entry fee (charged when the match starts, not when accepting) | 10 coins *(provisional)* | 10 coins *(provisional)* |
| Winner | 60 coins *(provisional)* | 60 coins *(provisional)* |
| Loser (consolation) | 20 coins *(provisional)* | 20 coins *(provisional)* |
| Office supply drop | every player rolls once from the office-supply pool; the winners' pool has better odds | same |

- The server issues the rewards. The fee is a coin sink, not a pot paid by the losers, so players never transfer coins to each other.
- A player can only start or accept a challenge if they have the fee. The server checks again at the start.
- **Anti-farming:** each player gets at most 10 rewarded matches per UTC day *(provisional)*, and the same set of opponents is rewarded at most 3 times per day *(provisional)*. After the cap, matches are "friendly": no fee, no coins, no drop, no rating change.
- **Office supplies** are the furniture and decoration items in §7.1. They go into the player's furniture inventory. The drop table and its odds must be published in config.
- The Recreation Rating and seasonal leaderboard (§8.2) stay. Top-10 season prizes are trophies, titles and decorations, plus coins *(amounts provisional)*.

### 21.3 Personal offices

**Every player gets their own office from the start.** It is an empty open-plan room they furnish however they like. Career progress unlocks furniture and decorations, not the room itself.

**Slots (Claude's suggestion, accepted by the owner):**
- **One slot per player place in the server.** The slot count equals `Players.MaxPlayers`, read at startup and never hard-coded, so every player always has an office. A 12–16 player server size is recommended.
- Slots stand in an **Office Wing** that is far from the main map and invisible from it. Players get there by teleport, so the map's fixed positions and their specs stay unchanged.
- Each slot is an open-plan room, about **40 × 40 studs**, with windows, a door and a nameplate ("<Name>'s Office"), plus a protected entry area near the door where nothing can be placed.
- A free slot is assigned on join and released on leave. The layout is saved in the player's profile (schema v9: a list of `{ItemKey, X, Z, Rotation}` relative to the room) and rebuilt in any slot.
- **New players get a free starter kit** (desk, chair, plant) so the room is never just bare.
- **Placement:** owned items only, from approved templates, on a 1-stud grid with 90° rotation. Items must stay inside the room and outside the entry area, and can't overlap. The server checks everything. There is a limit of 60 items per office *(provisional)*.

**Getting there and visiting:**
- A **🏢 My Office** HUD button (and a Menu entry) teleports the player to their office. A **Return** button takes them back to the lobby.
- An **Offices** button opens the **Office Directory** panel. It lists every player in this server who has an office: avatar, name, office name and a **Visit** button. Players choose an office from the list, and the button teleports them to that office's entry area.
- **Privacy** (owner setting): Public (default), Friends only, or Private. The server enforces it, both when the visit starts and while the visitor is inside.
- Visitors can look around but never edit. Edit mode exists only for the owner, inside their own office.
- Phase 6 may later add visits to offline players' offices across servers (a read-only copy of the saved layout). It is out of scope for the first release.

### 21.4 Levelling rework (owner decision 2026-10-09)

The owner found levelling pointless (no unlocks after Level 10, damage that made hammers irrelevant, no cap). Decided, all of it:
- **Max level 100**, a steeper curve after Level 10 (Level 10 unchanged; Level 100 ≈ 127 h of ideal farming), XP still counting on the Top Level board after the cap.
- **Level damage** +3 per level up to Level 10, then +1 (Level 100: +117 instead of +297).
- **Rewards:** coins every level (20 × level); every 5 levels a title, a hammer trail or a Zen glow colour; the Golden name tag at 100; level requirements on the top four coin hammers.
- **No player loses a level** (one-time XP protection).
- **Career = level titles.** The separate Career rank of §6 is dropped: the level titles (Intern … Chief Calm Officer) are the career, and quests, pickleball and co-op give XP. This replaces §6's "keep career progression separate from combat XP".
- Office themes and level-reward furniture join the reward track with Phase 2a.

Details: `docs/GAMEPLAY_RULES.md` "Player Level", "Level bonuses", "Level rewards".
