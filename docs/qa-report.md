# QA Report

Date: 2026-04-03

## Validated

- AllKnower route-level Bun tests are green: 23 passing tests and 1 intentional `todo` covering the missing deterministic better-auth bootstrap.
- Portal Playwright coverage is green: 8 passing tests across smoke, brain dump, lore CRUD, AI tools, and XSS rendering paths.
- The portal editor mention flow now uses a local cursor-query detector in `LoreEditor` and still resolves suggestions through `/api/lore/mention-search`.
- The focused AllCodex core Playwright slice is green: `allcodex-core/apps/server-e2e/src/llm_chat.spec.ts` passed 4/4 against the live `:8082` integration-memory server.
- The core spec now validates executable ETAPI-backed behaviors in this workspace: lore attribute creation, relation persistence, note content storage for code/mermaid/rich-text notes, and hostile title sanitization on note creation.

## Notes

- The old AllCodex browser-shell assumptions remain stale in this workspace because the legacy frontend assets are not present under the server build output. The green core slice was therefore rewritten to target live ETAPI server behavior instead of the missing UI shell.

## Files Touched

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