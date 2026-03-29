# Plan: Migrate AllCodex Portal → SvelteKit + MDsveX

Rewrite allcodex-portal from Next.js 16 / React 19 to **SvelteKit 2 / Svelte 5** with **MDsveX** for wiki/markdown features, preserving all 11 pages, 17 API endpoints, the Grimoire dark theme, and all AllCodex + AllKnower integrations.

---

## Dependency Mapping

| Current (Next.js/React) | SvelteKit Equivalent |
|---|---|
| `next` | `@sveltejs/kit` + `vite` |
| `react` / `react-dom` | `svelte` |
| `@tanstack/react-query` | `@tanstack/svelte-query` |
| `radix-ui` | `bits-ui` (via shadcn-svelte) |
| `shadcn` (React) | `shadcn-svelte` |
| `lucide-react` | `lucide-svelte` |
| `vaul` | `vaul-svelte` |
| `next-themes` | Not needed (always dark) |
| `zustand` | Dropped — never actually used |
| `babel-plugin-react-compiler` | Not needed (Svelte compiles natively) |
| `clsx` + `tailwind-merge` | Same — kept as-is |
| `class-variance-authority` | Same — kept as-is |
| — (new) | `mdsvex` + `remark-gfm` + `rehype-slug` + `rehype-autolink-headings` + `shiki` |
| `next/font/google` | `@fontsource/cinzel` + `@fontsource/crimson-text` |

---

## Current Inventory

### Pages (11)

- `/` — Dashboard (stats, recent entries, AI tools quicklinks)
- `/settings` — Connection config (AllCodex + AllKnower)
- `/search` — Dual-mode search (RAG + ETAPI)
- `/brain-dump` — Freeform text → AI processing + history
- `/lore` — Lore browser with type filter + grid
- `/lore/new` — Create lore entry
- `/lore/[id]` — View lore entry (HTML content, labels, relations)
- `/lore/[id]/edit` — Edit lore entry
- `/ai/relationships` — AI relationship suggestions
- `/ai/consistency` — AI consistency check
- `/ai/gaps` — AI gap detector

### API Endpoints (17)

- Lore CRUD: GET/POST `/api/lore`, GET/PATCH/DELETE `/api/lore/[id]`, GET/PUT `/api/lore/[id]/content`
- Search: GET `/api/search`
- RAG: GET/POST `/api/rag`
- Brain Dump: POST `/api/brain-dump`, GET `/api/brain-dump/history`
- AI: POST `/api/ai/relationships`, POST `/api/ai/consistency`, GET `/api/ai/gaps`
- Config: POST `/api/config/connect`, DELETE `/api/config/disconnect`, GET `/api/config/status`, POST `/api/config/allcodex-login`, POST `/api/config/allknower-login`, POST `/api/config/allknower-register`
- Auth: POST `/api/auth/sync`

### Server-Side Libs (4 files)

- `lib/etapi-server.ts` — Trilium ETAPI client (searchNotes, getNote, createNote, etc.)
- `lib/allknower-server.ts` — AllKnower API client (brainDump, RAG, consistency, etc.)
- `lib/get-creds.ts` — Cookie/env credential reader
- `lib/route-error.ts` — ServiceError class + handler

### UI Components

- 18 shadcn/ui components: badge, button, card, dialog, drawer, dropdown-menu, input, label, navigation-menu, scroll-area, select, separator, sheet, sidebar, skeleton, tabs, textarea, tooltip
- 2 custom portal components: AppSidebar, ServiceBanner
- 1 hook: useIsMobile
- 1 utility: cn() (clsx + tailwind-merge)

### Theme

- Always-dark "Grimoire" theme (oklch colors)
- Google Fonts: Cinzel (headings) + Crimson Text (body)
- Custom `.lore-content` prose styles
- `.grimoire-divider` ornamental divider
- Custom scrollbar styles

---

## Steps

### Phase 1: Project Scaffold & Core Config

