# Architectural Decisions

Short entries — what was chosen, why, and what the trade-off was.
Add an entry any time a non-obvious architecture choice is made.

---

## LanceDB over pgvector for vector storage
Chose LanceDB (embedded, on-disk) over pgvector (Postgres extension).
**Why:** No separate service to run or manage. pgvector requires a Postgres extension and a separate embeddings table alongside the main schema. LanceDB runs in-process in AllKnower with zero infra overhead.
**Trade-off:** LanceDB is less battle-tested at scale and lacks Postgres-native SQL joins.

## AllKnower ↔ AllCodex only via ETAPI
AllKnower never imports from AllCodex Core source. All reads and writes go through ETAPI HTTP calls.
**Why:** The two services run different runtimes (Bun vs Node.js). Shared imports would couple their release cycles and force one build system. ETAPI is already the stable public contract.
**Trade-off:** Every AllKnower → AllCodex write is an HTTP round-trip. No transactions across services.

## Portal proxies all backend calls
The browser never holds ETAPI tokens or AllKnower Bearer tokens. All credential-bearing requests happen in Next.js API routes (server-side).
**Why:** HTTP-only cookies can't be read by JavaScript. Putting tokens in the browser (localStorage, memory) exposes them to XSS.
**Trade-off:** An extra network hop through Next.js for every operation.

## HTTP-only cookies for credential storage
Portal stores AllCodex and AllKnower credentials in HTTP-only cookies, not localStorage or in-memory stores.
**Why:** HTTP-only cookies are invisible to JavaScript — XSS can't steal them. Tokens survive hard-refreshes and browser restarts without re-login.
**Trade-off:** Requires server-side cookie access on every API route call. Clearing cookies on logout must be intentional.

## Becca in-memory entity cache in AllCodex Core
All notes, branches, and attributes are loaded into memory at startup (Becca). Reads never hit SQLite directly.
**Why:** Note tree traversals and attribute lookups on a large lore database are expensive if done via SQL on every request. In-memory lookups are microseconds.
**Trade-off:** Large databases increase AllCodex memory footprint. Cold start takes longer.

## OpenRouter for all LLM and embedding calls
AllKnower uses a single OpenRouter API key for all models (Grok, Kimi, Aion, Qwen, etc.) rather than multiple provider SDKs.
**Why:** One API key, one billing account. OpenRouter handles provider failover server-side — a single HTTP call with `fallbacks[]` tries multiple models automatically.
**Trade-off:** Adds a proxy hop to every LLM call. Provider-specific features (fine-tuning, batch) aren't accessible.

## Trilium fork as the lore database
AllCodex Core is a fork of TriliumNext/Trilium rather than a bespoke database.
**Why:** Trilium already solved note tree storage, multi-parent branches, attribute labels/relations, ETAPI, full-text search, share rendering, and per-note encryption. Starting from scratch would have taken months.
**Trade-off:** The codebase carries Trilium legacy naming (TRILIUM_*, @triliumnext/*) and architectural decisions made for a desktop app, not a lore server.

## Brain dump overwrites note content wholesale
When AllKnower updates an existing note, it replaces the content entirely. There is no merge or diff.
**Why:** The LLM generates a complete, coherent lore entry each time. Merging LLM output with existing structured HTML reliably is unsolved. Overwrite is simple and predictable.
**Trade-off:** Any user edits made after the last brain dump are lost on the next update for that note. Review mode (returns proposals before writing) mitigates this for intentional updates.

## better-auth headless in AllKnower
AllKnower serves no login HTML. better-auth is configured in headless mode — the Portal owns all credential UI.
**Why:** Separates concerns cleanly. AllKnower is a pure API server. The Portal is the UI surface. Login flows, error messages, and form validation all live in one place.
**Trade-off:** AllKnower's auth endpoints are not browsable without the Portal running.

## AllKnower tests run in per-directory bun invocations
`bun test` in a single invocation shares a global module registry. `mock.module()` calls in one test file permanently shadow the real module for all files loaded later in the same process, causing false failures in unrelated tests.
**Why:** Bun's test runner processes all files in one V8 context by default. A route test that mocks `etapi/client.ts` leaves that mock active when the next alphabetical file imports the same module — even if the second file has its own `mock.module()` call, ESM static imports are hoisted above `mock.module()` and resolve from the already-contaminated registry.
**Trade-off:** Each `bun test <dir>` call spawns a fresh process, so total wall-clock time is slightly higher. Suite isolation is worth it — combining directories causes intermittent, order-dependent failures that are hard to diagnose.

## Next.js App Router with React Compiler
The Portal uses the Next.js App Router (not Pages Router) with React 19 and the experimental React Compiler enabled.
**Why:** App Router enables React Server Components for data-fetching layouts. React Compiler automates memoization — no manual `useMemo`/`useCallback` discipline required.
**Trade-off:** App Router patterns (server/client component boundary, `use client` directives) are stricter and less documented than Pages Router. Some libraries haven't fully adapted.
