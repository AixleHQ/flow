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
# MITM proxy (mitmdump) for request logging
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends python3-pip && \
    python3 -m pip install --no-cache-dir --break-system-packages mitmproxy==10.2.4 && \
    apt-get purge -y python3-pip && apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/* /root/.cache

# -----------------------------------------------------------------------------
# Claude Code CLI
# -----------------------------------------------------------------------------
RUN npm install -g @anthropic-ai/claude-code

# -----------------------------------------------------------------------------
# Create non-root user
# -----------------------------------------------------------------------------
RUN useradd -m -d /home/claude -s /bin/bash claude \
    && chown -R claude:claude /workspace /opt/watcher /home/claude

# Default .claude.json directory
RUN mkdir -p /home/claude/.claude \
    && chown -R claude:claude /home/claude

# -----------------------------------------------------------------------------
# Configuration & entrypoint
# -----------------------------------------------------------------------------
COPY entrypoint.sh /app/
COPY mitm_logger.py /app/
RUN chmod +x /app/entrypoint.sh

WORKDIR /workspace
ENV HOME=/home/claude

# Run as non-root user (required for --dangerously-skip-permissions)
USER claude

# Use tini as init system for proper signal handling
ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
