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

Each submodule has its own `CLAUDE.md` with stack-specific conventions and pitfalls. This file covers cross-service concerns only.

## Development Commands

No root-level build or test command spans all submodules — run commands from within each submodule directory. See each submodule's `CLAUDE.md` for specific commands.

Quick reference:

| Service | Install | Dev | Test | Typecheck |
|---|---|---|---|---|
| Core | `pnpm install` | `pnpm server:start` | `pnpm test:all` | `pnpm typecheck` |
| AllKnower | `bun install` | `bun dev` | `bun run check` | `bun typecheck` |
| Portal | `bun install` | `bun dev` | `bun run check` | `bun typecheck` |

## Architecture

Full details: [docs/shared/reference/architecture.md](docs/shared/reference/architecture.md) and [AGENTS.md](AGENTS.md).

**One-line flow:**
```text
User → Portal (:3000) → AllKnower (:3001) → AllCodex Core (:8080, via ETAPI)
                       → AllCodex Core (direct ETAPI for note CRUD)
```

- AllCodex Core never calls AllKnower — communication is one-directional.
- Portal proxies **all** backend calls through Next.js API routes; the browser never holds ETAPI tokens or AllKnower Bearer tokens.
- Core credentials are persisted in per-user backend storage within AllKnower, securely resolved during backend calls.
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

## Cross-Service Rules

1. **Do not import source code across services.** Cross-service contracts go through ETAPI, HTTP schemas, and explicit client libraries.
2. **Submodule commits**: commit inside the submodule first, then update the parent repo's submodule reference.
3. **Portal Zod schemas must match AllKnower source**: when writing or updating `allknower-schemas.ts`, cross-reference `allknower/src/pipeline/schemas/response-schemas.ts` — mismatches cause false 502s at runtime.
4. **Portal is the only auth UI**: AllKnower serves no login HTML; credentials are always collected by the Portal and proxied server-side.
5. **Brain dump overwrites**: AllKnower's brain-dump pipeline replaces note content wholesale — no merge/diff.
6. **Content sanitization is Portal's job, not Core's**: Core stores note content verbatim (including `<script>`, event handlers, etc.). Core only sanitizes **titles** at write time. Portal must run `sanitizeLoreHtml()` or `sanitizePlayerView()` before rendering any note content to browsers. Never assume content from ETAPI is safe for direct HTML insertion.
7. **ETAPI body parser only accepts `text/plain`**: Core's Express `text()` middleware only parses `Content-Type: text/plain`. Sending `text/html` to PUT `/etapi/notes/:id/content` results in null body. Portal's internal API routes use a different path — only ETAPI has this constraint.
