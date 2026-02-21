# =============================================================================
# Gemini CLI Interactive Session Image
#
# Build context: docker/ (parent dir, for access to base/ scripts)
# Build command: docker build -f gemini-cli/Dockerfile -t palad/gemini-cli:latest .
# =============================================================================
FROM palad/agent-base-core:latest

# =============================================================================
# Agent-specific layers (CACHED when only shared scripts change)
# =============================================================================
RUN useradd -m -d /home/gemini -s /bin/bash gemini

RUN npm install -g @google/gemini-cli

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
RUN chown -R gemini:gemini /workspace /opt/watcher /home/gemini

WORKDIR /workspace
ENV HOME=/home/gemini \
    AGENT_NAME="Gemini CLI" \
    LANG=C.UTF-8

ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
