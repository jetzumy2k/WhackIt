# Pets

Added 2026-10-08. Players get **eggs**, hatch them in an **incubator** in 60 seconds, and equip one
**pet** that follows them and boosts their XP, damage or crit damage.

```
Egg (Store, found outside, or an event boss drop) -> Bag
  -> Incubator (60 s, keeps going while you play) -> pet hatches into your pets
  -> Equip (Player Panel -> Pets) -> it follows you and its buffs apply
```

Code: `Config/PetConfig` (every balance number and position), `Shared/PetRules` (pure rules,
unit-tested), `Services/PetService` (eggs, incubators, hatching, world eggs, equip),
`Lib/IncubatorBuilder` (the Pet Incubation Center), `Lib/PetVisual` and `Controllers/PetController`
(pets, incubator displays, egg picker), the Player Panel **🐾 Pets** tab, the Store **Eggs** tab and
the Bag. Pets plug into the existing systems: eggs are Bag items, pets are player data (schema v8),
and buffs go through `BuffService`. There is no new DataStore, inventory, store or damage formula.

## Rarities and species (`PetConfig.Species`, `EggOdds`)
| Egg | Hatches (odds) | Buffs |
|---|---|---|
| **Common** | 🐶 Dog 25 %, 🐱 Cat 25 %, 🦋 Butterfly 20 %, 🪲 Beetle 15 %, 🐞 Ladybug 15 % | one of its own: Dog +3 % XP, Cat +3 % Damage, Butterfly +5 % Crit Damage, Beetle +3 % Damage, Ladybug +5 % Crit Damage |
| **Rare** | 🐰 Rabbit 35 %, 🐻 Bear 25 %, 🐵 Monkey 25 %, 🦜 Toucan 15 % | one of its own (Rabbit +6 % XP, Bear +6 % Damage, Monkey +10 % Crit Damage, Toucan +6 % Damage) **plus one random buff** of another kind: +2-5 % XP, +2-5 % Damage or +3-8 % Crit Damage |
| **Mythical** | 🐉 Dragon 40 %, 🔥 Phoenix 40 %, 🦄 Unicorn 20 % | two of its own: Dragon +10 % Damage +10 % Crit Damage, Phoenix +10 % XP +6 % Damage, Unicorn +8 % XP +12 % Crit Damage |

- **Crit** means crit damage, like the store's Crit Damage boosts: extra damage when a hit crits.
- **Balance:** a pet buff is at most what the strongest timed boost of that kind gives, and rarer pets
  are stronger in total. Specs check both, and that each egg's odds add up to 100.
- A pet's buffs, including a Rare pet's random one, are rolled **once** by the server when its egg
  goes into an incubator, and saved with that pet. Equipping, respawning, rejoining or opening the
  UI never rerolls them. Two Rabbits are two pets with their own ids (`pet_<n>`) and their own
  random buff.

## Eggs
Eggs are store items (`egg_common`, `egg_rare`, `egg_mythical`, StoreConfig Kind `"Egg"`) kept in
the **Bag** until they go into an incubator.
- **Store (Robux, Eggs tab):** suggested 49 / 149 / 399 R$. What hatches is random, so eggs are
  **paid random items**. Like the Mystery Hammer, the tab and the purchase exist only for players
  whose `PolicyService` allows paid random items, and the tab shows the odds. Delivery uses the
  existing `ProcessReceipt` handler (one egg into the Bag). Eggs can't be gifted. The three
  Developer Products still need creating; until their ids are in `StoreConfig` the tab says
  "Coming soon".
- **World eggs (free):** see below. Only Common and Rare appear on their own.
- **Boss drops:** an admin's **Boss Drop Event** can drop `egg_common` or `egg_rare`
  (docs/EVENTS.md), which makes it a "pet drop event". Never Mythical.

## Incubators
Six incubators stand in the **Pet Incubation Center** on the lawn east of the Front Plaza, facing the
walkway in front of the building, under a sign: "🐾 PET INCUBATION CENTER / Place your Egg into an
Incubator! / 60 seconds to hatch!" (`PetConfig.Incubators`, spec-checked to be clear of walkways,
props, areas and event-boss slots).
- **Place an egg:** press **E** ("Place Egg") at a free incubator, or tap **Incubate** on an egg in
  the Bag while standing within 14 studs of one. With several kinds of egg, a small picker asks
  which one.
