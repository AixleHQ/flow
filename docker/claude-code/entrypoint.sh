#!/bin/bash
set -e

# =============================================================================
# Claude Code Container Entrypoint
#
# Starts:
#   - ttyd (web terminal) on port 7681
#   - File watcher service on port 4040
#   - Interactive bash shell (or custom command)
#
# Claude Code Auth:
#   Uses managed-settings.json with apiKeyHelper to read ANTHROPIC_API_KEY
#   No interactive login required - fully deterministic startup
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

# HOME is set in Dockerfile
# Ensure config directories exist (may be tmpfs mounted)
mkdir -p "$HOME/.claude" 2>/dev/null || true

# MITM proxy settings
MITM_PROXY_PORT="${MITM_PROXY_PORT:-8888}"
MITM_LOG_PATH="${MITM_LOG_PATH:-$WORKSPACE/output/mitmproxy.log}"
MITM_LOG_MAX_BODY="${MITM_LOG_MAX_BODY:-16000}"
MITM_CA_CERT="${MITM_CA_CERT:-$HOME/.mitmproxy/mitmproxy-ca-cert.pem}"
export MITM_LOG_PATH MITM_LOG_MAX_BODY

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Claude Code Interactive Session${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# -----------------------------------------------------------------------------
# Validate API key
# -----------------------------------------------------------------------------
if [ -n "$ANTHROPIC_API_KEY" ]; then
    echo -e "${GREEN}✅ ANTHROPIC_API_KEY configured${NC}"
else
    echo -e "${YELLOW}⚠️  ANTHROPIC_API_KEY not set - Claude Code will not work${NC}"
fi

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

# Copy step-specific CLAUDE.md prompt if available
if [ -n "$STEP_NAME" ] && [ -f "/prompts/${STEP_NAME}.md" ]; then
    cp "/prompts/${STEP_NAME}.md" "$WORKSPACE/CLAUDE.md"
    echo -e "${GREEN}✅ Loaded prompt: ${STEP_NAME}${NC}"
fi

# -----------------------------------------------------------------------------
# Start MITM proxy (mitmdump) and set proxy env vars
# -----------------------------------------------------------------------------
echo -e "${CYAN}🛡️  Starting MITM proxy on port ${MITM_PROXY_PORT}...${NC}"
HTTP_PROXY="http://localhost:${MITM_PROXY_PORT}"
HTTPS_PROXY="$HTTP_PROXY"
NO_PROXY="localhost,127.0.0.1,::1"
export HTTP_PROXY HTTPS_PROXY NO_PROXY

mitmdump --listen-host 0.0.0.0 --listen-port "${MITM_PROXY_PORT}" \
    --set block_global=false \
    -q -s /app/mitm_logger.py &
MITM_PID=$!

# Wait briefly for CA to be generated so Node can trust it
for _ in {1..20}; do
    if [ -f "$MITM_CA_CERT" ]; then
        export NODE_EXTRA_CA_CERTS="$MITM_CA_CERT"
        break
    fi
    sleep 0.1
done

if kill -0 $MITM_PID 2>/dev/null; then
    echo -e "${GREEN}✅ MITM proxy started (PID: $MITM_PID) - logging to ${MITM_LOG_PATH}${NC}"
else
    echo -e "${YELLOW}⚠️  MITM proxy failed to start${NC}"
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

# Default command is claude, can be overridden with TTYD_CMD env var
TTYD_CMD="${TTYD_CMD:-claude}"

# Start ttyd (already running as claude user via Dockerfile USER directive)
# -W: Writable (allow input)
# -p: Port
if [ -n "$TTYD_CREDENTIAL" ]; then
    ttyd -W -c "$TTYD_CREDENTIAL" -p "$TTYD_PORT" $TTYD_CMD &
else
    ttyd -W -p "$TTYD_PORT" $TTYD_CMD &
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
echo -e "    claude   - Start AI assistant (no login required)"
echo -e "    tree     - Show directory structure"
echo -e "${BLUE}───────────────────────────────────────────────────────────────${NC}"
echo ""

# -----------------------------------------------------------------------------
# Handle shutdown
# -----------------------------------------------------------------------------
cleanup() {
    echo ""
    echo -e "${YELLOW}Shutting down services...${NC}"
    kill $MITM_PID 2>/dev/null || true
    kill $WATCHER_PID 2>/dev/null || true
    kill $TTYD_PID 2>/dev/null || true
    exit 0
}

trap cleanup SIGTERM SIGINT

# -----------------------------------------------------------------------------
# Keep container running or execute command
# -----------------------------------------------------------------------------
if [ $# -gt 0 ]; then
    # Execute provided command
    exec "$@"
else
    # Keep container running
    echo -e "${GREEN}Container ready. Connect via web terminal.${NC}"

    # Wait for any background process to exit
    wait -n $WATCHER_PID $TTYD_PID 2>/dev/null || true

    # If one exits, cleanup and exit
    cleanup
fi
