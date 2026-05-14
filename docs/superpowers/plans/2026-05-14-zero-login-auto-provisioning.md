# Zero-Login Auto-Provisioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate all manual login and credential configuration — Portal auto-provisions a session on first visit, AllKnower bootstraps a default user and ETAPI token on startup, Core auto-sets its password from an environment variable.

**Architecture:** Three-layer bootstrap chain: Core auto-sets password from `ALLCODEX_BOOTSTRAP_PASSWORD` env var on first boot. AllKnower on startup creates a default user (if none exists) and obtains an ETAPI token from Core (with retry backoff). Portal middleware detects missing session cookies and calls AllKnower's internal auto-provision endpoint to get a session token. The result: user opens Portal → everything works immediately, no login, no settings.

**Tech Stack:** AllKnower (Bun/Elysia/Prisma/better-auth), Portal (Next.js 16 App Router/Bun), Core (Express 5/SQLite/pnpm)

---

## Design Decisions

1. **Single shared user model**: AllKnower picks `users.findFirst()` — if a user already exists (from testing), it becomes "the default." Only creates `default@local` if no users exist. This avoids orphaning existing brain-dump history and UserIntegration rows.

2. **Bootstrap at startup, provision at request-time**: AllKnower creates the default user + ETAPI token on boot (async, non-blocking, with retry). Portal middleware only asks "give me a session" — fast, no racing against Core startup.

3. **Transparent to existing credential chain**: By auto-setting `allknower_url` and `allknower_token` cookies, the entire existing `getEtapiCreds()` → `resolveAllCodexCredentials()` chain works unchanged. Zero changes to the ETAPI resolution hot path.

4. **Dev-default PORTAL_INTERNAL_SECRET**: Both AllKnower and Portal use `dev-portal-secret-32chars!!!` as the default in non-production. Production check unchanged (≥16 chars required).

5. **Settings page → status dashboard with advanced override**: Connection cards show auto-provisioned status by default. Input fields hidden behind "Show Advanced" disclosure for debugging/override.

---

## Execution Order

```
Stream A: Core (1 task, ~20 min)
  A1: Auto-password from env var

Stream B: AllKnower (4 tasks, ~2h, sequential)
  B1 → B2 → B3 → B4

Stream C: Portal (2 tasks, ~1.5h, depends on B3)
  C1 → C2
```

Cross-stream dependency: B3 (auto-provision endpoint) must exist before C1 (Portal middleware) can call it. A1 should land before B2 so bootstrap can create ETAPI tokens.

---

## Stream A: Core

Working directory: `/Users/allmaker/projects/allcodex-aio/allcodex-core`

### Task A1: Auto-Set Password from Environment Variable

**Findings:** Core requires a password before ETAPI tokens can be created. Currently requires manual `/set-password` visit.

**Files:**
- Modify: `apps/server/src/services/encryption/password.ts:80-85`
- Modify: `apps/server/src/services/sql_init.ts:215-231`

- [ ] **Step 1: Add `autoSetFromEnv` to password.ts**

In `apps/server/src/services/encryption/password.ts`, add a new function before the `export default`:

```typescript
function autoSetFromEnv(): boolean {
    const envPassword = process.env.ALLCODEX_BOOTSTRAP_PASSWORD;
    if (!envPassword) return false;
    if (isPasswordSet()) return false;
    if (envPassword.length < 4) {
        console.warn("ALLCODEX_BOOTSTRAP_PASSWORD is too short (min 4 chars). Skipping auto-set.");
        return false;
    }
    setPassword(envPassword);
    return true;
}
```

Update the export:

```typescript
export default {
    isPasswordSet,
    changePassword,
    setPassword,
    resetPassword,
    autoSetFromEnv
};
```

- [ ] **Step 2: Hook auto-set into DB ready**

In `apps/server/src/services/sql_init.ts`, find the `dbReady.then(() => {` block at line ~215. Add password auto-set at the beginning of the callback:

```typescript
dbReady.then(() => {
    if (password.autoSetFromEnv()) {
        log.info("Password auto-set from ALLCODEX_BOOTSTRAP_PASSWORD environment variable.");
    }

    // ... existing backup/optimization scheduling code unchanged
});
```

The import for `password` already exists at line 15: `import password from "./encryption/password.js";`

- [ ] **Step 3: Verify**

```bash
cd /Users/allmaker/projects/allcodex-aio/allcodex-core && pnpm typecheck
```

- [ ] **Step 4: Test manually**

Set `ALLCODEX_BOOTSTRAP_PASSWORD=testpassword123` in environment, start server with a fresh DB:

```bash
ALLCODEX_BOOTSTRAP_PASSWORD=testpassword123 pnpm server:start
```

Verify:
- Log should show "Password auto-set from ALLCODEX_BOOTSTRAP_PASSWORD"
- `POST /etapi/auth/login` with `{"password":"testpassword123"}` should return 201 with `authToken`
- Restarting the server should NOT re-set the password (already set)

- [ ] **Step 5: Commit**

```bash
git add apps/server/src/services/encryption/password.ts apps/server/src/services/sql_init.ts
git commit -m "feat(core): auto-set server password from ALLCODEX_BOOTSTRAP_PASSWORD env var

If the password has not been set yet and ALLCODEX_BOOTSTRAP_PASSWORD is
present in the environment, automatically set it on DB ready. Skips if
password is already configured. Enables fully automated ETAPI token
bootstrapping without manual /set-password visit."
```

---

## Stream B: AllKnower

Working directory: `/Users/allmaker/projects/allcodex-aio/allknower`

### Task B1: Environment Variables + Dev Defaults

**Files:**
- Modify: `src/env.ts:102-103`
- Modify: `.env.example`

- [ ] **Step 1: Add ALLCODEX_PASSWORD and update PORTAL_INTERNAL_SECRET default**

In `src/env.ts`, find the `ALLCODEX_ETAPI_TOKEN` line (line ~103). After it, add `ALLCODEX_PASSWORD`. Also update `PORTAL_INTERNAL_SECRET` default:

Replace:
```typescript
    PORTAL_INTERNAL_SECRET: z.string().default(""),
```

With:
```typescript
    PORTAL_INTERNAL_SECRET: z.string().default(
        process.env.NODE_ENV === "production" ? "" : "dev-portal-secret-32chars!!!"
    ),
```

After the `ALLCODEX_ETAPI_TOKEN` line, add:
```typescript
    ALLCODEX_PASSWORD: z.string().default(""),
```

- [ ] **Step 2: Update .env.example**

In `.env.example`, add under the AllCodex ETAPI section:

