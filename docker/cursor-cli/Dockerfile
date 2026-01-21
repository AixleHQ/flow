# =============================================================================
# Cursor CLI Interactive Session Image
#
# Components:
#   - Cursor CLI (official installer from cursor.com)
#   - ttyd (web terminal)
#   - File watcher service (WebSocket streaming)
# =============================================================================
FROM palad/agent-base:latest

# -----------------------------------------------------------------------------
# Create non-root user first
# -----------------------------------------------------------------------------
RUN useradd -m -d /home/cursor -s /bin/bash cursor \
    && chown -R cursor:cursor /workspace /opt/watcher

# -----------------------------------------------------------------------------
# Cursor CLI Installation
# Install via official script from https://cursor.com/cli
# Install as cursor user so it goes to correct location
# -----------------------------------------------------------------------------
USER cursor
WORKDIR /home/cursor
RUN curl https://cursor.com/install -fsS | bash

# Add agent to PATH via .bashrc
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

# Switch back to root for remaining setup
USER root

# Ensure cursor CLI is accessible and create symlink
RUN mkdir -p /home/cursor/.cursor \
    && chown -R cursor:cursor /home/cursor \
    && ln -sf /home/cursor/.local/bin/agent /usr/local/bin/agent || true

# -----------------------------------------------------------------------------
# Configuration & entrypoint
# -----------------------------------------------------------------------------
COPY entrypoint.sh /app/
RUN chmod +x /app/entrypoint.sh

WORKDIR /workspace

# Use tini as init system for proper signal handling
ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
