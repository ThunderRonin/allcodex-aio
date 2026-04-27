# AllCodex Ecosystem

Three-service worldbuilding platform. The user interacts only with the Portal; the Portal calls AllKnower (AI) and AllCodex (data) server-side.

```
User → Portal (Next.js :3000) → AllKnower (Elysia/Bun :3001) → AllCodex (Express :8080)
                               → AllCodex (direct CRUD via ETAPI)
```

## Projects

| Directory | Stack | Runtime | Role |
|---|---|---|---|
| `allcodex-core/` | Express 5, SQLite, pnpm monorepo | Node.js | Lore database (fork of TriliumNext/Trilium) |
| `allknower/` | Elysia, Prisma (Postgres), LanceDB | Bun | AI orchestrator — brain dump, RAG, consistency, relationships, gaps |
| `allcodex-portal/` | Next.js 16, React 19, TanStack Query, shadcn/ui | Bun | Web frontend — the only user-facing surface |

## Quick Reference

### allcodex-core (pnpm)
```bash
pnpm install
pnpm server:start              # dev on :8080
pnpm server:build
pnpm test:all                  # parallel + sequential
pnpm typecheck
pnpm dev:linter-check && pnpm dev:format-check
```

### allknower (bun)
```bash
bun install
bun dev                        # dev on :3001
bun db:generate && bun db:migrate
bun test
bun typecheck
```

### allcodex-portal (bun)
```bash
bun install
bun dev                        # dev on :3000
bun build
```

## Architecture at a Glance

See [docs/shared/reference/architecture.md](docs/shared/reference/architecture.md) for full details. Key concepts:

- **Everything is a note** in AllCodex. Notes have types, content, attributes (labels/relations), and live in a multi-parent tree via branches.
- **Becca** = backend entity cache (all notes in memory). **Shaca** = read-only share cache.
- **ETAPI** (`/etapi/`) is the REST API for note CRUD/search. Token-based auth. OpenAPI spec at `/etapi/openapi.json`, interactive docs at `/docs`.
- AllKnower communicates with AllCodex **only via ETAPI** — no shared imports.
- Portal proxies all backend calls through **Next.js API routes** — browser never holds backend secrets.
- Credentials flow through HTTP-only cookies, resolved by `lib/get-creds.ts`.

## Coding Conventions

### allcodex-core
- TypeScript strict mode, `module: "nodenext"`, `target: "es2022"`
- Import sibling modules with `.js` extensions (NodeNext resolution)
- ESLint flat config + separate formatting config (`eslint.format.config.mjs`)
- 4-space indent, double quotes, semicolons, no trailing commas
- Vitest for tests (`.spec.ts` files), Playwright for E2E
- Server tests run **sequentially** (shared DB state) — use `pnpm test:sequential`
- Service-oriented architecture under `apps/server/src/services/`
- **Do not** import i18next-dependent modules at top level in `main.ts` (translation must init first)
- Package names still use `@triliumnext/*` and env vars use `TRILIUM_*` — this is intentional legacy naming

### allknower
- Bun runtime, ESM everywhere (`"type": "module"`)
- TypeScript strict, `moduleResolution: "bundler"`, imports use `.ts` extensions
- Elysia `t` schemas at HTTP boundaries, Zod for domain/LLM validation
- Prisma for Postgres, LanceDB for vectors — keep them separate
- OpenRouter for all LLM/embedding calls via model-router
- Pipeline modules (`src/pipeline/`) are the core business logic
- Lore types defined in `src/types/lore.ts` — single source of truth for entity schemas
- `bun:test` with `mock.module()` pattern for test isolation
- No lint toolchain yet — follow allcodex-core style conventions

### allcodex-portal
- Next.js App Router with React 19 and React Compiler enabled
- TanStack Query for server state (`useQuery` / `useMutation` + invalidation)
- Component state with `useState` — **Zustand** for dedicated stores (`useBrainDumpStore`, `useAIToolsStore`)
- Tailwind CSS 4 with shadcn/ui (new-york style, neutral base, CSS variables)
- `components/ui/` = generic shadcn primitives, `components/portal/` = app-specific
- `lib/` = server-only integration code (never import in client components)
- API routes are thin proxies — no domain logic in the portal
- Dark "grimoire" theme is hardcoded (Cinzel headings, Crimson Text body)
- **Resolved**: `dangerouslySetInnerHTML` is now wrapped with `sanitizeLoreHtml()` (DOMPurify) in the lore detail view via `lib/sanitize.ts`. Player-safe preview uses `sanitizePlayerView()`.
- `@/*` path alias for imports

## Key Files

