# Data Persistence Skill
Use a dedicated PlayerDataService.
Data must be versioned, validated, defaulted, migrated, safely updated, and resilient to transient failures.
Never persist arbitrary client data.
If loading cannot be trusted, fail safely instead of overwriting valid player data with defaults.
Purchase/reward grants must be idempotent.
