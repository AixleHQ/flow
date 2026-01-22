# =============================================================================
# Gemini CLI Interactive Session Image
#
# Components:
#   - Gemini CLI (@google/gemini-cli)
#   - ttyd (web terminal)
#   - File watcher service (WebSocket streaming)
# =============================================================================
FROM palad/agent-base:latest

# -----------------------------------------------------------------------------
# Create non-root user first
# -----------------------------------------------------------------------------
RUN useradd -m -d /home/gemini -s /bin/bash gemini \
    && chown -R gemini:gemini /workspace /opt/watcher

# -----------------------------------------------------------------------------
# Gemini CLI Installation
# Install via npm global package
# -----------------------------------------------------------------------------
USER root
RUN npm install -g @google/gemini-cli

# Switch to gemini user for configuration
USER gemini
WORKDIR /home/gemini

# Switch back to root for remaining setup
USER root

# -----------------------------------------------------------------------------
# Configuration & entrypoint
# -----------------------------------------------------------------------------
COPY entrypoint.sh /app/
RUN chmod +x /app/entrypoint.sh

WORKDIR /workspace

# Use tini as init system for proper signal handling
ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
