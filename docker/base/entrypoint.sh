#!/bin/bash
set -e

# =============================================================================
# Shared Agent Container Entrypoint
#
# Starts:
#   - MITM proxy for API request logging
#   - File watcher service (WebSocket + HTTP)
#   - ttyd web terminal with tmux session persistence
#
# Configuration (env vars set by each agent Dockerfile):
#   AGENT_NAME      - Display name (default: "Agent")
#   API_KEY_VAR     - Name of API key env var to validate (optional)
#   TTYD_CMD        - CLI command, set at runtime by strategy (default: "bash")
#   AGENT_PROMPT    - Non-interactive prompt text (optional, set at runtime)
# =============================================================================

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
TTYD_PORT="${TTYD_PORT:-7681}"
WATCHER_PORT="${WATCHER_PORT:-4040}"
WORKSPACE="${WORKSPACE:-/workspace}"
AGENT_NAME="${AGENT_NAME:-Agent}"

# Ensure HOME config directories exist (may be tmpfs mounted)
mkdir -p "$HOME/.config" 2>/dev/null || true

# -----------------------------------------------------------------------------
# Setup workspace
# -----------------------------------------------------------------------------
mkdir -p "$WORKSPACE/repo" "$WORKSPACE/outputs"

# Clone repo if URL provided
if [ -n "$REPO_URL" ]; then
    echo -e "${CYAN}📦 Cloning repository...${NC}"
    if [ -n "$REPO_BRANCH" ]; then
        git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$WORKSPACE/repo" 2>/dev/null || {
            echo -e "${YELLOW}⚠️  Failed to clone repo${NC}"
        }
    else
        git clone --depth 1 "$REPO_URL" "$WORKSPACE/repo" 2>/dev/null || {
            echo -e "${YELLOW}⚠️  Failed to clone repo${NC}"
        }
    fi
fi

# Copy step-specific prompt file if available (e.g. CLAUDE.md for pipeline steps)
if [ -n "$STEP_NAME" ] && [ -f "/prompts/${STEP_NAME}.md" ]; then
    cp "/prompts/${STEP_NAME}.md" "$WORKSPACE/CLAUDE.md"
    echo -e "${GREEN}✅ Loaded prompt: ${STEP_NAME}${NC}"
fi

# -----------------------------------------------------------------------------
# Start MITM proxy
# -----------------------------------------------------------------------------
source /opt/mitm/start-mitm.sh

# -----------------------------------------------------------------------------
# Start File Watcher Service
# -----------------------------------------------------------------------------
cd /opt/watcher
WATCH_DIR="$WORKSPACE" WATCHER_PORT="$WATCHER_PORT" node index.js > /dev/null 2>&1 &
WATCHER_PID=$!
cd "$WORKSPACE"

sleep 1
if kill -0 $WATCHER_PID 2>/dev/null; then
    echo -e "${GREEN}✅ File watcher ready${NC}"
else
    echo -e "${YELLOW}⚠️  File watcher failed${NC}"
fi

# -----------------------------------------------------------------------------
# Start OpenVSCode Server (interactive sessions only)
# Skipped when AGENT_PROMPT is set (non-interactive / autonomous mode)
# -----------------------------------------------------------------------------
if [ -z "$AGENT_PROMPT" ]; then
    VSCODE_PORT="${VSCODE_PORT:-8443}"
    SERVER_BASE_PATH="/t/${ROUTE_TOKEN}/ide"

    VSCODE_DATA_DIR="$HOME/.openvscode-server/data"
    mkdir -p "$VSCODE_DATA_DIR/Machine" "$VSCODE_DATA_DIR/User"
    cp /opt/openvscode-server/default-settings.json "$VSCODE_DATA_DIR/Machine/settings.json"
    cp /opt/openvscode-server/default-settings.json "$VSCODE_DATA_DIR/User/settings.json"

    /opt/openvscode-server/bin/openvscode-server \
        --port "$VSCODE_PORT" \
        --host 0.0.0.0 \
        --server-base-path "$SERVER_BASE_PATH" \
        --connection-token "$VSCODE_TOKEN" \
        --default-folder /workspace \
        > /dev/null 2>&1 &
    VSCODE_PID=$!

    sleep 1
    if kill -0 $VSCODE_PID 2>/dev/null; then
        echo -e "${GREEN}✅ OpenVSCode Server ready on port ${VSCODE_PORT}${NC}"
    else
        echo -e "${YELLOW}⚠️  OpenVSCode Server failed to start${NC}"
    fi
fi

# -----------------------------------------------------------------------------
# Start ttyd Web Terminal (with tmux session persistence)
#
# All commands run inside tmux:
#   - Command survives browser disconnects / tab refreshes
#   - Scrollback history (50k lines) preserved across reconnections
#   - Multiple tabs share the same live session
#   - tmux new -A: creates session on first connect, re-attaches on subsequent
# -----------------------------------------------------------------------------
TTYD_CMD="${TTYD_CMD:-bash}"

if [ -n "$AGENT_PROMPT" ]; then
    # Non-interactive: write prompt to file, build wrapper script
    # On exit, write exit code to /tmp/.agent_done so poll_for_completion detects it
    printf '%s' "$AGENT_PROMPT" > /tmp/.agent_prompt
    cat > /tmp/run_agent.sh <<AGENTEOF
#!/bin/sh
${TTYD_CMD} "\$(cat /tmp/.agent_prompt)"
EC=\$?
printf '%d' "\$EC" > /tmp/.agent_done
exit \$EC
AGENTEOF
    chmod +x /tmp/run_agent.sh
    TMUX_CMD="/tmp/run_agent.sh"
else
    TMUX_CMD="$TTYD_CMD"
fi

# -W enables input; omit for non-interactive (read-only terminal)
TTYD_WRITE_FLAG=""
if [ -z "$AGENT_PROMPT" ]; then
    TTYD_WRITE_FLAG="-W"
fi

ttyd $TTYD_WRITE_FLAG -p "$TTYD_PORT" tmux -u new -A -s agent $TMUX_CMD &
TTYD_PID=$!

sleep 1
if kill -0 $TTYD_PID 2>/dev/null; then
    echo -e "${GREEN}✅ ${AGENT_NAME} terminal ready${NC}"
else
    echo -e "${YELLOW}⚠️  Terminal failed to start${NC}"
fi

echo -e "${GREEN}Container ready.${NC}"

# Pipe tmux pane output to container stdout (docker logs)
# Wait for session to be created by first ttyd client, then attach pipe
(while ! tmux has-session -t agent 2>/dev/null; do sleep 1; done
 tmux pipe-pane -t agent "cat >> /proc/1/fd/1") &

# -----------------------------------------------------------------------------
# Handle shutdown
# -----------------------------------------------------------------------------
cleanup() {
    echo -e "${YELLOW}Shutting down...${NC}"
    kill $MITM_PID 2>/dev/null || true
    kill $WATCHER_PID 2>/dev/null || true
    kill $TTYD_PID 2>/dev/null || true
    kill $VSCODE_PID 2>/dev/null || true
    exit 0
}

trap cleanup SIGTERM SIGINT

# Keep container running or execute provided command
if [ $# -gt 0 ]; then
    exec "$@"
else
    wait -n $WATCHER_PID $TTYD_PID ${VSCODE_PID:+$VSCODE_PID} 2>/dev/null || true
    cleanup
fi
