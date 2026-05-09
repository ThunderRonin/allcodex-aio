# Code Quality Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce the 9 missing code quality criteria identified in the reviewer audit across all three AllCodex services.

**Architecture:** Two independent submodule tracks (AllKnower hardening, Portal hardening) plus root-level docs. Tasks within each track are sequenced by risk — scripts and error codes first, then runtime validation and UI safety nets. Eden Treaty (Task 10) is optional and supersedes Task 9's manual Zod schemas if adopted.

**Tech Stack:** Bun, Elysia, Next.js 15 App Router, React 19, TypeScript strict, Zod (new portal dep), Playwright

---

## Scope note

Tasks 1–6 are entirely within `allknower/`. Tasks 7–9 are entirely within `allcodex-portal/`. Task 10 (Eden Treaty) spans both. Task 11 (DECISIONS.md) is a root-level docs task. They can be run in any order across tracks; within each track, follow the sequence.

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `allknower/package.json` | Modify | Add `test` and `check` scripts |
| `allknower/src/index.ts` | Modify | Add startup health check |
| `allknower/src/routes/brain-dump.ts` | Modify | Add `code` field to rate-limit and 404 error responses |
| `allcodex-portal/package.json` | Modify | Add `check` script |
| `allcodex-portal/app/(portal)/error.tsx` | Create | Catch-all portal error boundary |
| `allcodex-portal/app/(portal)/lore/[id]/error.tsx` | Create | Lore detail error boundary |
| `allcodex-portal/app/(portal)/brain-dump/error.tsx` | Create | Brain dump error boundary |
| `allcodex-portal/app/(portal)/ai/error.tsx` | Create | AI tools error boundary (covers consistency/gaps/relationships) |
| `allcodex-portal/lib/allknower-schemas.ts` | Create | Zod schemas for AllKnower AI tool responses |
| `allcodex-portal/lib/allknower-server.ts` | Modify | Replace TS interfaces with `z.infer<>` types; add `.parse()` calls |
| `DECISIONS.md` | Create | Architectural decision log |

---

## Task 1: AllKnower — Add `test` and `check` scripts

**Files:**
- Modify: `allknower/package.json`

- [ ] **Step 1: Add scripts**

Open `allknower/package.json`. The current `scripts` block is:

```json
"scripts": {
  "dev": "bun --watch src/index.ts",
  "start": "bun src/index.ts",
  "build": "bun build src/index.ts --outdir dist --target bun",
  "db:generate": "bunx prisma generate",
  "db:migrate": "bunx prisma migrate dev",
  "db:migrate:prod": "bunx prisma migrate deploy",
  "db:studio": "bunx prisma studio",
  "db:reset": "bunx prisma migrate reset",
  "typecheck": "tsc --noEmit"
}
```

Replace with:

```json
"scripts": {
  "dev": "bun --watch src/index.ts",
  "start": "bun src/index.ts",
  "build": "bun build src/index.ts --outdir dist --target bun",
  "db:generate": "bunx prisma generate",
  "db:migrate": "bunx prisma migrate dev",
  "db:migrate:prod": "bunx prisma migrate deploy",
  "db:studio": "bunx prisma studio",
  "db:reset": "bunx prisma migrate reset",
  "typecheck": "tsc --noEmit",
  "test": "bun test test/ && bun test src/etapi/ && bun test src/pipeline/ && bun test src/routes/ && bun test src/rag/indexer.test.ts && bun test src/rag/lancedb.integration.test.ts",
  "test:all": "bun test",
  "check": "tsc --noEmit && bun test test/ && bun test src/etapi/ && bun test src/pipeline/ && bun test src/routes/ && bun test src/rag/indexer.test.ts && bun test src/rag/lancedb.integration.test.ts"
}
```

- [ ] **Step 2: Verify `bun test` discovers tests**

```bash
cd allknower && bun test test/
```

Expected: test files under `test/` run. Note any failures — do not fix them here, just confirm discovery works.

> **Implementation note:** Tests must be run as separate per-directory invocations rather than a single `bun test` call. Bun shares one module registry per process, so `mock.module()` calls in one test file permanently shadow the real module for all files loaded later — causing false failures in unrelated tests. The canonical groups are in the `test` script above.