- **One egg per player at a time**, and one per incubator. A busy incubator offers no prompt, so
  nobody can touch another player's egg. Max 100 pets; hatching is refused when full.
- **The timer never pauses or resets.** The server saves the start and end time with the player's
  data (`Incubation`) the moment the egg goes in, together with the pet it will hatch, which is
  kept hidden from the client. Walk away, open menus, die or leave: it keeps running.
- **Display (each client):** "🥚 RARE EGG / Incubating... 00:42 / progress bar / Owner: July",
  updated 4 times a second within 90 studs. When it ends: the egg shakes, a few sparkles pop, the
  pet appears for a moment, and the screen says "✨ EGG HATCHED! 🐰 Rabbit".
- **Hatching:** at the end time the server moves the pet into the player's pets in one step that
  never yields, so it can't be created twice. The owner gets "✨ EGG HATCHED! Your 🐰 Rabbit is
  ready!" with its buffs and an **EQUIP** button. Their first pet is equipped automatically. The
  incubator frees up 5 seconds later.
- **Leaving and rejoining:** leaving frees the incubator display, but the egg stays in the player's
  data. On rejoin (any server, after restarts too) it goes back into a free incubator with the time
  it really has left, or hatches at once if it finished while they were away. If every incubator is
  busy it still hatches on time and shows in the Player Panel.

## World eggs
- Every **2 hours on the UTC clock** (00:00, 02:00, ...), every server places one egg if none is
  still out there: **Common 80 % / Rare 20 %** (`WorldEggRarities`), at a random one of 10 safe spots
  on the outdoor walkways (`WorldEggSpawnPoints`; markers in
  `Workspace.PetCenter.OutdoorEggSpawnPoints`). The spots avoid the building, boss offices, event-boss
  slots, the spawn and the incubators (spec-checked). One wait per interval, no polling loop.
- Everyone in the server sees "🥚 NEW EGG FOUND! A Rare Egg has appeared somewhere outside the
  office! Find it and take it to an Incubator!", through the existing announcement card. The exact
  spot isn't given.
- **Easy to spot once you're near:** the server sets the egg on the real ground under its spot
  (a downward ray when it spawns), so it never ends up inside the terrain. It floats 1 stud up,
  is 2 × 2.6 studs, bobs gently, has a soft white outline (hidden behind walls) and a few
  sparkles, more for rarer eggs, and shows a small 🥚 marker within 60 studs
  (`PetConfig.WorldEggSize`, `WorldEggHover`, `WorldEggMarkerDistance`). There are no lights.
  **Claim Egg** (hold E): the first claim the server receives wins. The egg is marked claimed and
  removed in the same step as it goes into that player's Bag, and everyone else sees "<name> found
  the Rare Egg!". The next egg waits for the next scheduled time.
- **Admins** (Admin Panel → Events → World eggs) can place one now in their server, of any rarity,
  Mythical included for special events. At most 3 eggs are out at once. Admins have no tools to
  change anyone's pets or eggs.

## Egg hunts (2026-10-08)
An admin's **Egg Hunt** event (Admin → Events, docs/EVENTS.md) spawns eggs of one tier (Common, Rare
or **Mythical**) every 2-60 minutes while fewer than its 1-5 maximum are out, between its start and
end. These can be scheduled ahead and saved with the other events (all servers, survives restarts).
`PetService` runs one thread per running hunt that wakes once per interval (no polling). Hunt eggs
use the world egg spots and the normal claim (first claim wins, into the Bag). When the hunt ends,
is stopped or is force-removed, its thread stops and its unclaimed eggs vanish. The normal 2-hour
eggs carry on as before.

