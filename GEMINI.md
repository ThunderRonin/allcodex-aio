# AllCodex Ecosystem Instructions

Canonical instructions live in **[AGENTS.md](./AGENTS.md)** at the workspace root. That file is the single source of truth for project context, commands, conventions, key files, and pitfalls.

## Service-Specific Context
For deep dives into individual services, refer to:
- **Core**: [allcodex-core/CLAUDE.md](./allcodex-core/README.md)
- **AllKnower**: [allknower/README.md](./allknower/README.md)
- **Portal**: [allcodex-portal/README.md](./allcodex-portal/README.md)

## Quick Reference Commands
| Service | Tool | Command |
|---|---|---|
| **Core** | pnpm | `pnpm server:start`, `pnpm test:sequential` |
| **AllKnower** | Bun | `bun dev`, `bun run check` |
| **Portal** | Bun | `bun dev`, `bun run check` |

*Note: Always run commands inside the relevant submodule directory.*
