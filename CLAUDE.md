# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Layout

This is a **git submodule monorepo**. Three independent services live as submodules:

| Directory | Stack | Port | Role |
|---|---|---|---|
| `allcodex-core/` | Express 5, SQLite, pnpm | 8080 | Lore database (Trilium fork) |
| `allknower/` | Elysia, Bun, Prisma/Postgres, LanceDB | 3001 | AI orchestrator |
| `allcodex-portal/` | Next.js 16, React 19, Bun | 3000 | Web frontend (only user-facing surface) |
| `docs/shared/` | Markdown | — | Cross-repo documentation submodule |

Each submodule is a fully independent repo with its own `node_modules`, lockfile, and git history. Changes to submodule content must be committed inside the submodule first, then the parent repo's submodule reference updated.

## Development Commands

### allcodex-core (pnpm)
```bash
cd allcodex-core
pnpm install
pnpm server:start          # dev on :8080
pnpm server:build
pnpm test:all              # parallel + sequential suites
pnpm test:sequential       # server tests only (shared DB — always run sequentially)
pnpm typecheck
pnpm dev:linter-check && pnpm dev:format-check
```

### allknower (bun)
```bash
cd allknower
bun install
bun dev                    # dev on :3001
bun db:generate && bun db:migrate
bun test                   # per-directory isolated groups (see pitfall #11)
bun run check              # tsc --noEmit && bun test (per-directory)
bun typecheck
```

### allcodex-portal (bun)
```bash
cd allcodex-portal
bun install
bun dev                    # dev on :3000
bun build
bun run check              # tsc --noEmit && vitest run (excludes Playwright)
```

No root-level build or test command spans all submodules — run commands from within each submodule directory.

## Architecture

Full details: [docs/shared/reference/architecture.md](docs/shared/reference/architecture.md) and [AGENTS.md](AGENTS.md).

**One-line flow:**
```
User → Portal (:3000) → AllKnower (:3001) → AllCodex Core (:8080, via ETAPI)
                       → AllCodex Core (direct ETAPI for note CRUD)
```

- AllCodex Core never calls AllKnower — communication is one-directional.
- Portal proxies **all** backend calls through Next.js API routes; the browser never holds ETAPI tokens or AllKnower Bearer tokens.
- Credentials live in HTTP-only cookies, resolved by `allcodex-portal/lib/get-creds.ts`.
- AllCodex Core's primary data layer is **Becca** — an in-memory cache of all notes loaded at startup. All reads come from Becca, all writes go to both SQLite and Becca.
- AllKnower uses **LanceDB** (in-process, on-disk) for 4096-dim vector embeddings and **PostgreSQL** (via Prisma) for persistent state.

## Key Cross-Service Files

| What | Where |
|---|---|
| ETAPI client (AllKnower → Core) | `allknower/src/etapi/client.ts` |
| Portal → Core proxy lib | `allcodex-portal/lib/etapi-server.ts` |
| Portal → AllKnower proxy lib | `allcodex-portal/lib/allknower-server.ts` |
| Lore type schemas (21 types) | `allknower/src/types/lore.ts` |
| Brain dump pipeline | `allknower/src/pipeline/brain-dump.ts` |
| Credential resolver | `allcodex-portal/lib/get-creds.ts` |
| HTML sanitizer | `allcodex-portal/lib/sanitize.ts` |
| AllKnower response Zod schemas | `allcodex-portal/lib/allknower-schemas.ts` |

## Coding Conventions (Summary)

### allcodex-core
- TypeScript strict, `module: "nodenext"` — import siblings with `.js` extensions
- 4-space indent, double quotes, semicolons, no trailing commas
- Package/env names still say `@triliumnext/*` / `TRILIUM_*` — intentional legacy naming, do not rename