```bash
# AllCodex server password — used by bootstrap to auto-create ETAPI tokens.
# Only needed for initial setup; once a token is obtained, this is not used again.
# ALLCODEX_PASSWORD=

# Portal-to-AllKnower internal secret — must match Portal's PORTAL_INTERNAL_SECRET.
# Dev default: "dev-portal-secret-32chars!!!" (auto-used in non-production).
# PORTAL_INTERNAL_SECRET=
```

- [ ] **Step 3: Verify**

```bash
bun typecheck
```

- [ ] **Step 4: Commit**

```bash
git add src/env.ts .env.example
git commit -m "feat(env): add ALLCODEX_PASSWORD, dev-default PORTAL_INTERNAL_SECRET

ALLCODEX_PASSWORD enables automatic ETAPI token bootstrap.
PORTAL_INTERNAL_SECRET gets a dev-default so auto-provision works
without manual .env setup in development."
```

---

### Task B2: Bootstrap Module — Default User + ETAPI Token

**Files:**
- Create: `src/bootstrap/index.ts`
- Create: `src/bootstrap/ensure-default-user.ts`
- Create: `src/bootstrap/ensure-etapi-token.ts`

- [ ] **Step 1: Create `ensure-default-user.ts`**

```typescript
// src/bootstrap/ensure-default-user.ts
import prisma from "../db/client.ts";
import { auth } from "../auth/index.ts";
import { env } from "../env.ts";
import { rootLogger } from "../logger.ts";

const log = rootLogger.child({ module: "bootstrap" });

const DEFAULT_EMAIL = "default@local";
const DEFAULT_NAME = "Default User";

export interface DefaultUser {
    id: string;
    email: string;
    name: string | null;
    isNew: boolean;
}

export async function ensureDefaultUser(): Promise<DefaultUser> {
    const existing = await prisma.user.findFirst({
        select: { id: true, email: true, name: true },
    });

    if (existing) {
        log.info(`Default user resolved: ${existing.email} (${existing.id})`);
        return { ...existing, isNew: false };
    }

    log.info("No users found. Creating default user...");

    const password = env.ALLCODEX_PASSWORD || "allcodex-default-password";

    const res = await fetch(`${env.BETTER_AUTH_URL}/api/auth/sign-up/email`, {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            Origin: env.BETTER_AUTH_URL,
        },
        body: JSON.stringify({
            email: DEFAULT_EMAIL,
            password,
            name: DEFAULT_NAME,
        }),
    });

    if (!res.ok) {
        const body = await res.text().catch(() => "");
        throw new Error(`Failed to create default user: ${res.status} ${body}`);
    }

    const user = await prisma.user.findFirst({
        where: { email: DEFAULT_EMAIL },
        select: { id: true, email: true, name: true },
    });

    if (!user) {
        throw new Error("Default user was created but not found in database");
    }

    log.info(`Default user created: ${user.email} (${user.id})`);
    return { ...user, isNew: true };
}
```

- [ ] **Step 2: Create `ensure-etapi-token.ts`**

```typescript
// src/bootstrap/ensure-etapi-token.ts
import prisma from "../db/client.ts";
import { env } from "../env.ts";
import { invalidateCredentialCache } from "../etapi/client.ts";
import { connectAllCodexIntegration } from "../integrations/allcodex.ts";
import { rootLogger } from "../logger.ts";

const log = rootLogger.child({ module: "bootstrap" });

export async function ensureEtapiToken(defaultUserId: string): Promise<void> {
    const existingToken = await prisma.appConfig.findUnique({
        where: { key: "allcodexToken" },
    });

    if (existingToken?.value) {
        log.info("ETAPI token already configured in AppConfig.");
        await ensureUserIntegration(defaultUserId, env.ALLCODEX_URL, existingToken.value);
        return;
    }

    if (!env.ALLCODEX_PASSWORD) {
        if (env.ALLCODEX_ETAPI_TOKEN) {
            log.info("Using ALLCODEX_ETAPI_TOKEN from env (no password for bootstrap).");
            await persistToken(defaultUserId, env.ALLCODEX_URL, env.ALLCODEX_ETAPI_TOKEN);
            return;
        }
        log.warn("No ALLCODEX_PASSWORD or ALLCODEX_ETAPI_TOKEN — cannot bootstrap ETAPI token. Manual configuration required.");
        return;
    }

    log.info("Requesting ETAPI token from Core...");

    const res = await fetch(`${env.ALLCODEX_URL}/etapi/auth/login`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
            password: env.ALLCODEX_PASSWORD,
            tokenName: "AllKnower (auto-provisioned)",
        }),
        signal: AbortSignal.timeout(10_000),
    });

    if (!res.ok) {
        const body = await res.text().catch(() => "");
        throw new Error(`ETAPI login failed: ${res.status} ${body}`);
    }

    const { authToken } = (await res.json()) as { authToken: string };
    log.info("ETAPI token obtained from Core.");

    await persistToken(defaultUserId, env.ALLCODEX_URL, authToken);
}

async function persistToken(userId: string, url: string, token: string): Promise<void> {
    await Promise.all([
        prisma.appConfig.upsert({
            where: { key: "allcodexUrl" },
            update: { value: url },
            create: { key: "allcodexUrl", value: url },
        }),
        prisma.appConfig.upsert({
            where: { key: "allcodexToken" },
            update: { value: token },
            create: { key: "allcodexToken", value: token },
        }),
    ]);

    invalidateCredentialCache();

    await ensureUserIntegration(userId, url, token);

    rootLogger.child({ module: "bootstrap" }).info("ETAPI credentials persisted to AppConfig + UserIntegration.");
}

async function ensureUserIntegration(userId: string, baseUrl: string, token: string): Promise<void> {
    const existing = await prisma.userIntegration.findUnique({
        where: { userId_provider: { userId, provider: "allcodex" } },
    });

    if (existing) return;

    await connectAllCodexIntegration(userId, { baseUrl, token });
}
```

- [ ] **Step 3: Create `bootstrap/index.ts`**

