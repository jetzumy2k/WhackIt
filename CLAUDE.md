# WHACK IT OUT! — Claude Code Master Instructions

## Mission
Develop **WHACK IT OUT! — Stress Relief Simulator**, a fictional Roblox cartoon game where players hit humorous fictional "annoyance bosses" with a hammer, reduce their HP and Stress Meter, earn rewards, and replay.

## Non-negotiable content rules
- Fictional targets only.
- No real politicians, public figures, recognizable real people, protected groups, or real-world political conflicts as attack targets.
- No gore, realistic injury, torture, or graphic violence.
- Preserve the humorous stress-relief concept through fictional everyday annoyances.

## Engineering priorities
1. Roblox safety/compliance
2. Server authority and exploit resistance
3. Data integrity
4. Correctness
5. Performance
6. Maintainability
7. Developer convenience

## Technology
- Roblox Studio + Luau
- Windows 11 64-bit
- VS Code + Claude Code
- Git
- Rojo
- Wally
- Selene
- StyLua
- TestEZ
- Optional Rokit/Blender

Roblox Studio is the runtime/editor; VS Code + Claude Code is the primary source-code workflow.

## Preferred repository
```text
WHACK-IT-OUT/
├── CLAUDE.md
├── README.md
├── default.project.json
├── wally.toml
├── selene.toml
├── stylua.toml
├── src/
│   ├── ReplicatedStorage/{Shared,Config,Remotes}
│   ├── ServerScriptService/{Services,Controllers}
│   ├── StarterPlayer/StarterPlayerScripts/Controllers
│   └── StarterGui/Screens
├── tests/{Unit,Integration,Security}
├── assets/
└── docs/
```

## Architecture
Server Services: BossService, CombatService, StressService, PlayerDataService, RewardService, PurchaseService, SessionService, RemoteController.
Client Controllers: InputController, GameplayController, UIController, FeedbackController, AudioController.
Shared: types, constants, configuration, safe utilities.

## Server-authority rule
Client requests actions; server decides results.
Never trust client-provided:
- damage
- HP
- score
- coins/currency
- rewards
- unlocks
- win state
- purchase completion

Every remote must validate player, payload type/size, state, ownership, cooldown/rate limit, numeric bounds, and context.

## Luau standard
All code uses `--!strict`.
Use typed domain models, explicit public return types, guard clauses, no implicit globals, and no unnecessary `any`.
Keep gameplay values in configuration modules.

## Data standard
Use a dedicated PlayerDataService with schema versioning, validation, defaults, migrations, safe retries, and failure handling. Never overwrite trusted data with fallback defaults after an uncertain load.

## Testing gate
A feature is complete only after relevant formatting/static checks, tests, Studio playtest, multiplayer/security checks where applicable, and diff review. P0/P1 defects block release.

## Claude operating procedure
Before changing code:
1. Read this file.
2. Read the relevant skill in `.claude/skills/`.
3. Inspect existing implementation and dependencies.
4. State the smallest viable change.
5. Implement only the necessary files.
6. Run relevant checks/tests.
7. Inspect the diff.
8. Fix regressions.
9. Update documentation.
10. Report exactly what was changed and verified.

Do not rewrite unrelated code or add dependencies without justification.
Do not claim verification that was not actually performed.

## Definition of Done
Implementation + security review + tests/justification + error handling + acceptable performance + documentation + formatting/lint + clean understandable diff.

## Available skills
See `.claude/skills/*/SKILL.md`. Use the most specific skill for each task.
