# =============================================================================
# Claude Code Interactive Session Image
#
# Build context: docker/ (parent dir, for access to base/ scripts)
# Build command: docker build -f claude-code/Dockerfile -t palad/claude-code:latest .
# =============================================================================
ARG BASE_IMAGE=palad/agent-base-core:latest
FROM ${BASE_IMAGE}

# =============================================================================
# Agent-specific layers (CACHED when only shared scripts change)
# =============================================================================
RUN useradd -m -d /home/claude -s /bin/bash claude \
    && chown -R claude:claude /workspace /home/claude

USER claude
WORKDIR /home/claude
RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH="/home/claude/.local/bin:${PATH}"

USER root
RUN mkdir -p /home/claude/.claude \
    && chown -R claude:claude /home/claude

# =============================================================================
# Shared scripts — ordered by stability (most stable first, entrypoint last)
# =============================================================================
RUN printf '%s\n' \
    'set -g history-limit 50000' \
    'set -g remain-on-exit on' \
    'set -g status off' \
    'set -g set-clipboard on' \
    'set -g allow-passthrough on' \
    > /etc/tmux.conf

COPY base/inputrc /etc/inputrc
COPY base/vscode-settings.json /opt/openvscode-server/default-settings.json

WORKDIR /opt/watcher
COPY base/watcher/package.json ./
RUN npm install --production && npm cache clean --force
COPY base/watcher/index.js ./

COPY base/auth-check/index.js /opt/auth-check/index.js
COPY base/logger/ /opt/mitm/
RUN chmod +x /opt/mitm/start-mitm.sh

COPY base/entrypoint.sh /app/
RUN chmod +x /app/entrypoint.sh

# =============================================================================
# Final setup
# =============================================================================
RUN chown -R claude:claude /opt/watcher

WORKDIR /workspace
ENV HOME=/home/claude \
    AGENT_NAME="Claude Code" \
    LANG=C.UTF-8

# Run as non-root user (required for --dangerously-skip-permissions)
USER claude

ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