```typescript
// src/bootstrap/index.ts
import { ensureDefaultUser } from "./ensure-default-user.ts";
import { ensureEtapiToken } from "./ensure-etapi-token.ts";
import { rootLogger } from "../logger.ts";

const log = rootLogger.child({ module: "bootstrap" });

export type BootstrapStatus = {
    ran: boolean;
    userReady: boolean;
    etapiReady: boolean;
    error?: string;
};

let _status: BootstrapStatus = {
    ran: false,
    userReady: false,
    etapiReady: false,
};

export function getBootstrapStatus(): BootstrapStatus {
    return { ..._status };
}

async function attempt(): Promise<void> {
    const user = await ensureDefaultUser();
    _status.userReady = true;

    await ensureEtapiToken(user.id);
    _status.etapiReady = true;
}

export async function runBootstrap(): Promise<void> {
    const MAX_ATTEMPTS = 6;
    const DELAY_MS = 5_000;

    for (let i = 1; i <= MAX_ATTEMPTS; i++) {
        try {
            await attempt();
            _status.ran = true;
            log.info("Bootstrap complete.");
            return;
        } catch (e) {
            const msg = e instanceof Error ? e.message : String(e);
            log.warn(`Bootstrap attempt ${i}/${MAX_ATTEMPTS} failed: ${msg}`);
            _status.error = msg;

            if (_status.userReady && !_status.etapiReady) {
                log.info("User ready but ETAPI failed — Core may not be up yet. Retrying...");
            }

            if (i < MAX_ATTEMPTS) {
                await new Promise((r) => setTimeout(r, DELAY_MS));
            }
        }
    }

    _status.ran = true;
    log.error(`Bootstrap failed after ${MAX_ATTEMPTS} attempts. Check service connectivity and env vars.`);
}
```

- [ ] **Step 4: Verify**

```bash
bun typecheck
```

- [ ] **Step 5: Commit**

```bash
git add src/bootstrap/
git commit -m "feat(bootstrap): auto-provision default user and ETAPI token on startup

ensureDefaultUser: picks first existing user or creates default@local.
ensureEtapiToken: obtains ETAPI token from Core via password, persists
to both AppConfig (global) and UserIntegration (per-user).
Retry with backoff (6 attempts, 5s delay) for Core startup races."
```

---

### Task B3: Auto-Provision Endpoint

**Files:**
- Create: `src/routes/auto-provision.ts`
- Modify: `src/app.ts:75-76`

- [ ] **Step 1: Create auto-provision route**

```typescript
// src/routes/auto-provision.ts
import { Elysia } from "elysia";
import { randomBytes } from "crypto";
import prisma from "../db/client.ts";
import { env } from "../env.ts";
import { getBootstrapStatus } from "../bootstrap/index.ts";
import { rootLogger } from "../logger.ts";

const log = rootLogger.child({ module: "auto-provision" });

export const autoProvisionRoute = new Elysia({ name: "auto-provision" }).post(
    "/internal/auto-provision",
    async ({ request, set }) => {
        if (!env.PORTAL_INTERNAL_SECRET) {
            set.status = 503;
            return { error: "PORTAL_INTERNAL_SECRET is not configured." };
        }

        if (request.headers.get("X-Portal-Internal-Secret") !== env.PORTAL_INTERNAL_SECRET) {
            set.status = 403;
            return { error: "Forbidden" };
        }

        const status = getBootstrapStatus();
        if (!status.userReady) {
            set.status = 503;
            return { error: "Bootstrap not complete — no default user.", bootstrapStatus: status };
        }

        const defaultUser = await prisma.user.findFirst({
            select: { id: true, email: true, name: true },
        });

        if (!defaultUser) {
            set.status = 503;
            return { error: "No users in database." };
        }

        const existingSession = await prisma.session.findFirst({
            where: {
                userId: defaultUser.id,
                expiresAt: { gt: new Date() },
                userAgent: "auto-provision",
            },
            select: { token: true, expiresAt: true },
        });

        if (existingSession) {
            log.info(`Reusing existing auto-provision session for ${defaultUser.email}`);
            return {
                token: existingSession.token,
                url: env.BETTER_AUTH_URL,
                userId: defaultUser.id,
                expiresAt: existingSession.expiresAt.toISOString(),
            };
        }

        const token = randomBytes(32).toString("hex");
        const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

        await prisma.session.create({
            data: {
                userId: defaultUser.id,
                token,
                expiresAt,
                ipAddress: "internal",
                userAgent: "auto-provision",
            },
        });

        log.info(`Auto-provisioned session for ${defaultUser.email}`);

        return {
            token,
            url: env.BETTER_AUTH_URL,
            userId: defaultUser.id,
            expiresAt: expiresAt.toISOString(),
        };
    },
    {
        detail: {
            tags: ["System"],
            summary: "Auto-provision a session for the default user (Portal middleware)",
        },
    }
);
```

- [ ] **Step 2: Mount route in app.ts**

In `src/app.ts`, add the import after the existing route imports (line ~15):

```typescript
import { autoProvisionRoute } from "./routes/auto-provision.ts";
```

In the route chain (after `internalIntegrationsRoute`, line ~76), add:

```typescript
    .use(autoProvisionRoute)
```

- [ ] **Step 3: Verify**

```bash
bun typecheck
```

- [ ] **Step 4: Commit**

```bash
git add src/routes/auto-provision.ts src/app.ts
git commit -m "feat(routes): add /internal/auto-provision endpoint

Portal middleware calls this to get a session token for the default user.
Gated by X-Portal-Internal-Secret header. Reuses existing auto-provision
sessions to avoid creating duplicate rows."
```

---

### Task B4: Wire Bootstrap into Startup + Health Route

**Files:**
- Modify: `src/index.ts:16-35`
- Modify: `src/routes/health.ts:9-22`

- [ ] **Step 1: Call bootstrap after listen**

Replace `src/index.ts` entirely:

```typescript
import { app } from "./app.ts";
import { env } from "./env.ts";
import { runBootstrap } from "./bootstrap/index.ts";

const PORT = env.PORT;

await app.listen(PORT);

const origin = `http://${app.server!.hostname}:${app.server!.port}`;

console.log(
    `\n🧠 AllKnower is running at ${origin}\n` +
    `   📖 API docs: ${origin}/reference\n` +
    `   ❤️  Health:   ${origin}/health\n`
);

runBootstrap().catch((e) => {
    console.error("❌ Bootstrap failed unexpectedly:", e);
});
```

Note: `runBootstrap()` is fire-and-forget. It has its own retry logic and logging. The server is fully operational while bootstrap runs — existing manual flows still work if bootstrap hasn't completed yet.

- [ ] **Step 2: Expose bootstrap status in health route**

In `src/routes/health.ts`, add the import:

```typescript
import { getBootstrapStatus } from "../bootstrap/index.ts";
```

In the handler, after the existing `checks` object (line ~22), add bootstrap status:

```typescript
        const bootstrap = getBootstrapStatus();

        const checks = {
            allcodex: resolve(allcodex),
            lancedb: resolve(lancedb),
            database: resolve(db),
            bootstrap: {
                ok: bootstrap.userReady && bootstrap.etapiReady,
                ran: bootstrap.ran,
                userReady: bootstrap.userReady,
                etapiReady: bootstrap.etapiReady,
                ...(bootstrap.error ? { lastError: bootstrap.error } : {}),
            },
        };
