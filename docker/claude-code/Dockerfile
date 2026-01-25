# =============================================================================
# Claude Code Interactive Session Image
#
# Components:
#   - Claude Code CLI (official installer)
#   - ttyd (web terminal)
#   - File watcher service (WebSocket streaming)
# =============================================================================
FROM palad/agent-base:latest

# -----------------------------------------------------------------------------
# Claude Code CLI
# -----------------------------------------------------------------------------
RUN npm install -g @anthropic-ai/claude-code

# -----------------------------------------------------------------------------
# Create non-root user
# -----------------------------------------------------------------------------
RUN useradd -m -d /home/claude -s /bin/bash claude \
    && chown -R claude:claude /workspace /opt/watcher

# Default .claude.json (theme + onboarding state)
RUN mkdir -p /home/claude/.claude \
    && chown -R claude:claude /home/claude

# -----------------------------------------------------------------------------
# Configuration & entrypoint
# -----------------------------------------------------------------------------
COPY entrypoint.sh /app/
RUN chmod +x /app/entrypoint.sh

WORKDIR /workspace

# Use tini as init system for proper signal handling
ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