### allknower
- Bun ESM, `moduleResolution: "bundler"` — imports use `.ts` extensions
- Elysia `t` schemas at HTTP boundaries; Zod for domain/LLM validation
- All LLM/embedding calls go through OpenRouter via `src/pipeline/model-router.ts`
- Routes use a factory/DI pattern: `createXRoute({ dep1, dep2 })` — inject mocks in tests, real impls in production

### allcodex-portal
- Next.js App Router + React Compiler; `@/*` path alias
- TanStack Query for server state; Zustand (`useBrainDumpStore`, `useAIToolsStore`, `useCopilotStore`) for shared UI state
- `lib/` is server-only — never import from client components
- Theme supports light (parchment) and dark (grimoire) via `next-themes` — `ThemeProvider` in `components/providers.tsx`; `.dark` class activates the dark token block in `globals.css`
- All raw HTML rendering in React must be sanitized via `sanitizeLoreHtml()` from `lib/sanitize.ts` (DOMPurify) — player-safe previews use `sanitizePlayerView()`

## Common Pitfalls

1. **Legacy naming**: `@triliumnext/*` package names and `TRILIUM_*` env vars are intentional — don't rename.
2. **Sequential server tests**: allcodex-core server tests share DB state; always use `pnpm test:sequential`, never parallel.
3. **Translation init order**: in allcodex-core, `main.ts` must initialize i18next before any module importing translation strings.
4. **Brain dump overwrites**: AllKnower's brain-dump pipeline replaces note content wholesale — no merge/diff.
5. **Portal E2E requires full stack**: allcodex-portal has vitest unit tests (`lib/*.test.ts`) and a Playwright E2E suite (`tests/*.spec.ts`, 22 specs). `bun run check` excludes Playwright intentionally — E2E needs AllKnower (:3001) and AllCodex Core (:8080) live. Run `bun run test:e2e` from `allcodex-portal/` when the full stack is up; Playwright auto-starts the dev server.
6. **Portal is the only auth UI**: AllKnower serves no login HTML; credentials are always collected by the Portal and proxied server-side.
7. **Submodule commits**: to update a submodule, commit inside the submodule first, then update the parent repo's ref.
8. **AllKnower Prisma tests need live Postgres**: routes that call Prisma inline (e.g. history/:id) cannot be tested with the DI mock — they require a running Postgres instance.
9. **Portal Zod schemas must match AllKnower source**: when writing or updating `allknower-schemas.ts`, cross-reference `allknower/src/pipeline/schemas/response-schemas.ts` — mismatches cause false 502s at runtime.
10. **Elysia listen race**: always `await app.listen(PORT)` before accessing `app.server` — synchronous `app.listen()` leaves `app.server` null when the URL is built.
11. **Bun module cache contamination**: `bun test` in a single invocation shares one module registry across all test files. A `mock.module()` in file A permanently shadows the real module for file B loaded later — even if B has its own `mock.module()`. Always run AllKnower tests as separate per-directory invocations (`bun test test/`, `bun test src/etapi/`, etc.). See `package.json` `test` script for the canonical groups.
12. **Brain dump E2E fixtures need unique runtime IDs**: AllKnower's dedup logic treats content matching existing lore as an update attempt, not a new note. Embed `Date.now()` in both the entity name and body so each test run produces a genuinely novel entity.
13. **`autoRelate` latency scales with entity count**: `suggestRelationsForNote` runs once per created note (~30-40s each). A 3-entity fixture triggers 3 sequential LLM calls; keep integration test brain-dump fixtures to 1 entity to stay under timeout ceilings.
14. **AllKnower `.env.test` requires server restart**: env vars load once at startup — `/health` returning 200 does not mean the new env is active. After editing `.env.test`, kill the watcher and restart with `bun --env-file=.env.test dev`.
15. **LLM JSON schema `required` array prevents silent no-ops**: fallback models (e.g. `x-ai/grok-4.1-fast`) silently omit fields absent from `required` even if present in `properties`. Always include all expected output fields in `required`.