1. **Initialize SvelteKit** — `npx sv create` with Svelte 5, TypeScript strict, Tailwind v4, skeleton template
2. **Install deps** — shadcn-svelte (`pnpm dlx shadcn-svelte@next init`), `@tanstack/svelte-query`, `vaul-svelte`, `@fontsource/*`, `mdsvex`, remark/rehype plugins
3. **Configure MDsveX** in `svelte.config.js` — preprocessor with `.svx`/`.md` extensions, custom wiki layout, remark-gfm, rehype-slug, rehype-autolink-headings, shiki highlighting
4. **Port theme** — copy `globals.css` → `src/app.css`, keep all oklch color vars, `.lore-content` prose, `.grimoire-divider`, scrollbar styles; replace shadcn React CSS import with shadcn-svelte equivalent
5. **Configure `app.html`** — `<html lang="en" class="dark">`, `<meta name="color-scheme" content="dark">`, font classes on body
6. **Path aliases + env** — `$lib`, `$env/static/private`, `PUBLIC_ALLCODEX_URL`

### Phase 2: Server-Side Libs (no UI — pure TypeScript, mostly copy-paste)

7. **Port `route-error.ts`** → `src/lib/server/route-error.ts` — change `NextResponse.json()` → SvelteKit `json()` *(depends on 1)*
8. **Port `get-creds.ts`** → `src/lib/server/get-creds.ts` — change `cookies()` from `next/headers` to accept `cookies: Cookies` param from `RequestEvent`; use `$env/dynamic/private` for fallbacks *(depends on 1)*
9. **Port `etapi-server.ts`** → `src/lib/server/etapi-server.ts` — copy as-is, pure `fetch()` *(parallel with 7-8)*
10. **Port `allknower-server.ts`** → `src/lib/server/allknower-server.ts` — copy as-is *(parallel with 7-8)*
11. **Port `utils.ts`** → `src/lib/utils.ts` — `cn()` function, identical *(parallel with 7-8)*

### Phase 3: API Route Migration (17 routes)

Translation pattern: `NextResponse.json()` → SvelteKit `json()`; `cookies()` → `event.cookies`; `params.id` → `event.params.id`. No logic changes.

12. **Lore CRUD** (6 endpoints) → `src/routes/api/lore/+server.ts`, `[id]/+server.ts`, `[id]/content/+server.ts` *(depends on 7-10)*
13. **Search + RAG** (3 endpoints) → `src/routes/api/search/+server.ts`, `api/rag/+server.ts` *(parallel with 12)*
14. **Brain Dump** (2 endpoints) → `src/routes/api/brain-dump/+server.ts`, `history/+server.ts` *(parallel with 12)*
15. **AI routes** (3 endpoints) → `src/routes/api/ai/relationships/+server.ts`, `consistency/+server.ts`, `gaps/+server.ts` *(parallel with 12)*
16. **Config/Auth** (6 endpoints) → `src/routes/api/config/*/+server.ts`, `api/auth/sync/+server.ts` *(parallel with 12)*

### Phase 4: UI Component Migration

17. **Add all 18 shadcn-svelte components** — `pnpm dlx shadcn-svelte@next add badge button card dialog drawer dropdown-menu input label navigation-menu scroll-area select separator sheet sidebar skeleton tabs textarea tooltip` *(depends on 2)*
18. **Port `AppSidebar`** → `src/lib/components/portal/AppSidebar.svelte` — `usePathname()` → `$page.url.pathname`, `<Link>` → `<a>`, lucide-react → lucide-svelte, same nav groups *(depends on 17)*
19. **Port `ServiceBanner`** → `src/lib/components/portal/ServiceBanner.svelte` — React conditionals → Svelte `{#if}` blocks *(depends on 17)*

### Phase 5: Layout & Page Migration (11 pages)

