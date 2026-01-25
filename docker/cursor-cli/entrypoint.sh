#!/bin/bash
set -e

# =============================================================================
# Cursor CLI Container Entrypoint
#
# Starts:
#   - ttyd (web terminal) on port 7681
#   - File watcher service on port 4040
#   - Interactive bash shell (or custom command)
#
# Cursor Auth:
#   Uses interactive login via web browser or API key
# =============================================================================

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
TTYD_PORT="${TTYD_PORT:-7681}"
WATCHER_PORT="${WATCHER_PORT:-4040}"
WORKSPACE="${WORKSPACE:-/workspace}"

# Set HOME for Cursor
export HOME="/home/cursor"

# Add cursor CLI to PATH
export PATH="$HOME/.local/bin:$PATH"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Cursor CLI Interactive Session${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# -----------------------------------------------------------------------------
# Setup workspace
# -----------------------------------------------------------------------------
mkdir -p "$WORKSPACE/repo" "$WORKSPACE/output"

# Clone repo if URL provided
if [ -n "$REPO_URL" ]; then
    echo -e "${GREEN}📦 Cloning repository...${NC}"
    if [ -n "$REPO_BRANCH" ]; then
        git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$WORKSPACE/repo" 2>/dev/null || {
            echo -e "${YELLOW}⚠️  Failed to clone repo: $REPO_URL (branch: $REPO_BRANCH)${NC}"
        }
    else
        git clone --depth 1 "$REPO_URL" "$WORKSPACE/repo" 2>/dev/null || {
            echo -e "${YELLOW}⚠️  Failed to clone repo: $REPO_URL${NC}"
        }
    fi
fi

# -----------------------------------------------------------------------------
# Start File Watcher Service
# -----------------------------------------------------------------------------
echo -e "${CYAN}🔍 Starting file watcher on port ${WATCHER_PORT}...${NC}"
cd /opt/watcher
WATCH_DIR="$WORKSPACE" WATCHER_PORT="$WATCHER_PORT" node index.js &
WATCHER_PID=$!
cd "$WORKSPACE"

# Wait for watcher to be ready
sleep 1
if kill -0 $WATCHER_PID 2>/dev/null; then
    echo -e "${GREEN}✅ File watcher started (PID: $WATCHER_PID)${NC}"
else
    echo -e "${YELLOW}⚠️  File watcher failed to start${NC}"
fi

# -----------------------------------------------------------------------------
# Start ttyd Web Terminal
# -----------------------------------------------------------------------------
echo -e "${CYAN}🖥️  Starting web terminal on port ${TTYD_PORT}...${NC}"

# Default command is agent (cursor CLI), can be overridden with TTYD_CMD env var
TTYD_CMD="${TTYD_CMD:-agent}"

# For auth commands (like 'agent login'), keep session alive briefly after completion
# This gives time for credentials to be collected before container stops
if [[ "$TTYD_CMD" == *"login"* ]]; then
    TTYD_SHELL="$TTYD_CMD; echo -e '\\n\\033[0;32m✅ Authentication complete. Session will close shortly...\\033[0m\\n'; sleep 30"
else
    TTYD_SHELL="$TTYD_CMD"
fi

# Start ttyd with specified command
if [ -n "$TTYD_CREDENTIAL" ]; then
    ttyd -W -c "$TTYD_CREDENTIAL" -p "$TTYD_PORT" bash -c "$TTYD_SHELL" &
else
    ttyd -W -p "$TTYD_PORT" bash -c "$TTYD_SHELL" &
fi
TTYD_PID=$!

sleep 1
if kill -0 $TTYD_PID 2>/dev/null; then
    echo -e "${GREEN}✅ Web terminal started (PID: $TTYD_PID)${NC}"
else
    echo -e "${YELLOW}⚠️  Web terminal failed to start${NC}"
fi

# -----------------------------------------------------------------------------
# Show info
# -----------------------------------------------------------------------------
echo ""
echo -e "${BLUE}───────────────────────────────────────────────────────────────${NC}"
echo -e "  ${BLUE}Services:${NC}"
echo -e "    Web Terminal:  http://localhost:${TTYD_PORT}"
echo -e "    File Watcher:  ws://localhost:${WATCHER_PORT}"
echo -e "    File Tree:     http://localhost:${WATCHER_PORT}/tree"
echo ""
echo -e "  ${BLUE}Workspace:${NC}"
echo -e "    repo:    $WORKSPACE/repo"
echo -e "    output:  $WORKSPACE/output"
echo ""
echo -e "  ${BLUE}Commands:${NC}"
echo -e "    agent    - Start Cursor CLI assistant"
echo -e "    tree     - Show directory structure"
echo -e "${BLUE}───────────────────────────────────────────────────────────────${NC}"
echo ""

# -----------------------------------------------------------------------------
# Handle shutdown
# -----------------------------------------------------------------------------
cleanup() {
    echo ""
    echo -e "${YELLOW}Shutting down services...${NC}"
    kill $WATCHER_PID 2>/dev/null || true
    kill $TTYD_PID 2>/dev/null || true
    exit 0
}

trap cleanup SIGTERM SIGINT

# -----------------------------------------------------------------------------
# Keep container running or execute command
# -----------------------------------------------------------------------------
if [ $# -gt 0 ]; then
    exec "$@"
else
    echo -e "${GREEN}Container ready. Connect via web terminal.${NC}"
    wait -n $WATCHER_PID $TTYD_PID 2>/dev/null || true
    cleanup
fi
