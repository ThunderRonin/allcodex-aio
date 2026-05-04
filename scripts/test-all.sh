#!/usr/bin/env bash

# test-all.sh - Full stack orchestration and test runner for AllCodex
# Usage: ./scripts/test-all.sh [--prep] [playwright-args...]

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Ensure logs directory exists
mkdir -p logs

# NVM helpers — detect nvm.sh location
NVM_SH=""
if [ -f "$HOME/.nvm/nvm.sh" ]; then
    NVM_SH="$HOME/.nvm/nvm.sh"
elif command -v brew &>/dev/null && [ -f "$(brew --prefix nvm)/nvm.sh" ]; then
    NVM_SH="$(brew --prefix nvm)/nvm.sh"
fi

if [ -n "$NVM_SH" ]; then
    source "$NVM_SH"
    echo -e "${YELLOW}Initialising NVM...${NC}"
    if nvm use &>/dev/null; then
        echo -e "${GREEN}✅ Switched to Node $(node -v) via NVM${NC}"
    else
        echo -e "${YELLOW}No .nvmrc found in $(pwd); using current Node $(node -v)${NC}"
    fi
fi


# Cleanup function to kill background processes on exit
cleanup() {
  echo -e "\n${YELLOW}Stopping background services...${NC}"
  if [ ! -z "$CORE_PID" ]; then
    echo "Killing Core (PID $CORE_PID)..."
    kill $CORE_PID 2>/dev/null || true
  fi
  if [ ! -z "$KNOWER_PID" ]; then
    echo "Killing Knower (PID $KNOWER_PID)..."
    kill $KNOWER_PID 2>/dev/null || true
  fi
  exit ${EXIT_CODE:-0}
}

# Trap signals for cleanup
trap cleanup SIGINT SIGTERM EXIT

# 1. Preparation (optional)
if [[ "$1" == "--prep" ]]; then
  echo -e "${YELLOW}Running preparation...${NC}"
  ./scripts/prepare-tests.sh
  shift # remove --prep from args
fi

# 2. Start/Verify Core
if nc -z localhost 8080; then
  echo -e "${GREEN}✅ AllCodex Core is already running on 8080.${NC}"
else
  echo -e "${YELLOW}Starting AllCodex Core in background...${NC}"
  # Source nvm inside the subshell so the .nvmrc (Node 22) is respected
  if [ -n "$NVM_SH" ]; then
    (cd allcodex-core && source "$NVM_SH" && nvm use > /dev/null 2>&1 && pnpm server:start > ../logs/core-test.log 2>&1) &
  else
    (cd allcodex-core && pnpm server:start > ../logs/core-test.log 2>&1) &
  fi
  CORE_PID=$!
fi

# 3. Start/Verify Knower
if nc -z localhost 3001; then
  echo -e "${GREEN}✅ AllKnower is already running on 3001.${NC}"
  echo -e "${YELLOW}Note: Running integration tests against an already-running Knower will use its current environment (not necessarily test models).${NC}"
else
  echo -e "${YELLOW}Starting AllKnower (test mode) in background...${NC}"
  if [ -f "allknower/.env.test" ]; then
    (cd allknower && bun --env-file=.env.test dev > ../logs/knower-test.log 2>&1) &
  else
    (cd allknower && bun dev > ../logs/knower-test.log 2>&1) &
  fi
  KNOWER_PID=$!
fi

# 4. Wait for readiness
echo -en "${YELLOW}Waiting for services to stabilize...${NC}"
for i in {1..30}; do
  if nc -z localhost 8080 && nc -z localhost 3001; then
    echo -e "\n${GREEN}🚀 Services are ready!${NC}"
    break
  fi
  echo -n "."
  sleep 1
  if [ $i -eq 30 ]; then
    echo -e "\n${RED}❌ Timeout waiting for services.${NC}"
    exit 1
  fi
done

# 5. Run Playwright
echo -e "${YELLOW}Running Playwright tests...${NC}"
cd allcodex-portal
# Pass all remaining arguments to playwright
bun run test:e2e "${@}"
EXIT_CODE=$?
cd ..

# Final cleanup via trap EXIT
