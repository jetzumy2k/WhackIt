# Pet Arena

Added 2026-10-10 (recreation games, owner choice "Pet Arena, turn-based"). Cartoon pet battles at the
Recreation Center: your pet against a CPU trainer ladder or another player's pet. Nobody gets hurt:
a pet that runs out of **Pep** just gets dizzy.

Code: `Config/PetArenaConfig`, `Shared/PetArenaRules` (pure, unit-tested), `Services/PetArenaService`
(every battle runs on the server), `Controllers/PetArenaController` (window, battle screen), the
🐾 PET ARENA kiosk in `Lib/CourtBuilder` (west of the Recreation Center entrance), a 🐾 Pet Arena button
on the Social page.

## Playing
1. Walk to the 🐾 PET ARENA sign at the Recreation Center (or 🏢 Social → 🐾 Pet Arena).
2. Pick your fighter: one of your pets (its battle stats are shown).
3. 🏆 **Trainers**: battle the five CPU trainers in order, or 🤝 **Challenge** a player in the server
   (they get a card with ACCEPT; their picked pet fights).
4. Each round pick a move. The battle screen shows both pets on a little stage with Pep bars:
   - 💥 **Boop**: takes Pep from the other pet. 🍀 Lucky boops do 1.5×.
   - ⚡ **Charge**: your next Boop does 2× (the pet glows).
   - 🛡️ **Guard**: a boop on you this round only does 40 % (a bubble appears).
   Both pets choose at the same time; the faster pet acts first. Boops lunge and the target wobbles;
   the dizzy pet spins. After 20 rounds the pet with the bigger share of its Pep left wins.
5. 🏳️ gives up. Against a player, a pet whose trainer doesn't choose within 15 s Boops.

## Battle stats (`PetArenaRules.statsFor`)
| | Common | Rare | Mythical |
|---|---|---|---|
| Pep | 100 | 115 | 130 |
| Power (boop) | 12 | 14 | 16 |
| Speed | 10 | 12 | 14 |

Its buffs make each pet different: **Damage** +3 % Power per 1 %, **XP** +2 % Pep per 1 %, **Crit
Damage** +1 % lucky-boop chance per 1 % (from 5 %, at most 35 %). Flyers are +3 speed, hoppers +2,
crawlers −1.

## Trainers (`PetArenaConfig.Trainers`)
| # | Trainer | Pet | Strength | Style | Reward (first win today ×2) |
|---|---|---|---|---|---|
| 1 | Intern Ivy | Hamster (Common) | 85 % | random | 40 coins · 120 XP |
| 2 | Barista Ben | Frog (Common) | 100 % | careful (guards when low) | 70 · 220 |
| 3 | IT Support Ian | Owl (Rare) | 105 % | bold (charges, never guards) | 110 · 360 |
| 4 | Manager Mia | Tiger (Rare) | 115 % | clever (guards a charged pet, punishes guarding) | 160 · 520 |
| 5 | Director Dee | Celestial Lion (Mythical) | 115 % | clever | 250 · 800 + an office supply (first win each day) |

Beat each trainer to unlock the next (saved). Up to **10 rewarded trainer wins a day** (UTC).

## Player battles
Winner 90 coins · 300 XP, loser 30 · 100 XP. Rewarded **5 battles a day**, at most **twice against
the same player** (so friends can't farm each other). A draw pays nothing. Leaving mid-battle loses it.

## Safety and data
- The client only sends a trainer number, a pet id, an opponent's UserId, a move and yes/no; stats,
  rounds, luck and rewards are all server-side (`PetArenaRules` with the server's `Random`).
- Player data v18 `PetArena`: trainers beaten, today's rewarded wins and player battles (per opponent),
  total wins.
- Not in this version: battle history, ranked ladder, more than one pet per side.
