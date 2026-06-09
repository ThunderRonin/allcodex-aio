# QA Report

Date: 2026-05-25

## Validated — Hybrid Search + Streaming Entity Rendering

- AllKnower full check is green: `bun run check`.
- Portal check is green: `bun run check` with 48 test files and 293 tests passing.
- Direct real AllKnower brain-dump SSE probe is green: stream exits `0`, emits `event: done`, and emits keepalive comments during long quiet phases.
- Portal real LLM integration is green: `npx playwright test --project=integration`.
- Portal real brain-dump integration was rerun separately after the full integration pass: `npx playwright test --project=integration tests/integration/brain-dump-live.spec.ts` exited `0`.

## Failures Found + Fixed

- AllKnower `test/e2e/rag.e2e.test.ts` initially failed because the e2e mock env omitted the new RAG env fields. Missing `RAG_HYBRID_RRF_K` produced `NaN` scores that serialized to `null`; missing rerank settings produced invalid rerank payloads. Fixed by adding all seven RAG env fields to `test/helpers/e2e-mock-setup.ts` and disabling rerank there.
- Real brain-dump live integration initially failed because the browser never received the final SSE `done` event. AllKnower had long quiet gaps during RAG/LLM/write, and the stream closed before completion reached the client. Fixed by adding AllKnower SSE keepalive comments and by flushing the Portal client parser's final buffer on stream close.

## Files Touched — Current Work

- `allknower/src/env.ts`
- `allknower/.env.test`
- `allknower/src/rag/rrf.ts`
- `allknower/src/rag/rrf.test.ts`
- `allknower/src/rag/lancedb.ts`
- `allknower/src/routes/brain-dump.ts`
- `allknower/test/helpers/e2e-mock-setup.ts`
- `allknower/package.json`
- `allcodex-portal/lib/parse-streaming-entities.ts`
- `allcodex-portal/lib/parse-streaming-entities.test.ts`
- `allcodex-portal/lib/sanitize.ts`
- `allcodex-portal/lib/stores/brain-dump-store.ts`
- `allcodex-portal/app/(portal)/brain-dump/page.tsx`

## Historical Validated

- AllKnower route-level Bun tests are green: 23 passing tests and 1 intentional `todo` covering the missing deterministic better-auth bootstrap.
- Portal Playwright coverage is green: 8 passing tests across smoke, brain dump, lore CRUD, AI tools, and XSS rendering paths.
- The portal editor mention flow now uses a local cursor-query detector in `LoreEditor` and still resolves suggestions through `/api/lore/mention-search`.
- The focused AllCodex core Playwright slice is green: `allcodex-core/apps/server-e2e/src/llm_chat.spec.ts` passed 4/4 against the live `:8082` integration-memory server.
- The core spec now validates executable ETAPI-backed behaviors in this workspace: lore attribute creation, relation persistence, note content storage for code/mermaid/rich-text notes, and hostile title sanitization on note creation.

## Historical Notes

- The old AllCodex browser-shell assumptions remain stale in this workspace because the legacy frontend assets are not present under the server build output. The green core slice was therefore rewritten to target live ETAPI server behavior instead of the missing UI shell.

## Historical Files Touched

- `allcodex-core/apps/server-e2e/src/llm_chat.spec.ts`
- `allcodex-core/apps/server/src/services/notes.ts`
- `allcodex-core/apps/server/src/share/shaca/shaca_loader.ts`
- `allknower/test/helpers/auth.ts`
- `allknower/test/helpers/http.ts`
- `allknower/test/auth.integration.test.ts`
- `allknower/test/health.test.ts`
- `allknower/test/rag.test.ts`
- `allknower/test/suggest.test.ts`
- `allknower/test/brain-dump.test.ts`
- `allknower/test/consistency.test.ts`
- `allcodex-portal/playwright.config.ts`
- `allcodex-portal/tests/helpers/mock-api.ts`
- `allcodex-portal/tests/helpers/test-utils.ts`
- `allcodex-portal/tests/smoke.spec.ts`
- `allcodex-portal/tests/brain-dump.spec.ts`
- `allcodex-portal/tests/lore-crud.spec.ts`
- `allcodex-portal/tests/xss-portal.spec.ts`
- `allcodex-portal/tests/ai-tools.spec.ts`
- `allcodex-portal/components/editor/LoreEditor.tsx`
- `allcodex-portal/app/(portal)/lore/new/page.tsx`
- `allcodex-portal/app/api/lore/mention-search/route.ts`