20. **Root layout** (`src/routes/+layout.svelte`) — import fonts, app.css, wrap in QueryClientProvider *(depends on 4, 17)*
21. **Portal group layout** (`src/routes/(portal)/+layout.svelte`) — SidebarProvider + AppSidebar + header *(depends on 18, 20)*
22. **Dashboard** (`/`) — 3 stat cards, recent entries, AI tools panel. `useQuery` → `createQuery` *(depends on 21)*
23. **Settings** (`/settings`) — state machine with `$state`/`$effect` runes replacing `useState`/`useEffect` *(depends on 21)*
24. **Search** (`/search`) — `$page.url.searchParams`, `goto()` for URL updates, tabs *(depends on 21)*
25. **Brain Dump** (`/brain-dump`) — textarea, `createMutation`, collapsible history *(depends on 21)*
26. **Lore Browser** (`/lore`) — filter dropdown, reactive query, grid *(depends on 21)*
27. **Lore Detail** (`/lore/[id]`) — fetch note + content, `{@html content}`, breadcrumb, labels, relations *(depends on 21)*
28. **Lore Edit** (`/lore/[id]/edit`) — form, parallel save mutations, delete confirm *(depends on 21)*
29. **Lore New** (`/lore/new`) — create form, POST → navigate *(depends on 21)*
30. **AI Relationships** (`/ai/relationships`) — pre-fill from `?noteId`, mutation, colored badges *(depends on 21)*
31. **AI Consistency** (`/ai/consistency`) — note IDs input, severity grouping *(parallel with 30)*
32. **AI Gaps** (`/ai/gaps`) — lazy-triggered query, severity summary *(parallel with 30)*

### Phase 6: MDsveX Wiki Integration (NEW)

33. **Wiki layout component** — `src/lib/components/wiki/WikiLayout.svelte` wrapping content in `.lore-content` with optional ToC extracted from headings, frontmatter metadata display *(depends on 3)*
34. **Custom MDsveX component map** — styled `h1`-`h6` with anchors + Cinzel font, smart `<a>` with internal link detection → `/lore/` or `/wiki/`, grimoire-styled `<blockquote>`, responsive `<table>`, syntax-highlighted `<code>`, lazy `<img>` with captions *(depends on 33)*
35. **Wiki routes** — `src/routes/(portal)/wiki/+page.svelte` (index listing all wiki pages via `import.meta.glob`), `src/routes/(portal)/wiki/[...slug]/+page.svelte` (catch-all renderer that loads `.svx` files from `src/content/wiki/`) *(depends on 33)*
36. **Add "Wiki" nav entry** to AppSidebar under Chronicle group *(depends on 18, 35)*
37. **Lore view MDsveX** — for `/lore/[id]`, keep `{@html}` for Trilium HTML content; optionally add `unified` (`remark-parse` → `remark-rehype` → `rehype-stringify`) pipeline for markdown content if encountered *(depends on 27)*

### Phase 7: Build, Deploy & Cleanup

38. **Adapter** — install `@sveltejs/adapter-node`, configure in `svelte.config.js` *(depends on 1)*
39. **Update `package.json` scripts** — `"dev": "vite dev"`, `"build": "vite build"`, `"preview": "vite preview"`, `"check": "svelte-kit sync && svelte-check"` *(parallel with 38)*
40. **Update Dockerfile** — `vite build` → `node build/index.js` *(depends on 38)*
41. **Remove old portal**, rename new to `allcodex-portal` *(depends on all above)*

---

## Relevant Files

### Source (current portal) → Target (new SvelteKit)