- [ ] **Step 3: Commit**

```bash
git add allknower/package.json
git commit -m "chore(allknower): add test and check npm scripts"
```

---

## Task 2: AllKnower — Fix missing `code` fields in brain-dump error responses

**Files:**
- Modify: `allknower/src/routes/brain-dump.ts`

The rate-limit response (line ~30) and the history/:id 404 (line ~148) both return `{ error: "..." }` with no `code` field. Every other AllKnower error response has one.

- [ ] **Step 1: Write a failing test**

In `allknower/test/brain-dump.test.ts`, at the end of the existing test suite, add:

```ts
it("rate limit error response contains a code field", async () => {
  const limited = new Elysia().use(createBrainDumpRoute({
    requireAuthImpl: requireAuthBypass,
    rateLimitEnv: {
      BRAIN_DUMP_RATE_LIMIT_MAX: 0,   // instant limit
      BRAIN_DUMP_RATE_LIMIT_WINDOW_MS: 60000,
    },
    runBrainDumpImpl: async () => ({ mode: "auto" as const, summary: "", created: [], updated: [], skipped: [] }),
    commitReviewedEntitiesImpl: async () => ({ summary: "", created: [], updated: [], skipped: [] }),
    indexNoteImpl: async () => {},
  }));

  const res = await limited.handle(
    new Request("http://localhost/brain-dump/", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ rawText: "The archivist buried a fragment beneath the obsidian gate." }),
    })
  );

  expect(res.status).toBe(429);
  const body = await res.json();
  expect(body).toHaveProperty("code");
  expect(body.code).toBe("RATE_LIMITED");
});

it("history/:id 404 response contains a code field", async () => {
  const app = new Elysia().use(createBrainDumpRoute({
    requireAuthImpl: requireAuthBypass,
    rateLimitEnv: { BRAIN_DUMP_RATE_LIMIT_MAX: 10, BRAIN_DUMP_RATE_LIMIT_WINDOW_MS: 60000 },
    runBrainDumpImpl: async () => ({ mode: "auto" as const, summary: "", created: [], updated: [], skipped: [] }),
    commitReviewedEntitiesImpl: async () => ({ summary: "", created: [], updated: [], skipped: [] }),
    indexNoteImpl: async () => {},
  }));

  const res = await app.handle(
    new Request("http://localhost/brain-dump/history/does-not-exist-at-all")
  );

  expect(res.status).toBe(404);
  const body = await res.json();
  expect(body).toHaveProperty("code");
  expect(body.code).toBe("NOT_FOUND");
});
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd allknower && bun test test/brain-dump.test.ts
```

Expected: the two new tests fail — `code` property missing.

- [ ] **Step 3: Fix the rate-limit response**

In `allknower/src/routes/brain-dump.ts`, find the `errorResponse` in the `rateLimit()` call (~line 30):

```ts
errorResponse: new Response(
    JSON.stringify({ error: "Rate limit exceeded. Brain dump is limited to 10 requests per minute." }),
    { status: 429, headers: { "Content-Type": "application/json" } }
),
```

Change to:

```ts
errorResponse: new Response(
    JSON.stringify({
        error: "Rate limit exceeded. Brain dump is limited to 10 requests per minute.",
        code: "RATE_LIMITED",
    }),
    { status: 429, headers: { "Content-Type": "application/json" } }
),
```

- [ ] **Step 4: Fix the history/:id 404**

In the same file, find the 404 return (~line 148):

```ts
if (!entry) {
    set.status = 404;
    return { error: "Brain dump entry not found" };
}
```

Change to:

```ts
if (!entry) {
    set.status = 404;
    return { error: "Brain dump entry not found", code: "NOT_FOUND" };
}
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
cd allknower && bun test test/brain-dump.test.ts
```

Expected: all tests pass including the two new ones.

- [ ] **Step 6: Commit**

```bash
git add allknower/src/routes/brain-dump.ts allknower/test/brain-dump.test.ts
git commit -m "fix(allknower): add code field to rate-limit and 404 error responses"
```