```

- [ ] **Step 3: Verify**

```bash
bun typecheck
```

- [ ] **Step 4: Test manually**

Start AllKnower with Core running and proper env vars:

```bash
ALLCODEX_PASSWORD=testpassword123 bun dev
```

Check:
- Logs show "Bootstrap complete" or retry attempts
- `GET /health` returns `bootstrap.ok: true`
- `POST /internal/auto-provision` with correct secret returns a token

- [ ] **Step 5: Commit**

```bash
git add src/index.ts src/routes/health.ts
git commit -m "feat(startup): run bootstrap on server start, expose status in /health

Bootstrap runs non-blocking after listen. Health route includes
bootstrap.ok, .userReady, .etapiReady fields. Server remains
fully operational while bootstrap retries against Core."
```

---

## Stream C: Portal

Working directory: `/Users/allmaker/projects/allcodex-aio/allcodex-portal`

### Task C1: Auto-Provision Middleware + Settings Refactor

**Files:**
- Create: `middleware.ts`
- Modify: `app/(portal)/settings/page.tsx`
- Modify: `.env.example` (if it exists, otherwise `.env.local` docs)

- [ ] **Step 1: Create Next.js middleware**

Create `middleware.ts` in the Portal root:

```typescript
import { NextRequest, NextResponse } from "next/server";

const ALLKNOWER_URL = process.env.ALLKNOWER_URL || "http://localhost:3001";
const PORTAL_INTERNAL_SECRET = process.env.PORTAL_INTERNAL_SECRET || "dev-portal-secret-32chars!!!";

const COOKIE_OPTS = {
    httpOnly: true,
    sameSite: "lax" as const,
    path: "/",
    secure: process.env.NODE_ENV === "production",
    maxAge: 60 * 60 * 24 * 30,
};

const PROVISION_COOLDOWN_SECONDS = 30;

export async function middleware(request: NextRequest) {
    const hasToken = request.cookies.get("allknower_token")?.value;
    if (hasToken) return NextResponse.next();

    const cooldown = request.cookies.get("_ak_provision_attempted")?.value;
    if (cooldown) return NextResponse.next();

    if (!ALLKNOWER_URL || !PORTAL_INTERNAL_SECRET) {
        return NextResponse.next();
    }

    try {
        const res = await fetch(`${ALLKNOWER_URL}/internal/auto-provision`, {
            method: "POST",
            headers: {
                "X-Portal-Internal-Secret": PORTAL_INTERNAL_SECRET,
                "Content-Type": "application/json",
            },
            signal: AbortSignal.timeout(5_000),
        });

        if (!res.ok) {
            const response = NextResponse.next();
            response.cookies.set("_ak_provision_attempted", "1", {
                httpOnly: true,
                path: "/",
                maxAge: PROVISION_COOLDOWN_SECONDS,
            });
            return response;
        }

        const { token, url } = (await res.json()) as { token: string; url: string };

        const response = NextResponse.next();
        response.cookies.set("allknower_token", token, COOKIE_OPTS);
        response.cookies.set("allknower_url", url, COOKIE_OPTS);
        return response;
    } catch {
        const response = NextResponse.next();
        response.cookies.set("_ak_provision_attempted", "1", {
            httpOnly: true,
            path: "/",
            maxAge: PROVISION_COOLDOWN_SECONDS,
        });
        return response;
    }
}

export const config = {
    matcher: [
        "/((?!_next/static|_next/image|favicon.ico|api/auth|api/config/status).*)",
    ],
};
```

Key design choices in the middleware:
- **Cooldown cookie**: If auto-provision fails, sets a 30s cooldown cookie so we don't hammer AllKnower on every request.
- **Matcher excludes**: `_next/static`, `_next/image`, `favicon.ico` (static assets), `api/auth` (auth routes should work without session), `api/config/status` (health probe should work unconditionally).
- **Graceful fallback**: If AllKnower is unreachable, middleware does nothing — existing manual flow still works via settings page.

- [ ] **Step 2: Refactor settings page — status dashboard with advanced override**

Replace `app/(portal)/settings/page.tsx` with:

```tsx
"use client";

import { useState, useEffect, useCallback } from "react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Label } from "@/components/ui/label";
import { StatusBadge } from "@/components/portal/StatusBadge";
import {
  CheckCircle2,
  Loader2,
  Link2,
  Unlink,
  Key,
  Lock,
  Brain,
  Scroll,
  UserPlus,
  LogIn,
  Globe,
  ExternalLink,
  ChevronDown,
  ChevronRight,
  Settings2,
} from "lucide-react";

// ── Types ──────────────────────────────────────────────────────────────────────

type ConnState = "unknown" | "checking" | "connected" | "disconnected" | "error";

interface StatusPayload {
  allcodex: { ok: boolean; configured: boolean; url: string | null; version?: string; error?: string };
  allknower: { ok: boolean; configured: boolean; url: string | null; error?: string };
}

// ── AllCodex card ──────────────────────────────────────────────────────────────

