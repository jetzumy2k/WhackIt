# Development Workflow
1. Inspect existing code.
2. Read the relevant skill.
3. Define acceptance criteria.
4. Implement the smallest clean change.
5. Format/lint/type-check: `scripts/check.ps1` (see below).
6. Run tests: `scripts/check.ps1 -Tests`, or open `build/tests.rbxl` in Studio and press Run (F8).
   Close the tests place in Studio (File → Close Place, don't save) before re-opening a new
   build: Studio keeps the old copy in memory and "Open from File" won't reload it.
7. Playtest in Studio.
8. Security-test remote-facing systems.
9. Review the diff.
10. Update documentation.

## First-time setup
```powershell
rokit install      # rojo, wally, stylua, selene, luau-lsp, run-in-roblox (pinned in rokit.toml)
wally install      # TestEZ into DevPackages/ (dev-only; never shipped)
```

## Checks (`scripts/check.ps1`)
| Gate | Tool | Scope |
|---|---|---|
| Format | StyLua (`stylua.toml`, LF endings enforced by `.gitattributes`) | `src`, `tests`, `scripts` |
| Lint | Selene (`selene.toml`; tests use `selene.tests.toml` + `testez.yml` for TestEZ globals) | all Luau |
| Type-check | luau-lsp `analyze`, strict via `.luaurc`, Roblox defs downloaded to `globalTypes.d.luau` matching the pinned luau-lsp version | `src`; `tests`+`scripts` also load `types/testez.d.luau` |
| Build | Rojo | `default.project.json` -> `build/WhackItOut.rbxl`, `test.project.json` -> `build/tests.rbxl` |
| Unit tests (`-Tests`) | TestEZ via run-in-roblox | every `*.spec.luau` under `tests/` |

CI (`.github/workflows/ci.yml`) runs the same `scripts/check.ps1` on every push to `master` and every pull request. It cannot run TestEZ (no Studio on CI runners), so run the specs locally before merging.

run-in-roblox listens on fixed port 50312. If Windows has reserved it
(`netsh interface ipv4 show excludedportrange protocol=tcp`), run the tests from Studio instead.

## Runtime layout
- Server: `src/server/Main.server.luau` is the only Script. Services (`src/server/services`) and server controllers (`src/server/controllers`) are ModuleScripts.
- Server-only config: `src/server/config` → `ServerScriptService.Config` (never replicated to clients; not booted). Abuse thresholds and anything clients must not read go here; display/gameplay values clients may see go in `src/config`.
- Client→server remotes are bound only through `RemoteController` and validated with `Shared/Validate`; see `docs/REMOTE_CONTRACTS.md`.
- Client: `src/client/Main.client.luau` is the only LocalScript. Controllers (`src/client/controllers`) are ModuleScripts.
- Both boot through `Shared/Lifecycle`: every module's `init()` (must not yield) runs before any `start()` (may yield). Within a folder, modules load in name order.
- Folders in `default.project.json` use optional `$path`s, so an empty/missing source folder still builds as an empty Folder.