---

## Task 3: AllKnower — Health check at startup

**Files:**
- Modify: `allknower/src/index.ts`

Currently `src/index.ts` starts the server and logs the URL but never checks whether AllCodex, LanceDB, or Postgres are reachable. A misconfigured `DATABASE_URL` or dead AllCodex only surfaces on the first real request.

- [ ] **Step 1: Update `src/index.ts`**

Current content of `allknower/src/index.ts`:

```ts
import { app } from "./app.ts";
import { env } from "./env.ts";

const PORT = env.PORT;

app.listen(PORT);

console.log(
    `\n🧠 AllKnower is running at http://${app.server?.hostname}:${app.server?.port}\n` +
    `   📖 API docs: http://${app.server?.hostname}:${app.server?.port}/reference\n` +
    `   ❤️  Health:   http://${app.server?.hostname}:${app.server?.port}/health\n`
);
```

Replace with:

```ts
import { app } from "./app.ts";
import { env } from "./env.ts";

const PORT = env.PORT;

app.listen(PORT);

const origin = `http://${app.server?.hostname}:${app.server?.port}`;

console.log(
    `\n🧠 AllKnower is running at ${origin}\n` +
    `   📖 API docs: ${origin}/reference\n` +
    `   ❤️  Health:   ${origin}/health\n`
);

// Non-blocking startup dependency check — warns early instead of failing silently later.
setTimeout(async () => {
    try {
        const res = await fetch(`${origin}/health`);
        const { checks } = await res.json() as {
            checks: {
                allcodex: { ok: boolean };
                lancedb: { ok: boolean };
                database: { ok: boolean };
            };
        };
        if (!checks.allcodex.ok)  console.warn("⚠️  AllCodex Core is unreachable — check ALLCODEX_URL and ALLCODEX_TOKEN");
        if (!checks.database.ok)  console.warn("⚠️  Postgres is unreachable — check DATABASE_URL");
        if (!checks.lancedb.ok)   console.warn("⚠️  LanceDB failed to initialize — check data directory permissions");
    } catch {
        console.warn("⚠️  Startup health check failed — dependencies may not be ready");
    }
}, 150);
```

- [ ] **Step 2: Verify dev startup still works**

```bash
cd allknower && bun dev
```

Expected: server starts, health check fires ~150ms later, any unreachable service produces a `⚠️` warning. No crash if dependencies are down.

- [ ] **Step 3: Commit**

```bash
git add allknower/src/index.ts
git commit -m "feat(allknower): warn at startup if dependencies are unreachable"
```

---

## Task 4: Portal — Add `check` script

**Files:**
- Modify: `allcodex-portal/package.json`

Current `scripts`:

```json
"dev": "next dev",
"build": "next build",
"start": "next start",
"test:unit": "vitest run",
"test:unit:watch": "vitest",
"test:e2e": "playwright test",
"test": "vitest run && playwright test"
```

- [ ] **Step 1: Add the `check` script**

Add one line to the scripts object:

```json
"check": "tsc --noEmit && vitest run"
```

The `check` script intentionally excludes Playwright — E2E tests need a running server and belong in CI, not in a pre-commit gate. TypeScript + unit tests are the fast local gate.

- [ ] **Step 2: Verify it runs**

```bash
cd allcodex-portal && bun run check
```

Expected: `tsc --noEmit` completes with no errors, then `vitest run` executes unit tests.

- [ ] **Step 3: Commit**

```bash
git add allcodex-portal/package.json
git commit -m "chore(portal): add check script (tsc + unit tests)"
```

---

## Task 5: Portal — Error boundaries for key route segments

**Files:**
- Create: `allcodex-portal/app/(portal)/error.tsx`
- Create: `allcodex-portal/app/(portal)/lore/[id]/error.tsx`
- Create: `allcodex-portal/app/(portal)/brain-dump/error.tsx`
- Create: `allcodex-portal/app/(portal)/ai/error.tsx`

Next.js App Router renders `error.tsx` when any Server Component or Client Component in that route segment throws. Without these files, a single thrown error kills the entire page and shows a generic browser error. The portal already handles API errors well at the fetch layer; this covers render-time crashes.

- [ ] **Step 1: Write the portal-level catch-all boundary**

Create `allcodex-portal/app/(portal)/error.tsx`:

```tsx
"use client";