function AllCodexCard({ initialStatus }: { initialStatus?: StatusPayload["allcodex"] }) {
  const [state, setState] = useState<ConnState>(
    initialStatus?.ok ? "connected" : initialStatus?.configured ? "error" : "disconnected"
  );
  const [version, setVersion] = useState(initialStatus?.version);
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [url, setUrl] = useState(initialStatus?.url ?? "http://localhost:8080");
  const [token, setToken] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const isConnected = state === "connected";

  async function handleConnectToken() {
    if (!url || !token) return;
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/integrations/allcodex/connect", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ baseUrl: url, token }),
      });
      if (!res.ok) throw new Error((await res.json()).error);
      const status = await fetch("/api/config/status").then((r) => r.json());
      if (status.allcodex.ok) {
        setState("connected");
        setVersion(status.allcodex.version);
      } else {
        setState("error");
        setError(status.allcodex.error ?? "Could not reach AllCodex");
      }
    } catch (e) {
      setState("error");
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }

  async function handleLoginPassword() {
    if (!url || !password) return;
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/config/allknower-login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ url, password }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setState("connected");
      setPassword("");
      const status = await fetch("/api/config/status").then((r) => r.json());
      setVersion(status.allcodex.version);
    } catch (e) {
      setState("error");
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }

  async function handleDisconnect() {
    setLoading(true);
    try {
      await fetch("/api/integrations/allcodex", { method: "DELETE" });
    } catch {}
    setState("disconnected");
    setVersion(undefined);
    setToken("");
    setPassword("");
    setError(null);
    setLoading(false);
  }

  return (
    <div className="rounded-none border border-border/30 border-l-2 border-l-primary/60 bg-card/40 overflow-hidden">
      <div className="px-5 py-4 border-b border-border/20 flex items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <Scroll className="h-4 w-4 text-primary" />
          <div>
            <h3 className="text-sm font-semibold text-primary" style={{ fontFamily: "var(--font-cinzel)" }}>AllCodex</h3>
            <p className="text-[11px] text-muted-foreground">Trilium notes — ETAPI</p>
          </div>
        </div>
        <StatusBadge state={state} version={version} />
      </div>

      <div className="px-5 py-4 space-y-4">
        {isConnected && (
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <CheckCircle2 className="h-4 w-4 text-emerald-500" />
            <span>Auto-connected via AllKnower bootstrap</span>
            {url && <span className="font-mono text-xs opacity-60">({url})</span>}
          </div>
        )}

        <button
          onClick={() => setShowAdvanced(!showAdvanced)}
          className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors"
        >
          {showAdvanced ? <ChevronDown className="h-3 w-3" /> : <ChevronRight className="h-3 w-3" />}
          <Settings2 className="h-3 w-3" />
          Advanced / Override
        </button>

        {showAdvanced && (
          <div className="space-y-4 border-t border-border/20 pt-4">
            <div className="space-y-1.5">
              <Label htmlFor="allcodex-url">Service URL</Label>
              <Input
                id="allcodex-url"
                type="url"
                placeholder="http://localhost:8080"
                value={url}
                onChange={(e) => setUrl(e.target.value)}
                disabled={loading}
                className="rounded-none bg-transparent border-x-0 border-t-0 border-b border-border/50 focus-visible:ring-0 px-0 h-9"
              />
            </div>

            {!isConnected && (
              <Tabs defaultValue="token" className="w-full">
                <TabsList className="grid w-full grid-cols-2 rounded-none">
                  <TabsTrigger value="token" className="rounded-none">
                    <Key className="h-3.5 w-3.5 mr-1.5" /> ETAPI Token
                  </TabsTrigger>
                  <TabsTrigger value="password" className="rounded-none">
                    <Lock className="h-3.5 w-3.5 mr-1.5" /> Password Login
                  </TabsTrigger>
                </TabsList>

                <TabsContent value="token" className="space-y-3 mt-3">
                  <div className="space-y-1.5">
                    <Label htmlFor="allcodex-token">ETAPI Token</Label>
                    <Input id="allcodex-token" type="password" placeholder="Trilium → Settings → ETAPI" value={token} onChange={(e) => setToken(e.target.value)} disabled={loading} className="rounded-none bg-transparent border-x-0 border-t-0 border-b border-border/50 focus-visible:ring-0 px-0 h-9" />
                  </div>
                  <Button className="w-full gap-2 rounded-none" onClick={handleConnectToken} disabled={loading || !url || !token}>
                    {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Link2 className="h-4 w-4" />}
                    Connect
                  </Button>
                </TabsContent>

                <TabsContent value="password" className="space-y-3 mt-3">
                  <div className="space-y-1.5">
                    <Label htmlFor="allcodex-password">Trilium Password</Label>
                    <Input id="allcodex-password" type="password" placeholder="Your Trilium login password" value={password} onChange={(e) => setPassword(e.target.value)} disabled={loading} className="rounded-none bg-transparent border-x-0 border-t-0 border-b border-border/50 focus-visible:ring-0 px-0 h-9" />
                  </div>
                  <Button className="w-full gap-2 rounded-none" onClick={handleLoginPassword} disabled={loading || !url || !password}>
                    {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Link2 className="h-4 w-4" />}
                    Login &amp; Connect
                  </Button>
                </TabsContent>
              </Tabs>
            )}

            {isConnected && (
              <Button variant="destructive" className="w-full gap-2 rounded-none" onClick={handleDisconnect} disabled={loading}>
                {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Unlink className="h-4 w-4" />}
                Disconnect
              </Button>
            )}
          </div>
        )}

        {error && (
          <p className="text-xs text-destructive rounded-none bg-destructive/10 border border-destructive/20 p-2">{error}</p>
        )}
      </div>
    </div>
  );
}

// ── AllKnower card ─────────────────────────────────────────────────────────────

type AkMode = "idle" | "login" | "register";

