#!/usr/bin/env bash
set -e

# prepare-tests.sh - Initialize the environment for E2E testing
# This script ensures dependencies are installed and test environment files are populated.

echo "🚀 Preparing AllCodex ecosystem for testing..."

# 1. Dependency Installation
echo "📦 Checking dependencies across all services..."

echo "--- [allcodex-core] ---"
if command -v pnpm &> /dev/null; then
  (cd allcodex-core && pnpm install)
else
  echo "⚠️  pnpm not found. Assuming dependencies are already installed."
fi

echo "--- [allknower] ---"
if command -v bun &> /dev/null; then
  (cd allknower && bun install && bun db:generate)
else
  echo "⚠️  bun not found. This is required for Knower."
fi

echo "--- [allcodex-portal] ---"
if command -v bun &> /dev/null; then
  (cd allcodex-portal && bun install)
else
  echo "⚠️  bun not found. This is required for Portal."
fi

# 2. Environment Configuration
echo "🔐 Configuring test environments..."

# Portal .env.test
if [ ! -f "allcodex-portal/.env.test" ]; then
    echo "Creating allcodex-portal/.env.test..."
    cat > allcodex-portal/.env.test <<EOF
# Needed for Phase 3 integration tests
TEST_OPENROUTER_API_KEY=
TEST_ALLKNOWER_URL=http://localhost:3001
# TEST_ALLKNOWER_BEARER_TOKEN is no longer required (auto-handled by globalSetup)
EOF
else
    echo "✅ allcodex-portal/.env.test already exists."
fi

# Knower .env.test (for model overrides)
if [ ! -f "allknower/.env.test" ]; then
    echo "Creating allknower/.env.test with cost-optimized test models..."
    # Copy base .env first to get DB/Auth secrets
    if [ -f "allknower/.env" ]; then
        cp allknower/.env allknower/.env.test
        # Append overrides
        cat >> allknower/.env.test <<EOF

# ── TEST ENV OVERRIDES ──────────────────────────────────
NODE_ENV=test
BRAIN_DUMP_MODEL=qwen/qwen3.5-flash
CONSISTENCY_MODEL=qwen/qwen3.5-flash
SUGGEST_MODEL=deepseek/deepseek-v4-flash
GAP_DETECT_MODEL=qwen/qwen3.5-flash
AUTOCOMPLETE_MODEL=deepseek/deepseek-v4-flash
RERANK_MODEL=deepseek/deepseek-v4-flash
EMBEDDING_CLOUD=qwen/qwen3-embedding-8b
EOF
    else
        echo "⚠️  allknower/.env missing! Cannot create a complete .env.test."
    fi
else
    echo "✅ allknower/.env.test already exists."
fi

# 3. Service Verification
echo "🔍 Checking backend availability..."
nc -z localhost 8080 && echo "✅ AllCodex Core (8080) is UP" || echo "❌ AllCodex Core (8080) is DOWN"
nc -z localhost 3001 && echo "✅ AllKnower (3001) is UP" || echo "❌ AllKnower (3001) is DOWN"

echo ""
echo "✨ Preparation complete!"
echo "Next steps:"
echo "1. Ensure Core and Knower are running (use 'scripts/dev.sh' or manual start)."
echo "2. If running Knower for integration tests, you may want to use the test env:"
echo "   cd allknower && bun run dev --env-file=.env.test"
echo "3. Run the tests:"
echo "   cd allcodex-portal && bun run test:e2e"
