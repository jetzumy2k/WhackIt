# Architecture Skill
- Separate Server, Client, and Shared responsibilities.
- Server Services own authoritative state; Client Controllers own presentation/input.
- Keep modules small and single-purpose.
- Avoid circular dependencies and giant scripts.
- Before coding, identify state owner, mutation authority, client/server boundary, persistence needs, abuse cases, and tests.
- Prefer the smallest clean architecture that satisfies the requirement.