- `app/layout.tsx` → `src/routes/+layout.svelte` — root layout, fonts, providers
- `app/(portal)/layout.tsx` → `src/routes/(portal)/+layout.svelte` — sidebar shell
- `app/globals.css` → `src/app.css` — Grimoire theme, all oklch vars, `.lore-content`
- `components/providers.tsx` → merged into `+layout.svelte`
- `components/portal/AppSidebar.tsx` → `src/lib/components/portal/AppSidebar.svelte`
- `components/portal/ServiceBanner.tsx` → `src/lib/components/portal/ServiceBanner.svelte`
- `hooks/use-mobile.ts` → shadcn-svelte's built-in (or `src/lib/stores/mobile.svelte.ts`)
- `lib/utils.ts` → `src/lib/utils.ts` (copy as-is)
- `lib/route-error.ts` → `src/lib/server/route-error.ts` — `NextResponse` → `json()`
- `lib/get-creds.ts` → `src/lib/server/get-creds.ts` — cookies param injection
- `lib/etapi-server.ts` → `src/lib/server/etapi-server.ts` (copy as-is)
- `lib/allknower-server.ts` → `src/lib/server/allknower-server.ts` (copy as-is)
- All 17 `route.ts` files → corresponding `+server.ts` files
- All 11 `page.tsx` files → corresponding `+page.svelte` files

### New files (MDsveX / wiki)

- `src/lib/components/wiki/WikiLayout.svelte` — MDsveX layout wrapper
- `src/routes/(portal)/wiki/+page.svelte` — wiki index
- `src/routes/(portal)/wiki/[...slug]/+page.svelte` — wiki page renderer
- `src/content/wiki/` — static .svx wiki pages

---

## Verification

1. `pnpm build` succeeds with zero errors
2. `pnpm check` (svelte-check) passes all type checks
3. Navigate all 11 pages — verify layout, data loading, correct rendering
4. `curl` all 17 API endpoints — verify same request/response JSON shapes as current
5. Full cookie auth flow: connect AllCodex + AllKnower in `/settings` → verify cookies persist → verify API calls authenticate
6. Lore CRUD cycle: create → view → edit → delete an entry
7. Search both modes: RAG semantic + ETAPI attribute search
8. Brain dump end-to-end: submit text → see response + verify history entry appears
9. All 3 AI tools: relationships, consistency, gaps — verify results render with proper styling
10. MDsveX wiki: create a `.svx` file with frontmatter + GFM content → verify headings get anchors, tables render, code highlights
11. Theme integrity: compare screenshots — all oklch colors, Cinzel/Crimson fonts, scrollbar, `.grimoire-divider` match original
12. Mobile: verify sidebar collapses, grid goes single-column

---

## Decisions

- **Zustand** — dropped (listed as dep but never imported/used in any component)
- **TanStack Query** — keeping via `@tanstack/svelte-query` for cache parity (staleTime 30s, retry 1) rather than pure SvelteKit `load` — matches current all-client-rendered architecture
- **Theme** — keeping always-dark, no toggle
- **MDsveX scope** — compile-time for static wiki `.svx` files; `{@html}` for runtime AllCodex HTML content; optional `unified` pipeline for runtime markdown if needed later
- **Adapter** — `@sveltejs/adapter-node` for self-hosted deployment (matching current Next.js standalone)
- **ROADMAP features** in progress (promoted attributes, Azgaar import, etc.) — will port to new Svelte patterns if they land before migration completes

---

## Further Considerations

1. **SSR opportunity** — Currently ALL pages are client-rendered. SvelteKit makes SSR trivial with `+page.server.ts`. Could convert dashboard + lore browser to SSR for faster first paint. **Recommendation**: keep client-side first for 1:1 parity, convert in a follow-up.

2. **shadcn-svelte sidebar maturity** — shadcn-svelte's sidebar component may have API differences from the React version. Need to verify during implementation and adapt `AppSidebar` accordingly.

3. **MDsveX dynamic content** — MDsveX is compile-time only. For dynamic wiki content (user-authored, stored in AllCodex), runtime rendering needs either `{@html}` (current) or a `unified` pipeline. **Options**: (A) `{@html}` for HTML content as-is (current approach), (B) `unified` pipeline for runtime markdown→HTML, (C) `mdsvex.compile()` for runtime svex compilation. **Recommendation**: A for HTML, B for markdown content if AllCodex ever outputs markdown.
