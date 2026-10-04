# Player Data Schema
Current schema should be versioned. Example:
```lua
type PlayerData = {
    SchemaVersion: number,
    Coins: number,
    TotalHits: number,
    TotalBossesDefeated: number,
    UnlockedBosses: {[string]: boolean},
    OwnedHammers: {[string]: boolean},
    SelectedHammer: string,
}
```
All loaded data must be validated and migrations tested before production.