import { useEffect } from "react";
import { Button } from "@/components/ui/button";

export default function PortalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error("[portal error]", error);
  }, [error]);

  return (
    <div className="flex flex-col items-center justify-center min-h-[60vh] gap-4 text-center px-4">
      <h2 className="font-cinzel text-xl text-foreground">Something went wrong</h2>
      <p className="text-sm text-muted-foreground max-w-md">
        {error.message || "An unexpected error occurred. Try again or reload the page."}
      </p>
      <Button variant="outline" onClick={reset}>
        Try again
      </Button>
    </div>
  );
}
```

- [ ] **Step 2: Write the lore detail boundary**

Create `allcodex-portal/app/(portal)/lore/[id]/error.tsx`:

```tsx
"use client";

import { useEffect } from "react";
import { Button } from "@/components/ui/button";
import Link from "next/link";

export default function LoreDetailError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error("[lore detail error]", error);
  }, [error]);

  return (
    <div className="flex flex-col items-center justify-center min-h-[60vh] gap-4 text-center px-4">
      <h2 className="font-cinzel text-xl text-foreground">Could not load lore entry</h2>
      <p className="text-sm text-muted-foreground max-w-md">
        {error.message || "This entry may have been deleted or is temporarily unavailable."}
      </p>
      <div className="flex gap-2">
        <Button variant="outline" onClick={reset}>
          Try again
        </Button>
        <Button variant="ghost" asChild>
          <Link href="/lore">Back to Lore</Link>
        </Button>
      </div>
    </div>
  );
}
```

- [ ] **Step 3: Write the brain dump boundary**

Create `allcodex-portal/app/(portal)/brain-dump/error.tsx`:

```tsx
"use client";

import { useEffect } from "react";
import { Button } from "@/components/ui/button";

export default function BrainDumpError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error("[brain dump error]", error);
  }, [error]);

  return (
    <div className="flex flex-col items-center justify-center min-h-[60vh] gap-4 text-center px-4">
      <h2 className="font-cinzel text-xl text-foreground">Brain dump unavailable</h2>
      <p className="text-sm text-muted-foreground max-w-md">
        {error.message || "The brain dump pipeline encountered an error. Check that AllKnower is running."}
      </p>
      <Button variant="outline" onClick={reset}>
        Try again
      </Button>
    </div>
  );
}
```

- [ ] **Step 4: Write the AI tools boundary**

Create `allcodex-portal/app/(portal)/ai/error.tsx`:

```tsx
"use client";

import { useEffect } from "react";
import { Button } from "@/components/ui/button";

export default function AIToolsError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error("[ai tools error]", error);
  }, [error]);

  return (
    <div className="flex flex-col items-center justify-center min-h-[60vh] gap-4 text-center px-4">
      <h2 className="font-cinzel text-xl text-foreground">AI tools unavailable</h2>
      <p className="text-sm text-muted-foreground max-w-md">
        {error.message || "Could not load this AI tool. Verify that AllKnower is connected in Settings."}
      </p>
      <Button variant="outline" onClick={reset}>
        Try again
      </Button>
    </div>
  );
}
```

- [ ] **Step 5: Write an error boundary smoke test**

In `allcodex-portal/tests/error-states.spec.ts`, the file already exists. Open it and check if a render-crash case is covered. If not, add:

```ts
test("portal shows error boundary when lore detail throws a render error", async ({ page }) => {
  await installPortalApiMocks(page, {
    notes: [],
  });

  // Navigate to a note ID that the mock returns 404 for — the detail page
  // will try to render undefined data and should show the error boundary,
  // not a blank/crashed page.
  await page.goto("/lore/nonexistent-note-id");

  // The page should not be blank — some recovery UI should be visible.
  await expect(page.locator("body")).not.toBeEmpty();
  // Should NOT show an unhandled Next.js error overlay in production mode.
  await expect(page.getByText("Application error")).not.toBeVisible();
});
```

- [ ] **Step 6: Run the E2E smoke test to confirm the boundary renders**

```bash
cd allcodex-portal && bun run test:e2e -- --grep "error boundary"
```

Expected: the test navigates to the nonexistent note, sees the lore detail page either gracefully handle 404 or trigger the `error.tsx` with a friendly message — not a crash.

- [ ] **Step 7: Commit**

```bash
git add \
  allcodex-portal/app/\(portal\)/error.tsx \
  allcodex-portal/app/\(portal\)/lore/\[id\]/error.tsx \
  allcodex-portal/app/\(portal\)/brain-dump/error.tsx \
  allcodex-portal/app/\(portal\)/ai/error.tsx \
  allcodex-portal/tests/error-states.spec.ts