## Equipping and following
- **Player Panel → 🐾 Pets (redone 2026-10-08):**
  - the incubating egg with a live countdown and progress, and the eggs in your Bag;
  - a **Pet details** card for the selected pet (the equipped one at first): its name, rarity in its
    colour, type (Ground, Hopping, Crawling bug or Flying, its movement from `PetConfig`), buffs with
    values, and status (✓ EQUIPPED or in your pets), with **EQUIP PET** or **UNEQUIP PET**;
  - **My pets:** cards in a grid (several per row on desktop, one or two on phones), the equipped pet
    marked ✓ and listed first, then the rarest. Tap a card to select it; on desktop, hovering shows
    its details.
- **Equip and unequip** go through `Pets.Equip` (an owned pet id, or `""` to put it away). The server
  checks the pet is the player's. Buffs are never added to or removed from a stored total: every hit
  and every XP reward reads the equipped pet's saved buffs fresh (`BuffService`). So switching,
  re-equipping, respawning or rejoining can't stack a pet's buffs or remove anyone else's bonuses
  (level, hammer, boosts, events).
- Only **one** pet is out at a time. Equipping another puts the old one away: it stays owned.
- The equipped pet is published as Player attributes (`PetSpecies`, `PetRarity`). **Each client
  draws everyone's pets locally**: anchored parts that never collide, block raycasts or fire
  touches, so they can't push players, block doors, NPCs, incubators or bosses, or affect hammer
  hits (boss targeting is by distance). One visual pet per player: equipping another, putting it
  away, respawning or leaving always removes the old model first, glitter included.

## Looks and movement (redone 2026-10-08)
Code: `Lib/PetVisual` (bodies, skeleton, poses, glitter), `Lib/PetMotion` (following and behaviour,
pure and unit-tested), `Controllers/PetController` (gathers the inputs, ground rays, moves every pet).
Per-species settings are in `PetConfig.Species` (`Movement`, `Follow`, `FlyHeight`, `FlapRate`,
`Look`) and glitter in `PetConfig.Glitter`. The pet's data, buffs and server logic are untouched.

**Why procedural, not Animation assets:** Roblox `Animation` objects need animations uploaded to
an account and Motor6D rigs on unanchored, physics-driven parts. Pets here are light part-built
models, so each one has a small skeleton instead. Its parts hang off the **root** (legs, from the
hips), the **torso** (body, tail, wings) or the **head** (face, ears, horns, antennae). Each frame,
`PetVisual.pose` turns the pet's state into CFrames for every part. No Humanoid, Animator, Motor6D
or physics is involved, and no animation is ever "restarted": states blend smoothly.

| Movement | Pets | How it moves |
|---|---|---|
| Ground | Dog, Cat, Bear, Monkey, Unicorn | four legs in a diagonal gait; the body bobs with each step and leans a little into a run; the head nods with the stride |
| Hopping | Rabbit | moves in hops (lift and forward lean follow the gait), ears sweep back on each hop |
| Crawling | Beetle, Ladybug | six legs in a tripod gait, quick short steps, a slight body sway, antennae swaying |
| Flying | Butterfly, Toucan, Dragon, Phoenix | flies at its height over the ground under it (Butterfly 3.2, Toucan 3.6, Phoenix 4.0, Dragon 4.4 studs), bobs gently, banks into turns, flaps faster when flying than hovering; the Butterfly has four wings and drifts lightly around its spot; the Dragon beats slowly and swings its tail; the Phoenix fans three tail feathers |