| What | Where |
|---|---|
| AllCodex entry point | `allcodex-core/apps/server/src/main.ts` |
| Express app setup | `allcodex-core/apps/server/src/app.ts` |
| Entity cache | `allcodex-core/apps/server/src/becca/becca.ts` |
| ETAPI routes | `allcodex-core/apps/server/src/etapi/` |
| Share rendering | `allcodex-core/apps/server/src/share/content_renderer.ts` |
| Lore templates | `allcodex-core/apps/server/src/services/hidden_subtree_templates.ts` |
| DB schema | `allcodex-core/apps/server/src/assets/db/schema.sql` |
| AllKnower app | `allknower/src/app.ts` |
| Brain dump pipeline | `allknower/src/pipeline/brain-dump.ts` |
| RAG embedder | `allknower/src/rag/embedder.ts` |
| ETAPI client | `allknower/src/etapi/client.ts` |
| Lore type schemas | `allknower/src/types/lore.ts` (21 entity types) |
| System pack import | `allknower/src/routes/import.ts` |
| Prisma schema | `allknower/prisma/schema.prisma` |
| Portal layout | `allcodex-portal/app/(portal)/layout.tsx` |
| Backend proxy lib | `allcodex-portal/lib/etapi-server.ts`, `lib/allknower-server.ts` |
| Credential resolver | `allcodex-portal/lib/get-creds.ts` |
| HTML sanitizer | `allcodex-portal/lib/sanitize.ts` |
| Zustand stores | `allcodex-portal/lib/stores/brain-dump-store.ts`, `lib/stores/ai-tools-store.ts` |
| Share settings component | `allcodex-portal/components/portal/ShareSettings.tsx` |
| Statblock card component | `allcodex-portal/components/portal/StatblockCard.tsx` |
| Canonical lore schema | `docs/shared/reference/canonical-lore-schema.md` |

## Existing Documentation

- [docs/shared/README.md](docs/shared/README.md) — **documentation index** (start here)
- [docs/shared/reference/architecture.md](docs/shared/reference/architecture.md) — ecosystem architecture (submodule across repos)
- [docs/shared/planning/ROADMAP.md](docs/shared/planning/ROADMAP.md) — canonical DM-first roadmap (Phases 0–4 shipped, Phase 5 partial)
- [docs/shared/planning/implementation_plan_phases_0_3.md](docs/shared/planning/implementation_plan_phases_0_3.md) — detailed implementation plan (all phases A–G complete)
- [docs/shared/reference/canonical-lore-schema.md](docs/shared/reference/canonical-lore-schema.md) — 21 lore entity types (single source of truth)
- [docs/shared/analysis/gap_analysis_vs_worldanvil.md](docs/shared/analysis/gap_analysis_vs_worldanvil.md) — feature gap analysis vs World Anvil
- [docs/shared/analysis/worldanvil_feature_matrix.md](docs/shared/analysis/worldanvil_feature_matrix.md) — implementation-verified feature matrix
- [docs/shared/reference/portal-api-reference.md](docs/shared/reference/portal-api-reference.md) — complete Portal API route and method reference
- [allcodex-core/CLAUDE.md](allcodex-core/CLAUDE.md) — detailed AllCodex agent guide
- [allcodex-core/docs/Developer Guide/](allcodex-core/docs/Developer%20Guide/) — upstream Trilium dev guide (partially stale for this fork)
- [allknower/docs/ai_architecture_investigation.md](allknower/docs/ai_architecture_investigation.md) — AI/RAG improvement backlog
- [allcodex-portal/ROADMAP.md](allcodex-portal/ROADMAP.md) — portal feature backlog

## Common Pitfalls

1. **Legacy naming**: code/configs still say Trilium/TriliumNext in many places. Don't rename unless specifically asked.
2. **Server tests are sequential**: they share DB state. Use `pnpm test:sequential`, not parallel.
3. **Translation init order**: in allcodex-core, `main.ts` must initialize i18next before any module that imports translation strings.
4. **ESLint ignores `packages/*`**: root lint config doesn't cover all package folders.
5. **Brain dump overwrites**: AllKnower's brain-dump pipeline replaces note content wholesale — no merge/diff.
6. **Docs drift**: some README endpoints, shared docs model references, and test expectations are stale vs. current code.
7. **Portal tests are split**: `allcodex-portal` has Vitest unit tests and Playwright E2E specs. `bun run check` runs typecheck + unit tests and intentionally excludes Playwright, which needs the full stack running.
8. **HTML in portal**: lore detail view HTML is sanitized via `sanitizeLoreHtml()` (DOMPurify). Player-safe previews use `sanitizePlayerView()`. Keep this pattern when adding new HTML rendering paths.