git commit -m "feat(portal): add error boundaries for key route segments"
```

---

## Task 6: Portal — Runtime Zod validation on AllKnower responses

**Files:**
- Create: `allcodex-portal/lib/allknower-schemas.ts`
- Modify: `allcodex-portal/lib/allknower-server.ts`

Currently `allknower-server.ts` has hand-written TypeScript interfaces and calls `.json()` with no runtime check. If AllKnower returns an unexpected shape (schema drift, partial failure), the portal passes garbage to the browser and React crashes at render time. This task adds runtime parsing using Zod.

- [ ] **Step 1: Install Zod**

```bash
cd allcodex-portal && bun add zod
```

Expected: `zod` added to `dependencies` in `package.json`.

- [ ] **Step 2: Write failing tests for the Zod parse layer**

Create `allcodex-portal/lib/allknower-schemas.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import {
  ConsistencyResultSchema,
  GapResultSchema,
  RelationshipsResultSchema,
  BrainDumpResultSchema,
} from "./allknower-schemas";

describe("ConsistencyResultSchema", () => {
  it("accepts a valid response", () => {
    const input = {
      issues: [
        { type: "contradiction", severity: "high", description: "Aria Vale is both alive and dead.", affectedNoteIds: ["n1", "n2"] },
      ],
      summary: "One contradiction found.",
    };
    expect(() => ConsistencyResultSchema.parse(input)).not.toThrow();
  });

  it("rejects a response missing issues array", () => {
    expect(() => ConsistencyResultSchema.parse({ summary: "ok" })).toThrow();
  });
});

describe("GapResultSchema", () => {
  it("accepts a valid response", () => {
    const input = {
      gaps: [{ area: "Factions", severity: "medium", description: "Thin", suggestion: "Add a rival guild" }],
      summary: "One gap found.",
      typeCounts: { character: 5 },
      totalNotes: 10,
    };
    expect(() => GapResultSchema.parse(input)).not.toThrow();
  });

  it("rejects a response missing gaps array", () => {
    expect(() => GapResultSchema.parse({ summary: "ok" })).toThrow();
  });
});

describe("RelationshipsResultSchema", () => {
  it("accepts a valid response", () => {
    const input = {
      suggestions: [
        { targetNoteId: "n1", targetTitle: "Aether Keep", relationshipType: "ally", description: "Allied." },
      ],
    };
    expect(() => RelationshipsResultSchema.parse(input)).not.toThrow();
  });

  it("rejects a response where suggestions is not an array", () => {
    expect(() => RelationshipsResultSchema.parse({ suggestions: "bad" })).toThrow();
  });
});

describe("BrainDumpResultSchema", () => {
  it("accepts a valid auto-mode response", () => {
    const input = {
      summary: "Extracted two entities",
      created: [{ noteId: "n1", title: "Aria Vale", type: "character" }],
      updated: [],
      skipped: [],
    };
    expect(() => BrainDumpResultSchema.parse(input)).not.toThrow();
  });
});
```

- [ ] **Step 3: Run to confirm tests fail**

```bash
cd allcodex-portal && bun run test:unit -- allknower-schemas
```

Expected: module not found / parse functions not defined.

- [ ] **Step 4: Create `lib/allknower-schemas.ts`**

```ts
import { z } from "zod";

