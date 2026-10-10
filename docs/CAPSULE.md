# Lucky Capsule Machine

Added 2026-10-10 (recreation games 2/3; owner choice "Lucky Capsule Machine" instead of a betting slot
machine). A big gumball-style machine at the Recreation Center entrance (east, across from the Pet
Arena). **Not a bet:** every spin costs the same fixed coin price and **every spin wins a prize**.

Code: `Config/CapsuleConfig`, `Shared/CapsuleRules` (pure, unit-tested), `Services/CapsuleService`,
`Controllers/CapsuleController`, the machine in `Lib/CourtBuilder`, a 🎁 Capsules button on the Social
page.

## Why it isn't a slot machine
The owner first asked for a machine where you bet points to win more. A wager-and-lose mechanic is
casino-style simulated gambling, which Roblox treats as sensitive content (it may need declaring in the
experience questionnaire and can raise the age rating). This machine keeps the fun without that:
- a fixed price, no bet size, no "lose everything" outcome: every spin pays something;
- **coins only**: coins can't be bought with Robux and the machine never takes Robux;
- every prize's odds are shown before spinning (normal and lucky spin);
- a daily spin limit;
- on average it pays back fewer coins than it costs (spec-checked), so it's a coin sink with fun
  items, not a way to farm coins.

## Playing
Level 5+. Walk up to the machine (prompt "Spin") or 🏢 Social → 🎁 Capsules. **200 coins a spin, 10 spins
a day (UTC).** The **last spin of the day is lucky**: only Rare, Epic or Jackpot prizes. The window shows a
capsule that wobbles while the handle on the machine turns, then pops open in the prize's tier colour.
Rare and better prizes get a celebration card.

## Prizes and odds (`CapsuleConfig.Prizes`, weights out of 1000)
| Prize | Tier | Chance | Lucky spin |
|---|---|---|---|
| 100 coins | Common | 26.0 % | – |
| 250 coins | Common | 18.0 % | – |
| 400 XP | Common | 16.0 % | – |
| +10 % XP boost (30 min) | Uncommon | 9.0 % | – |
| +5 % Damage boost (30 min) | Uncommon | 8.0 % | – |
| +5 % Crit Damage boost (30 min) | Uncommon | 7.0 % | – |
| 500 coins | Rare | 6.0 % | 37.5 % |
| An office supply | Rare | 6.0 % | 37.5 % |
| A Common Egg | Epic | 2.5 % | 15.6 % |
| A Rare Egg | Epic | 0.8 % | 5.0 % |
| JACKPOT: 3,000 coins | Jackpot | 0.7 % | 4.4 % |

Boosts and eggs go to the 🎒 Bag; the office supply (paddle rack, ball bucket, desk fan, mini fridge,
zen bonsai, snack machine or neon CALM sign) to office storage. Average coins back per spin: 122 of 200.

## Safety and data
- `Capsule.Spin` takes no arguments; the server checks level, spins left and coins, takes the coins
  (`SessionService.trySpendCoins`, never below 0), rolls with its own `Random` and pays at once. The
  handler never yields, so double taps can't spend twice. Every spin is in the player's history
  ("Lucky Capsule: …").
- Player data v19 `Capsule`: the day, spins that day, total spins.
