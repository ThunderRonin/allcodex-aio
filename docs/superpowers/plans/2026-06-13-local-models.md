# Local Model Integration (Ollama & LM Studio)

Add support for local LLM and embedding models (Ollama, LM Studio, vLLM) in AllKnower. This allows self-hosters to run AllCodex entirely offline or mix local models with cloud models (e.g., local autocomplete and embeddings, cloud brain dumps).

This change modifies the centralized model router, guaranteeing that **all** pipelines involving LLMs (Brain Dump, Article Copilot, Consistency Scan, Suggest Relations, Autocomplete, Gap Detection, and Context/Session Compaction) will support local models.

## User Review Required

> [!NOTE]
> The integration supports **hybrid chains**: a task can have a local model as the primary, and fallback to OpenRouter cloud models (or vice-versa).
>
> **Example Configuration:**
> - `BRAIN_DUMP_MODEL=ollama/llama3` (primary: local)
> - `BRAIN_DUMP_FALLBACK_1=deepseek/deepseek-v4-pro` (fallback: cloud)

> [!WARNING]
> Local models (Ollama/LM Studio) do not support OpenRouter-specific API fields such as `models` (fallback array), `plugins` (response-healing), or `provider` options. These fields will be stripped dynamically by the router when dispatching to a local client.

## Open Questions

- **Model Names**: We propose prefixing local models with `ollama/` or `local/` (e.g., `ollama/llama3:8b` or `local/gemma2`). The prefix will be stripped before sending the model name to the local API. Is this acceptable?
- **Embedding Dimensions**: Local embedding models (like `nomic-embed-text`) output 768 or 1024 dimensions. Switching to a local embedding model will require dropping the LanceDB table and running a full reindex (`POST /rag/reindex`). We will document this.

## Proposed Changes

---

### AllKnower (AI Orchestrator)

#### [MODIFY] [env.ts](file:///Users/allmaker/projects/allcodex-aio/allknower/src/env.ts)
Add configuration for local providers:
- `LOCAL_PROVIDER_BASE_URL` (default: `"http://localhost:11434/v1"` to target local Ollama OpenAI-compatible endpoint).
- `LOCAL_PROVIDER_API_KEY` (default: `"ollama"`).

```typescript
// Add to envSchema in allknower/src/env.ts:
LOCAL_PROVIDER_BASE_URL: z.string().default("http://localhost:11434/v1"),
LOCAL_PROVIDER_API_KEY: z.string().default("ollama"),
```

#### [MODIFY] [model-router.ts](file:///Users/allmaker/projects/allcodex-aio/allknower/src/pipeline/model-router.ts)
1. Initialize a secondary OpenAI client pointing to the local provider:
```typescript
import OpenAI from "openai";

const localClient = new OpenAI({
    baseURL: env.LOCAL_PROVIDER_BASE_URL,
    apiKey: env.LOCAL_PROVIDER_API_KEY,
});
```
2. Modify `callWithFallback` and `callModelStream` to detect if the selected model starts with `ollama/` or `local/`:
```typescript
const isLocal = model.startsWith("ollama/") || model.startsWith("local/");
const cleanModel = isLocal ? model.replace(/^(ollama\/|local\/)/, "") : model;
```
3. If `isLocal` is true:
   - Call `localClient` instead of `openrouter`.
   - Strip OpenRouter-specific parameters: `models` fallback array, `plugins`, `provider`, and `trace`.
   - Execute the call. If it fails, fall back to the next model in the chain (handles local-to-cloud failover).
   - This ensures **all** 8 LLM-based pipelines (`brain-dump`, `article-copilot`, `consistency`, `suggest`, `gap-detect`, `autocomplete`, `compact`, and `session-compact`) inherit local model compatibility automatically.

#### [MODIFY] [embedder.ts](file:///Users/allmaker/projects/allcodex-aio/allknower/src/rag/embedder.ts)
1. Initialize local embeddings client:
```typescript
const localClient = new OpenAI({
    baseURL: env.LOCAL_PROVIDER_BASE_URL,
    apiKey: env.LOCAL_PROVIDER_API_KEY,
});
```
2. In `embedBatch`, select client based on `EMBEDDING_CLOUD` prefix:
```typescript
const isLocal = EMBEDDING_CLOUD.startsWith("ollama/") || EMBEDDING_CLOUD.startsWith("local/");
const cleanModel = isLocal ? EMBEDDING_CLOUD.replace(/^(ollama\/|local\/)/, "") : EMBEDDING_CLOUD;
const client = isLocal ? localClient : openrouterClient;

const response = await client.embeddings.create({
    model: cleanModel,
    input: texts,
});
```

---

### Bookkeeping & Documentation

#### [MODIFY] [ROADMAP.md](file:///Users/allmaker/projects/allcodex-aio/docs/shared/planning/ROADMAP.md)
Update the roadmap to add local model integration as a completed feature.

#### [MODIFY] [allknower/README.md](file:///Users/allmaker/projects/allcodex-aio/allknower/README.md)
Document the new environment variables (`LOCAL_PROVIDER_BASE_URL` and `LOCAL_PROVIDER_API_KEY`) and detail how to configure local models using the `ollama/` and `local/` prefixes.

---

## Verification Plan

### Automated Tests
Run model router tests with mock local endpoints:
```bash
cd allknower
bun test src/pipeline/model-router.test.ts
bun test src/rag/lancedb.integration.test.ts
```

### Manual Verification
1. Run a local Ollama instance with `llama3` and `nomic-embed-text`.
2. Configure `.env` in `allknower`:
   ```env
   BRAIN_DUMP_MODEL=ollama/llama3
   EMBEDDING_CLOUD=ollama/nomic-embed-text
   EMBEDDING_DIMENSIONS=768
   ```
3. Run `POST /rag/reindex` to re-initialize LanceDB with 768-dim table.
4. Execute a Brain Dump query from the Portal and verify local logs show generation/embeddings routing correctly to localhost:11434.