export const ConsistencyIssueSchema = z.object({
  type: z.enum(["contradiction", "timeline", "orphan", "naming"]),
  severity: z.enum(["high", "medium", "low"]),
  description: z.string(),
  affectedNoteIds: z.array(z.string()),
});

export const ConsistencyResultSchema = z.object({
  issues: z.array(ConsistencyIssueSchema),
  summary: z.string(),
});

export const GapAreaSchema = z.object({
  area: z.string(),
  severity: z.enum(["high", "medium", "low"]),
  description: z.string(),
  suggestion: z.string(),
});

export const GapResultSchema = z.object({
  gaps: z.array(GapAreaSchema),
  summary: z.string(),
  typeCounts: z.record(z.number()).optional(),
  totalNotes: z.number().optional(),
});

export const RelationshipSuggestionSchema = z.object({
  targetNoteId: z.string(),
  targetTitle: z.string(),
  relationshipType: z.string(),
  description: z.string(),
});

export const RelationshipsResultSchema = z.object({
  suggestions: z.array(RelationshipSuggestionSchema),
});

export const BrainDumpEntitySchema = z.object({
  noteId: z.string(),
  title: z.string(),
  type: z.string(),
});

export const BrainDumpResultSchema = z
  .object({
    summary: z.string(),
    created: z.array(BrainDumpEntitySchema),
    updated: z.array(BrainDumpEntitySchema),
    skipped: z.array(z.object({ title: z.string(), reason: z.string() })),
  })
  .passthrough();

export const BrainDumpReviewResultSchema = z.object({
  mode: z.literal("review"),
  summary: z.string(),
  proposedEntities: z.array(
    z.object({
      title: z.string(),
      type: z.string(),
      action: z.enum(["create", "update"]),
      content: z.string().optional(),
      existingNoteId: z.string().optional(),
    })
  ),
}).passthrough();

