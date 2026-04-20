---
name: check-all
description: Use when verifying the full monorepo typechecks and unit tests pass before committing or merging to dev or main. Runs all three services sequentially from the parent repo root.
---

# Check All

Runs typecheck + tests across all three services. Run from `/Users/allmaker/projects/allcodex-aio`.

## Quick One-Liner

```bash
(cd allcodex-portal && bun run check) && (cd allknower && bun run check) && (cd allcodex-core && pnpm typecheck)
```

Stop on first failure — fix before continuing.

## Per-Service Breakdown

| Service | Command | Covers |
|---------|---------|--------|
| `allcodex-portal` | `bun run check` | `tsc --noEmit` + vitest unit tests |
| `allknower` | `bun run check` | `tsc --noEmit` + `bun test` (per-directory isolated groups) |
| `allcodex-core` | `pnpm typecheck` | `tsc --noEmit` only |

## What This Does NOT Cover

- **allcodex-core server tests**: run `pnpm test:sequential` separately (shared DB — never parallel)
- **allcodex-portal E2E**: run `bun run test:e2e` separately — needs full stack (AllKnower :3001, Core :8080) live
- **allknower Prisma route tests**: require live Postgres; skipped unless DB is running