function AllKnowerCard({ initialStatus }: { initialStatus?: StatusPayload["allknower"] }) {
  const [state, setState] = useState<ConnState>(
    initialStatus?.ok ? "connected" : initialStatus?.configured ? "error" : "disconnected"
  );
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [url, setUrl] = useState(initialStatus?.url ?? "http://localhost:3001");
  const [mode, setMode] = useState<AkMode>("idle");
  const [email, setEmail] = useState("");
  const [name, setName] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const isConnected = state === "connected";

  function resetForm() { setEmail(""); setName(""); setPassword(""); setError(null); }
  function switchMode(next: AkMode) { resetForm(); setMode(next); }

  async function handleLogin() {
    if (!url || !email || !password) return;
    setLoading(true); setError(null);
    try {
      const res = await fetch("/api/auth/login", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ url, email, password }) });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setState("connected"); resetForm(); setMode("idle");
    } catch (e) { setState("error"); setError(String(e)); } finally { setLoading(false); }
  }

  async function handleRegister() {
    if (!url || !email || !name || !password) return;
    setLoading(true); setError(null);
    try {
      const res = await fetch("/api/auth/register", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ url, email, name, password }) });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setState("connected"); resetForm(); setMode("idle");
    } catch (e) { setState("error"); setError(String(e)); } finally { setLoading(false); }
  }

  async function handleDisconnect() {
    setLoading(true);
    await fetch("/api/config/disconnect?service=allknower", { method: "DELETE" });
    setState("disconnected"); resetForm(); setMode("idle"); setLoading(false);
  }

  return (
    <div className="rounded-none border border-border/30 border-l-2 border-l-[var(--accent)]/60 bg-card/40 overflow-hidden">
      <div className="px-5 py-4 border-b border-border/20 flex items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <Brain className="h-4 w-4 text-[var(--accent)]" />
          <div>
            <h3 className="text-sm font-semibold text-[var(--accent)]" style={{ fontFamily: "var(--font-cinzel)" }}>AllKnower</h3>
            <p className="text-[11px] text-muted-foreground">AI knowledge service</p>
          </div>
        </div>
        <StatusBadge state={state} />
      </div>

      <div className="px-5 py-4 space-y-4">
        {isConnected && (
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <CheckCircle2 className="h-4 w-4 text-emerald-500" />
            <span>Auto-provisioned session</span>
            {url && <span className="font-mono text-xs opacity-60">({url})</span>}
          </div>
        )}

        <button
          onClick={() => setShowAdvanced(!showAdvanced)}
          className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors"
        >
          {showAdvanced ? <ChevronDown className="h-3 w-3" /> : <ChevronRight className="h-3 w-3" />}
          <Settings2 className="h-3 w-3" />
          Advanced / Override
        </button>

        {showAdvanced && (
          <div className="space-y-4 border-t border-border/20 pt-4">
            <div className="space-y-1.5">
              <Label htmlFor="allknower-url">Service URL</Label>
              <Input id="allknower-url" type="url" placeholder="http://localhost:3001" value={url} onChange={(e) => setUrl(e.target.value)} disabled={isConnected || loading} className="rounded-none bg-transparent border-x-0 border-t-0 border-b border-border/50 focus-visible:ring-0 px-0 h-9" />
            </div>

            {!isConnected && mode === "idle" && (
              <div className="flex gap-2">
                <Button className="flex-1 gap-2 rounded-none" onClick={() => switchMode("login")} disabled={!url}>
                  <LogIn className="h-4 w-4" /> Login
                </Button>
                <Button variant="outline" className="flex-1 gap-2 rounded-none" onClick={() => switchMode("register")} disabled={!url}>
                  <UserPlus className="h-4 w-4" /> Register
                </Button>
              </div>
            )}

            {!isConnected && mode === "login" && (
              <div className="space-y-3">
                <div className="space-y-1.5">
                  <Label htmlFor="ak-login-email">Email</Label>
                  <Input id="ak-login-email" type="email" placeholder="you@example.com" value={email} onChange={(e) => setEmail(e.target.value)} disabled={loading} autoComplete="email" className="rounded-none bg-transparent border-x-0 border-t-0 border-b border-border/50 focus-visible:ring-0 px-0 h-9" />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="ak-login-password">Password</Label>
                  <Input id="ak-login-password" type="password" value={password} onChange={(e) => setPassword(e.target.value)} disabled={loading} autoComplete="current-password" className="rounded-none bg-transparent border-x-0 border-t-0 border-b border-border/50 focus-visible:ring-0 px-0 h-9" />
                </div>
                <div className="flex gap-2">
                  <Button className="flex-1 gap-2 rounded-none" onClick={handleLogin} disabled={loading || !url || !email || !password}>
                    {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : <LogIn className="h-4 w-4" />} Login
                  </Button>
                  <Button variant="ghost" className="gap-2 rounded-none" onClick={() => switchMode("idle")} disabled={loading}>Cancel</Button>
                </div>
              </div>
            )}

            {!isConnected && mode === "register" && (
              <div className="space-y-3">
                <div className="space-y-1.5">
                  <Label htmlFor="ak-reg-name">Name</Label>
                  <Input id="ak-reg-name" type="text" value={name} onChange={(e) => setName(e.target.value)} disabled={loading} autoComplete="name" className="rounded-none bg-transparent border-x-0 border-t-0 border-b border-border/50 focus-visible:ring-0 px-0 h-9" />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="ak-reg-email">Email</Label>
                  <Input id="ak-reg-email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} disabled={loading} autoComplete="email" className="rounded-none bg-transparent border-x-0 border-t-0 border-b border-border/50 focus-visible:ring-0 px-0 h-9" />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="ak-reg-password">Password</Label>
                  <Input id="ak-reg-password" type="password" value={password} onChange={(e) => setPassword(e.target.value)} disabled={loading} autoComplete="new-password" className="rounded-none bg-transparent border-x-0 border-t-0 border-b border-border/50 focus-visible:ring-0 px-0 h-9" />
                </div>
                <div className="flex gap-2">
                  <Button className="flex-1 gap-2 rounded-none" onClick={handleRegister} disabled={loading || !url || !email || !name || !password}>
                    {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : <UserPlus className="h-4 w-4" />} Register
                  </Button>
                  <Button variant="ghost" className="gap-2 rounded-none" onClick={() => switchMode("idle")} disabled={loading}>Cancel</Button>
                </div>
              </div>
            )}

            {isConnected && (
              <Button variant="destructive" className="w-full gap-2 rounded-none" onClick={handleDisconnect} disabled={loading}>
                {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Unlink className="h-4 w-4" />} Disconnect
              </Button>
            )}
          </div>
        )}

        {error && (
          <p className="text-xs text-destructive rounded-none bg-destructive/10 border border-destructive/20 p-2">{error}</p>
        )}
      </div>
    </div>
  );
}

// ── Share Config card ─────────────────────────────────────────────────────────

function ShareConfigCard() {
  const [noteId, setNoteId] = useState("");
  const [current, setCurrent] = useState<{ noteId: string; title: string; alias: string | null; url: string | null } | null>(null);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch("/api/share")
      .then((r) => r.json())
      .then((d) => { if (d.configured) setCurrent(d); })
      .catch(() => {});
  }, []);

  async function handleSave() {
    if (!noteId.trim()) return;
    setSaving(true); setError(null); setSaved(false);
    try {
      const res = await fetch("/api/share", { method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ noteId: noteId.trim() }) });
      if (!res.ok) throw new Error((await res.json()).error ?? "Save failed");
      const updated = await fetch("/api/share").then((r) => r.json());
      if (updated.configured) setCurrent(updated);
      setNoteId(""); setSaved(true); setTimeout(() => setSaved(false), 2000);
    } catch (e) { setError(String(e)); } finally { setSaving(false); }
  }

  return (
    <div className="rounded-none border border-border/30 border-l-2 border-l-primary/40 bg-card/40 overflow-hidden col-span-full">
      <div className="px-5 py-4 border-b border-border/20 flex items-center gap-3">
        <Globe className="h-4 w-4 text-primary" />
        <div>
          <h3 className="text-sm font-semibold text-primary" style={{ fontFamily: "var(--font-cinzel)" }}>Share Configuration</h3>
          <p className="text-[11px] text-muted-foreground">Configure which note is the public share root.</p>
        </div>
      </div>
      <div className="px-5 py-4 space-y-4">
        {current && (
          <div className="border-l-2 border-border/40 bg-muted/20 p-3 space-y-1">
            <p className="text-[10px] uppercase tracking-wider text-muted-foreground font-semibold">Current share root</p>
            <p className="text-sm font-medium">{current.title}</p>
            <p className="text-xs font-mono text-muted-foreground">{current.noteId}</p>
            {current.url && (
              <a href={current.url} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 text-xs text-primary/70 hover:text-primary transition-colors mt-1">
                <ExternalLink className="h-3 w-3" />{current.url}
              </a>
            )}
          </div>
        )}
        <div className="space-y-1.5">
          <Label htmlFor="share-root-id">Set Share Root Note ID</Label>
          <div className="flex gap-2">
            <Input id="share-root-id" placeholder="Enter a note ID" value={noteId} onChange={(e) => setNoteId(e.target.value)} className="font-mono text-sm" disabled={saving} />
            <Button onClick={handleSave} disabled={saving || !noteId.trim()} className="shrink-0 gap-2">
              {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : saved ? <CheckCircle2 className="h-4 w-4 text-green-400" /> : "Save"}
            </Button>
          </div>
        </div>
        {error && <p className="text-xs text-destructive rounded-none bg-destructive/10 border border-destructive/20 p-2">{error}</p>}
      </div>
    </div>
  );
}

