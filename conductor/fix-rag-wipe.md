# Plan: Clear RagIndexMeta during DB Wipe

## Objective
Ensure the dashboard correctly reports 0 indexed RAG entities after executing the "Wipe DB Lore & RAG" dev/debug operation by clearing the associated metadata tracking table.

## Key Files & Context
- `allknower/src/routes/config.ts`: Defines the `/config/wipe` API route.
- **Context**: The dashboard retrieves its "RAG Indexed" count from `GET /api/rag/status`, which queries the Prisma `RagIndexMeta` table. Currently, the wipe operation drops the LanceDB table but leaves the tracking metadata intact.

## Implementation Steps

1. **Update `/config/wipe` endpoint**:
   - In `allknower/src/routes/config.ts`, locate the `POST /config/wipe` handler.
   - Immediately following the `await prisma.lLMCallLog.deleteMany();` statement, add `await prisma.ragIndexMeta.deleteMany();` to ensure the metadata aligns with the dropped LanceDB table.
   - Update the subsequent `rootLogger.info` message to include `RagIndexMeta` in the list of wiped components.

## Verification & Testing
- Use `run_shell_command` to execute `bun run check` in the `allknower/` directory to verify TypeScript compilation passes.
- Manually trigger the "Wipe DB Lore & RAG" operation via the Settings UI and verify the Dashboard shows 0 indexed entities.