**States:** Idle, Walk and Run for walkers, Hover and Fly for flyers. The stride blends from 0
(standing) through 1 (walking, the owner's walk speed) to 2 (running, sprint speed). **Legs cycle
with the distance the pet actually covers**, so feet never slide. Walking can't override idle and
the other way round: every motion is weighted by the stride.

**Following:** each pet keeps to its own spot beside and behind its owner, further away for bigger
pets (Butterfly about 3 studs, Dog 4.3, Bear 5.3, Dragon 5.7). It speeds up with its owner and a
little more when it falls behind, eases in as it arrives, and stops when the owner stops. It turns
toward where it's going at a limited rate (about 290°/s walking, 400°/s running) and only moves as
fast as it faces its way, so it never walks sideways or backwards, spins or jitters. When the owner
stops it settles facing the same way.

**Ground:** walkers stand on the ground under them. A downward ray roughly 8 times a second per
nearby pet ignores characters, pets, boss hitboxes and the incubators, and the height eases in
between rays. If nothing is under the pet, the owner's feet height is used. This handles terrain,
paths, steps and slopes, and nothing floats, sinks or falls.

**Safety:** a pet more than 40 studs from its owner (teleport, the Executive Elevator, a respawn,
lag) is put back in its spot once. It never teleports frame by frame. A new character puts the pet
back beside the owner, so respawning never leaves a pet behind or makes a duplicate.

**Standing still:** the pet breathes, and every few seconds does one small thing: looks around,
looks at its owner, sits (Dog, Cat, Bear, Monkey and Unicorn, after about 6 s of standing), does a
little hop (Rabbit), flutters (Butterfly) or gives a few stronger wing beats (big flyers). Ears
twitch now and then. A Dog wags fast; a Cat sways its tail slowly.

**Boss hits:** when its owner lands a hit (`Combat.CombatFeedback`), the pet is briefly excited for
about a second: a little hop, a faster wag, or a quick flutter or wing beat. Pets never attack, deal
damage or touch boss health; they only give their buffs.

**Glitter:** one small `ParticleEmitter` per pet (sparkle texture), emitting inside its body. There
are no lights and no post-processing.

| Rarity | Sparkles per second | Look |
|---|---|---|
| Common | 1 | tiny white and gold |
| Rare | 1.8 | small soft blue and white |
| Mythical | 3 | gold, lilac and white, a little brighter (light emission 0.45) |

Phones get half. The emitter is inside the pet's model, so it goes away with the model.

**Performance:**
- **One `Heartbeat` per client:** it moves every pet with a single `Workspace:BulkMoveTo` and stops
  early when no pet is out.
- **Distance tiers:** pets within 70 studs of the camera update every frame, pets at 70-150 studs
  update 10 times a second, and pets further away aren't updated at all.
- **Ground rays:** about 8 per second per nearby pet, with the exclusion list refreshed once a second.
- **Nothing heavy:** no physics, pathfinding, Humanoids, lights or server parts.
- **Size:** each pet is 7-16 parts (spec-checked at 20 or fewer).

## How buffs combine (`BuffService`)
Pet buffs are modifiers to the existing formulas. They add to the bonuses already there, so nothing
overwrites anything:
```
damage bonus  = Damage boost + Mystery Hammer bonus + pet Damage
crit damage   = base +50 % + Mystery Hammer crit + Crit Damage boost + pet Crit Damage
XP            = score x XpRewardMultiplier x (1 + XP boost + pet XP) x XP event multiplier
```
Hit damage is still `CombatRules.hitDamage` with its usual half-up rounding: 35 base with a +15 %
pet hits for round(35 × 1.15) = 40. Example XP: 100 with a +10 % XP pet is 110. Score and coins
are never boosted.

## Data (player data, schema v8)
`Pets: { [pet_<n>]: { Species, Rarity, Buffs = { { Kind, Percent } }, CreatedAt } }`,
`NextPetNumber`, `EquippedPetId` (`""` = none), and
`Incubation: { EggKey, Rarity, StartedAt, EndsAt, IncubatorIndex, Pet }?`. Existing players start
with no pets and nothing incubating; nothing else changes. Loading keeps every valid pet (buffs
clamped, never rerolled), unequips a pet that isn't owned, never reuses an id, and gives the egg back
if a saved incubation is broken. See docs/DATA_SCHEMA.md.

## Security
Clients only ask: `Pets.Equip(petId)` (must be one of your pets), `Pets.Incubate(eggKey,
incubator?)` (must be an egg in your Bag, you at a free incubator within reach, nothing already
incubating), and the prompts, whose `Triggered` gives the server the real player. Species, rarity,
buffs, ids, timing, hatching, world-egg rarity and claims are decided and checked on the server. The
admin egg spawn checks admin rights. See docs/REMOTE_CONTRACTS.md.

## Extending
Ideas that fit as extensions, none hard-coded:
- **Egg Hunt:** a shorter interval while an event runs. Add an event type whose effect query
  `PetService.start` reads.
- **Mythical Egg Event:** an admin places one now (already possible).
- **Pet XP / Pet Drop:** Boss Drop events with eggs (already possible).