function PortalConfigCard() {
  const [loreRootId, setLoreRootId] = useState("");
  const [saved, setSaved] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch("/api/config/portal").then((r) => r.json()).then((d) => setLoreRootId(d.loreRootNoteId ?? "")).catch(() => {});
  }, []);

  async function handleSave() {
    setLoading(true); setError(null); setSaved(false);
    try {
      const res = await fetch("/api/config/portal", { method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ loreRootNoteId: loreRootId }) });
      if (!res.ok) throw new Error((await res.json()).error);
      setSaved(true); setTimeout(() => setSaved(false), 2000);
    } catch (e) { setError(String(e)); } finally { setLoading(false); }
  }

  return (
    <div className="rounded-none border border-border/30 border-l-2 border-l-secondary/60 bg-card/40 overflow-hidden col-span-full">
      <div className="px-5 py-4 border-b border-border/20 flex items-center gap-3">
        <Scroll className="h-4 w-4 text-secondary-foreground" />
        <div>
          <h3 className="text-sm font-semibold" style={{ fontFamily: "var(--font-cinzel)" }}>Portal Configuration</h3>
          <p className="text-[11px] text-muted-foreground">Control how the Portal connects to your lore structure.</p>
        </div>
      </div>
      <div className="px-5 py-4 space-y-4">
        <div className="space-y-1.5">
          <Label htmlFor="lore-root-id">Lore Root Note ID</Label>
          <div className="flex gap-2">
            <Input id="lore-root-id" placeholder="root (default) or a specific note ID" value={loreRootId} onChange={(e) => setLoreRootId(e.target.value)} className="font-mono text-sm rounded-none bg-transparent border-x-0 border-t-0 border-b border-border/50 focus-visible:ring-0 px-0 h-9" disabled={loading} />
            <Button onClick={handleSave} disabled={loading} className="shrink-0 gap-2 rounded-none">
              {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : saved ? <CheckCircle2 className="h-4 w-4" /> : "Save"}
            </Button>
          </div>
        </div>
        {error && <p className="text-xs text-destructive rounded-none bg-destructive/10 border border-destructive/20 p-2">{error}</p>}
      </div>
    </div>
  );
}

function DevDebugCard() {
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function handleWipeDB() {
    if (!confirm("Are you sure you want to wipe ALL lore notes and the entire RAG database? This action cannot be undone.")) return;
    setLoading(true); setMessage(null);
    try {
      const res = await fetch("/api/config/wipe", { method: "POST" });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "Wipe failed");
      setMessage("Success: Database and Lore wiped.");
    } catch (e: any) { setMessage(`Error: ${e.message}`); } finally { setLoading(false); }
  }

  return (
    <div className="rounded-2xl border border-destructive/30 bg-card/80 p-6 shadow-lg shadow-destructive/5 relative overflow-hidden">
      <div className="absolute top-0 right-0 p-4 opacity-10"><Brain className="w-24 h-24 text-destructive" /></div>
      <div className="relative z-10 space-y-4">
        <div className="flex items-center gap-3">
          <div className="p-2 rounded-lg bg-destructive/10"><Brain className="h-5 w-5 text-destructive" /></div>
          <div>
            <h2 className="text-lg font-bold text-destructive" style={{ fontFamily: "var(--font-cinzel)" }}>Dev / Debug Options</h2>
            <p className="text-sm text-muted-foreground">Dangerous operations for development and debugging</p>
          </div>
        </div>
        <div className="pt-4 space-y-3">
          <Button variant="destructive" onClick={handleWipeDB} disabled={loading} className="w-full sm:w-auto">
            {loading ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : null}
            Wipe DB Lore & RAG
          </Button>
          {message && (
            <p className={`text-xs mt-2 p-2 rounded ${message.startsWith("Error") ? "bg-destructive/10 text-destructive border border-destructive/20" : "bg-emerald-500/10 text-emerald-400 border border-emerald-500/20"}`}>{message}</p>
          )}
        </div>
      </div>
    </div>
  );
}

// ── Page ───────────────────────────────────────────────────────────────────────

export default function SettingsPage() {
  const [status, setStatus] = useState<StatusPayload | null>(null);
  const [loading, setLoading] = useState(true);

  const fetchStatus = useCallback(async () => {
    setLoading(true);
    try {
      const data = await fetch("/api/config/status").then((r) => r.json());
      setStatus(data);
    } catch {} finally { setLoading(false); }
  }, []);

  useEffect(() => { fetchStatus(); }, [fetchStatus]);

  const bothConnected = status?.allcodex?.ok && status?.allknower?.ok;

  return (
    <div className="space-y-5 max-w-4xl">
      <div className="mb-8">
        <p className="text-[10px] uppercase tracking-[0.2em] text-muted-foreground mb-1" style={{ fontFamily: "var(--font-cinzel)" }}>System</p>
        <h1 className="text-2xl font-bold text-primary" style={{ fontFamily: "var(--font-cinzel)" }}>Service Connections</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          {bothConnected
            ? "All services connected and operational. Credentials were auto-provisioned."
            : "Configure AllCodex and AllKnower connections."}
        </p>
      </div>

      {loading ? (
        <div className="space-y-5">
          {[0, 1].map((i) => (
            <div key={i} className="h-32 border border-border/30 bg-card/20 animate-pulse" />
          ))}
        </div>
      ) : (
        <div className="space-y-5">
          <AllKnowerCard initialStatus={status?.allknower} />
          <AllCodexCard initialStatus={status?.allcodex} />
          <PortalConfigCard />
          <ShareConfigCard />
          <DevDebugCard />
        </div>
      )}
    </div>
  );
}
```

Notable changes from the original:
- Both connection cards default to showing just status + "Advanced / Override" disclosure
- When connected, shows "Auto-connected" / "Auto-provisioned" message
- AllKnower card moved above AllCodex (it bootstraps first)
- Removed env var hint section (no longer relevant)
- `AllCodexCard.handleConnectToken` now posts to correct endpoint `/api/integrations/allcodex/connect` (was broken `/api/config/connect`)
- Page subtitle changes based on connection state

- [ ] **Step 3: Update Portal .env.example**

Add/update in `.env.example` (or `.env.local` if no .env.example):

```bash
# Auto-provisioning — these are required for zero-login operation.
# In development, matching defaults are used automatically.
ALLKNOWER_URL=http://localhost:3001
PORTAL_INTERNAL_SECRET=dev-portal-secret-32chars!!!

