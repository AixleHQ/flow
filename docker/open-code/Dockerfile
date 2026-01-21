# =============================================================================
# Open Code Interactive Session Image
#
# Components:
#   - Open Code CLI (https://opencode.ai)
#   - ttyd (web terminal)
#   - File watcher service (WebSocket streaming)
# =============================================================================
FROM palad/agent-base:latest

# -----------------------------------------------------------------------------
# Create non-root user first
# -----------------------------------------------------------------------------
RUN useradd -m -d /home/opencode -s /bin/bash opencode \
    && chown -R opencode:opencode /workspace /opt/watcher

# -----------------------------------------------------------------------------
# Open Code CLI Installation
# Install via official script from https://opencode.ai
# Install as opencode user so it goes to correct location
# -----------------------------------------------------------------------------
USER opencode
WORKDIR /home/opencode
RUN curl -fsSL https://opencode.ai/install | bash

# Add opencode to PATH via .bashrc
RUN echo 'export PATH="$HOME/.opencode/bin:$PATH"' >> ~/.bashrc

# Switch back to root for remaining setup
USER root

# Ensure opencode CLI is accessible and create symlink
RUN chown -R opencode:opencode /home/opencode \
    && ln -sf /home/opencode/.opencode/bin/opencode /usr/local/bin/opencode || true

# -----------------------------------------------------------------------------
# Configuration & entrypoint
# -----------------------------------------------------------------------------
COPY entrypoint.sh /app/
RUN chmod +x /app/entrypoint.sh

WORKDIR /workspace

# Use tini as init system for proper signal handling
ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