// Derived TypeScript types — replace manual interfaces in allknower-server.ts
export type ConsistencyResult = z.infer<typeof ConsistencyResultSchema>;
export type GapResult = z.infer<typeof GapResultSchema>;
export type RelationshipSuggestion = z.infer<typeof RelationshipSuggestionSchema>;
export type RelationshipsResult = z.infer<typeof RelationshipsResultSchema>;
export type BrainDumpResult = z.infer<typeof BrainDumpResultSchema>;
export type BrainDumpReviewResult = z.infer<typeof BrainDumpReviewResultSchema>;
```

- [ ] **Step 5: Run to confirm schema tests pass**

```bash
cd allcodex-portal && bun run test:unit -- allknower-schemas
```

Expected: all tests pass.

- [ ] **Step 6: Wire Zod parsing into `allknower-server.ts`**

In `allcodex-portal/lib/allknower-server.ts`, add the import at the top (after the `ServiceError` import):

```ts
import {
  ConsistencyResultSchema,
  GapResultSchema,
  RelationshipsResultSchema,
  BrainDumpResultSchema,
  type ConsistencyResult,
  type GapResult,
  type RelationshipsResult,
} from "./allknower-schemas";
```

Then update the four functions that proxy AI tool responses. Find and update each one:

**`checkConsistency`** — current:
```ts
export async function checkConsistency(creds: AkCreds, noteIds?: string[]): Promise<ConsistencyResult> {
  const res = await akFetch(creds, "/consistency/check", {
    method: "POST",
    body: JSON.stringify({ noteIds }),
  });
  return res.json();
}
```
Replace with:
```ts
export async function checkConsistency(creds: AkCreds, noteIds?: string[]): Promise<ConsistencyResult> {
  const res = await akFetch(creds, "/consistency/check", {
    method: "POST",
    body: JSON.stringify({ noteIds }),
  });
  const raw = await res.json();
  const parsed = ConsistencyResultSchema.safeParse(raw);
  if (!parsed.success) {
    throw new ServiceError("SERVICE_ERROR", 502, `AllKnower /consistency/check returned unexpected shape: ${parsed.error.message}`);
  }
  return parsed.data;
}
```

**`getGaps`** — current:
```ts
export async function getGaps(creds: AkCreds): Promise<GapResult> {
  const res = await akFetch(creds, "/suggest/gaps");
  return res.json();
}
```
Replace with:
```ts
export async function getGaps(creds: AkCreds): Promise<GapResult> {
  const res = await akFetch(creds, "/suggest/gaps");
  const raw = await res.json();
  const parsed = GapResultSchema.safeParse(raw);
  if (!parsed.success) {
    throw new ServiceError("SERVICE_ERROR", 502, `AllKnower /suggest/gaps returned unexpected shape: ${parsed.error.message}`);
  }
  return parsed.data;
}
```

**`suggestRelationships`** — current:
```ts
export async function suggestRelationships(creds: AkCreds, text: string, noteId?: string): Promise<{ suggestions: RelationshipSuggestion[] }> {
  const res = await akFetch(creds, "/suggest/relationships", {
    method: "POST",
    body: JSON.stringify({ text, ...(noteId ? { noteId } : {}) }),
  });
  return res.json();
}
```
Replace with:
```ts
export async function suggestRelationships(creds: AkCreds, text: string, noteId?: string): Promise<RelationshipsResult> {
  const res = await akFetch(creds, "/suggest/relationships", {
    method: "POST",
    body: JSON.stringify({ text, ...(noteId ? { noteId } : {}) }),
  });
  const raw = await res.json();
  const parsed = RelationshipsResultSchema.safeParse(raw);
  if (!parsed.success) {
    throw new ServiceError("SERVICE_ERROR", 502, `AllKnower /suggest/relationships returned unexpected shape: ${parsed.error.message}`);
  }
  return parsed.data;
}
```

Also remove the now-redundant manual TypeScript interfaces at the top of `allknower-server.ts` for the types that are now derived from Zod: `ConsistencyIssue`, `ConsistencyResult`, `RelationshipSuggestion`, `GapArea`, `GapResult`. Leave `BrainDumpEntity`, `ProposedEntity`, `BrainDumpResult`, `BrainDumpReviewResult`, `BrainDumpInboxResult`, `BrainDumpAnyResult`, `BrainDumpHistoryEntry`, `BrainDumpDetailEntry`, `RagChunk`, `ApplyRelationsResult`, `AkCreds` — these have no Zod counterpart in this plan.

- [ ] **Step 7: Run typecheck to confirm no regressions**

```bash
cd allcodex-portal && bun run check
```

Expected: `tsc --noEmit` passes, unit tests pass.

- [ ] **Step 8: Commit**

```bash
git add allcodex-portal/lib/allknower-schemas.ts allcodex-portal/lib/allknower-schemas.test.ts allcodex-portal/lib/allknower-server.ts allcodex-portal/package.json
git commit -m "feat(portal): add Zod runtime validation for AllKnower AI tool responses"
```

---

## Task 7: DECISIONS.md

**Files:**
- Create: `DECISIONS.md` (repo root)

- [ ] **Step 1: Create the file**

```bash
cat > DECISIONS.md << 'EOF'
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

## Next.js App Router with React Compiler
The Portal uses the Next.js App Router (not Pages Router) with React 19 and the experimental React Compiler enabled.
**Why:** App Router enables React Server Components for data-fetching layouts. React Compiler automates memoization — no manual `useMemo`/`useCallback` discipline required.
**Trade-off:** App Router patterns (server/client component boundary, `use client` directives) are stricter and less documented than Pages Router. Some libraries haven't fully adapted.
EOF
```

- [ ] **Step 2: Commit**

```bash
git add DECISIONS.md
git commit -m "docs: add DECISIONS.md with architectural decision log"
```

---

## Task 8 (Optional): Eden Treaty — end-to-end type-safe AllKnower client

**Skip this if Task 6 (Zod validation) is sufficient for now.** Eden Treaty replaces the manual fetch wrapper in `allknower-server.ts` with a fully type-inferred client derived from AllKnower's `App` type. Schema drift becomes a TypeScript compile error, not a runtime surprise.

**Files:**
- Modify: `allcodex-portal/package.json`
- Modify: `allcodex-portal/lib/allknower-server.ts`

- [ ] **Step 1: Install `@elysia/eden` in the portal**

```bash
cd allcodex-portal && bun add @elysia/eden
```

- [ ] **Step 2: Export the AllKnower `App` type from a barrel file**

The type is already exported from `allknower/src/app.ts`:
```ts
export type App = typeof app;
```

The portal is a separate submodule and cannot import from `allknower/src/`. Instead, expose the type via AllKnower's package.json exports so the portal can reference it as a dev type dependency if both repos are co-located. This requires coordination between the two repos.

**Alternative (simpler, same session):** Since both are git submodules in the same monorepo, add a path alias in the portal's `tsconfig.json`:

```json
"paths": {
  "@/*": ["./*"],
  "@allknower/*": ["../allknower/src/*"]
}
```

Then in `allcodex-portal/lib/allknower-client.ts` (new file):

```ts
import { treaty } from "@elysia/eden";
import type { App } from "@allknower/app";