# Legacy manual overrides — only needed if auto-provisioning is disabled.
# ALLCODEX_URL=http://localhost:8080
# ALLCODEX_ETAPI_TOKEN=
# ALLKNOWER_BEARER_TOKEN=
```

- [ ] **Step 4: Verify**

```bash
bun run check
```

- [ ] **Step 5: Test end-to-end**

With all three services running and proper env vars:

1. Clear all cookies in browser
2. Navigate to `http://localhost:3000`
3. Verify: no login screen, Portal loads directly
4. Check browser cookies: `allknower_url` and `allknower_token` should be set
5. Navigate to Settings: both cards should show "connected" / "auto-provisioned"
6. Try a brain dump: should work without any manual configuration

- [ ] **Step 6: Commit**

```bash
git add middleware.ts app/\(portal\)/settings/page.tsx
git commit -m "feat(portal): auto-provision middleware + settings status dashboard

middleware.ts: detects missing allknower_token cookie, calls AllKnower's
/internal/auto-provision to get a session, sets cookies transparently.
30s cooldown on failed attempts to avoid hammering AllKnower.

Settings page: connection cards default to status view with 'Advanced'
disclosure for manual override. Shows auto-provisioned state when active."
```

---

### Task C2: Update Portal Env Defaults

**Files:**
- Modify: `lib/get-creds.ts:55-75` (minor — ensure ALLKNOWER_URL default is consistent)

- [ ] **Step 1: Ensure getAkCreds uses ALLKNOWER_URL consistently**

In `lib/get-creds.ts`, the `getAkCreds` function currently falls through to env vars. Verify the dev fallback for `url` uses `ALLKNOWER_URL`:

```typescript
export async function getAkCreds(): Promise<AkCreds> {
    const jar = await cookies();
    const rawUrl = jar.get("allknower_url")?.value;
    const token = jar.get("allknower_token")?.value;

    if (process.env.NODE_ENV === "production" && !token) {
        return { url: "", token: "" };
    }

    let url = "";
    try {
        url = rawUrl ? validateAllKnowerUrl(rawUrl) : (process.env.ALLKNOWER_URL || "");
    } catch {
        return { url: "", token: "" };
    }

    return {
        url,
        token: token ?? process.env.ALLKNOWER_BEARER_TOKEN ?? "",
    };
}
```

This should already be correct from the v1 review fixes. Verify it matches. No change needed if it does.

- [ ] **Step 2: Verify PORTAL_INTERNAL_SECRET is accessible**

In `lib/get-creds.ts`, the `getEtapiCreds` function reads `process.env.PORTAL_INTERNAL_SECRET`. With the dev-default set in AllKnower and the env var set in Portal's `.env.local`, the auto-provisioned cookies will successfully resolve per-user credentials.

Run:
```bash
bun run check
```

- [ ] **Step 3: Commit (if any changes)**

Only commit if changes were needed. If `getAkCreds` was already correct, skip this commit.

---

## Environment Variable Summary

After implementation, the minimum env vars for zero-login operation:

### AllCodex Core

```bash
# Only needed for first boot — auto-sets the server password
ALLCODEX_BOOTSTRAP_PASSWORD=your-chosen-password
```

### AllKnower

```bash
DATABASE_URL=postgresql://...
BETTER_AUTH_SECRET=your-secret-min-16-chars
OPENROUTER_API_KEY=sk-or-...

# Auto-bootstrap: Core password to create ETAPI token
ALLCODEX_PASSWORD=your-chosen-password
ALLCODEX_URL=http://localhost:8080
ALLCODEX_ETAPI_TOKEN=will-be-auto-obtained

# Dev defaults apply automatically:
# PORTAL_INTERNAL_SECRET=dev-portal-secret-32chars!!!
# BETTER_AUTH_URL=http://localhost:3001
```

### Portal

```bash
ALLKNOWER_URL=http://localhost:3001
PORTAL_INTERNAL_SECRET=dev-portal-secret-32chars!!!
```

---

## Verification Plan

### Per-Service Verification

**Core:**
```bash
cd allcodex-core && pnpm typecheck
# Manual: start with ALLCODEX_BOOTSTRAP_PASSWORD, verify password auto-set
```

**AllKnower:**
```bash
cd allknower && bun typecheck && bun test test/ && bun test src/etapi/ && bun test src/routes/
# Manual: start with ALLCODEX_PASSWORD, verify bootstrap logs
# Verify: GET /health shows bootstrap.ok: true
```

**Portal:**
```bash
cd allcodex-portal && bun run check
# Manual: clear cookies, visit http://localhost:3000
# Verify: auto-provisioned, no login screen
```

### End-to-End Flow Test

1. Stop all services
2. Set env vars: `ALLCODEX_BOOTSTRAP_PASSWORD`, `ALLCODEX_PASSWORD`, `PORTAL_INTERNAL_SECRET`
3. Start Core → verify "Password auto-set" log
4. Start AllKnower → verify "Bootstrap complete" log (may retry until Core is ready)
5. Start Portal → verify dev server starts
6. Clear all cookies in browser
7. Navigate to `http://localhost:3000`
8. **Expected**: Portal loads immediately, no login, settings shows all green
9. Run a brain dump → should work without any manual configuration
10. Restart AllKnower → verify session cookie still works (persist across restarts)
11. Restart Portal → verify still works (cookies survive, middleware skips provision)

### Failure Mode Tests

1. Start Portal WITHOUT AllKnower running → middleware fails gracefully, settings page shows disconnected with manual override available
2. Start AllKnower WITHOUT Core running → bootstrap retries 6x, logs warnings, health shows `bootstrap.etapiReady: false`
3. Remove `allknower_token` cookie → next request auto-provisions new session
4. Set wrong `PORTAL_INTERNAL_SECRET` in Portal → auto-provision gets 403, falls through to manual flow
