# =============================================================================
# OpenAI Codex CLI Interactive Session Image
#
# Components:
#   - OpenAI Codex CLI
#   - ttyd (web terminal)
#   - File watcher service (WebSocket streaming)
# =============================================================================
FROM palad/agent-base:latest

# -----------------------------------------------------------------------------
# OpenAI Codex CLI
# -----------------------------------------------------------------------------
RUN npm install -g @openai/codex

# -----------------------------------------------------------------------------
# Create non-root user
# -----------------------------------------------------------------------------
RUN useradd -m -d /home/codex -s /bin/bash codex \
    && chown -R codex:codex /workspace /opt/watcher

# -----------------------------------------------------------------------------
# Configuration & entrypoint
# -----------------------------------------------------------------------------
COPY entrypoint.sh /app/
RUN chmod +x /app/entrypoint.sh

WORKDIR /workspace

# Use tini as init system for proper signal handling
ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
