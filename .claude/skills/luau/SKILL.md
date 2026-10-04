# Luau Skill
- Every Luau module uses `--!strict`.
- Prefer explicit types and typed domain tables; avoid `any`.
- Use guard clauses, local functions, predictable returns, and no implicit globals.
- Use PascalCase for modules/types, camelCase for locals/functions, UPPER_SNAKE_CASE for constants.
- No magic numbers in gameplay logic; use configuration modules.
- Never silently swallow errors; log actionable failures.