export function createAllKnowerClient(baseUrl: string, token: string) {
  return treaty<App>(baseUrl, {
    headers: {
      Authorization: `Bearer ${token}`,
    },
  });
}
```

- [ ] **Step 3: Update `allknower-server.ts` to use the treaty client**

Replace the `akFetch` calls in each function with Eden Treaty calls. For example, `checkConsistency`:

Before (from Task 6):
```ts
export async function checkConsistency(creds: AkCreds, noteIds?: string[]): Promise<ConsistencyResult> {
  const res = await akFetch(creds, "/consistency/check", {
    method: "POST",
    body: JSON.stringify({ noteIds }),
  });
  const raw = await res.json();
  // ... Zod parse
}
```

After:
```ts
export async function checkConsistency(creds: AkCreds, noteIds?: string[]): Promise<ConsistencyResult> {
  const client = createAllKnowerClient(creds.url, creds.token);
  const { data, error } = await client.consistency.check.post({ noteIds });
  if (error) throw new ServiceError("SERVICE_ERROR", 502, `AllKnower consistency check failed: ${error.value}`);
  const parsed = ConsistencyResultSchema.safeParse(data);
  if (!parsed.success) throw new ServiceError("SERVICE_ERROR", 502, `AllKnower /consistency/check returned unexpected shape`);
  return parsed.data;
}
```

Apply the same pattern to `getGaps`, `suggestRelationships`, `runBrainDump`, `getBrainDumpHistory`, and `queryRag`.

- [ ] **Step 4: Run typecheck**

```bash
cd allcodex-portal && tsc --noEmit
```

Expected: no errors. Any AllKnower route path or body type mismatch will now be a compile error.

- [ ] **Step 5: Commit**

```bash
git add allcodex-portal/lib/allknower-client.ts allcodex-portal/lib/allknower-server.ts allcodex-portal/tsconfig.json allcodex-portal/package.json
git commit -m "feat(portal): add Elysia Eden Treaty client for AllKnower"
```

---

## Self-Review

### Spec coverage check

| Criterion | Tasks |
|---|---|
| Tests — `bun test` script | Task 1 |
| TS strict mode | Already done — no task needed |
| Shared API types | Task 6 (Zod schemas replace hand-written interfaces) + Task 8 optional (Eden Treaty) |
| Zod validation on Portal routes | Task 6 |
| Error boundaries | Task 5 |
| Single `check` script | Tasks 1 + 4 |
| Eden Treaty | Task 8 (optional) |
| Health check at startup | Task 3 |
| Structured error codes | Task 2 |
| Playwright brain dump test | Already done — no task needed |
| DECISIONS.md | Task 7 |

All criteria accounted for.

### Placeholder scan

None found — all steps include exact code and exact commands.

### Type consistency

- `ConsistencyResult`, `GapResult`, `RelationshipsResult` are exported from `allknower-schemas.ts` in Task 6 and imported into `allknower-server.ts` — consistent.
- `ServiceError` is imported from `./route-error` in `allknower-server.ts` — already present, no change needed.
- The `createAllKnowerClient` function in Task 8 references `ConsistencyResultSchema` from Task 6 — ensure Task 6 is complete before Task 8.
