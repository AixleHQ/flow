# =============================================================================
# Claude Code Interactive Session Image
#
# Components:
#   - Claude Code CLI (official installer)
#   - ttyd (web terminal)
#   - File watcher service (WebSocket streaming)
#   - MITM proxy (inherited from base)
# =============================================================================
FROM palad/agent-base:latest

# -----------------------------------------------------------------------------
# Create non-root user
# -----------------------------------------------------------------------------
RUN useradd -m -d /home/claude -s /bin/bash claude \
    && chown -R claude:claude /workspace /opt/watcher /home/claude

# -----------------------------------------------------------------------------
# Claude Code CLI (official installer)
# -----------------------------------------------------------------------------
USER claude
WORKDIR /home/claude
RUN curl -fsSL https://claude.ai/install.sh | bash

# Add claude to PATH
ENV PATH="/home/claude/.local/bin:${PATH}"

# Switch back to root for remaining setup
USER root

# Default .claude directory
RUN mkdir -p /home/claude/.claude \
    && chown -R claude:claude /home/claude

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
WORKDIR /workspace
ENV HOME=/home/claude \
    AGENT_NAME="Claude Code"

# Run as non-root user (required for --dangerously-skip-permissions)
USER claude
