#!/usr/bin/env bash

# deploy.sh - Production/Build launcher using Tmux
# This builds and starts allcodex-core, allknower, and allcodex-portal in a split-pane tmux session sequentially.

SESSION_NAME="allcodex-prod"

# Check if tmux is installed
if ! command -v tmux &> /dev/null; then
    echo -e "\033[0;31mTmux is not installed.\033[0m"
    echo "Please install tmux (e.g. 'brew install tmux') to use the deploy script."
    exit 1
fi

echo "Spinning up sequentially staggered production builds in tmux session '$SESSION_NAME'..."

# Check if session already exists
if tmux has-session -t $SESSION_NAME 2>/dev/null; then
    echo "Session $SESSION_NAME already exists. Attaching..."
    tmux attach-session -t $SESSION_NAME
    exit 0
fi

# Create new detached session with the first window named "Ecosystem"
tmux new-session -d -s $SESSION_NAME -n "Ecosystem"

# Pane 0 (Left side): allcodex-core (First)
tmux send-keys -t $SESSION_NAME:0.0 "echo 'Building and starting Core...' && cd allcodex-core && pnpm server:build && pnpm server:start-prod" C-m

# Split horizontally (create Pane 1 on the Right)
tmux split-window -h -t $SESSION_NAME:0.0

# Pane 1 (Right-Top): allknower (Second)
tmux send-keys -t $SESSION_NAME:0.1 "echo 'Waiting for Core (8080) before building AI...' && while ! curl -s http://127.0.0.1:8080 >/dev/null; do sleep 1; done && echo 'Core is up!' && cd allknower && bun run build && bun run start" C-m

# Split Pane 1 vertically (create Pane 2 on the Right-Bottom)
tmux split-window -v -t $SESSION_NAME:0.1

# Pane 2 (Right-Bottom): allcodex-portal (Third)
tmux send-keys -t $SESSION_NAME:0.2 "echo 'Waiting for Knower (3001) before building Portal...' && while ! curl -s http://127.0.0.1:3001 >/dev/null; do sleep 1; done && echo 'Knower is up!' && cd allcodex-portal && bun run build && bun run start" C-m

# Resize layout cleanly (Core gets 50% left, the other two split the right side)
tmux select-layout -t $SESSION_NAME:0 main-vertical

echo "Layout constructed. Entering tmux session..."
echo "To detach and leave them running in the background, press 'Ctrl+b' then 'd'."
echo "To completely kill the ecosystem, type 'tmux kill-session -t $SESSION_NAME'"
sleep 2

# Finally, attach to the running session
tmux attach-session -t $SESSION_NAME
