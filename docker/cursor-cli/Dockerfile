# =============================================================================
# Cursor CLI Interactive Session Image
#
# Build context: docker/ (parent dir, for access to base/ scripts)
# Build command: docker build -f cursor-cli/Dockerfile -t aixle/cursor-cli:latest .
# =============================================================================
ARG BASE_IMAGE=aixle/agent-base-core:latest
FROM ${BASE_IMAGE}

# =============================================================================
# Agent-specific layers (CACHED when only shared scripts change)
# =============================================================================
# -G AGENT_BROWSERS_GROUP: write access to the shared browser tree (Playwright creates
# a server dir inside it on first launch) without a 1 GB-duplicating recursive chown.
RUN useradd -m -d /home/cursor -s /bin/bash -G ${AGENT_BROWSERS_GROUP} cursor \
    && chown -R cursor:cursor /workspace /home/cursor

USER cursor
WORKDIR /home/cursor
ARG CURSOR_CLI_VERSION=2026.08.25-3e8eec8
RUN curl https://cursor.com/install -fsS | bash \
    && test -x /home/cursor/.local/bin/agent \
    && readlink -f /home/cursor/.local/bin/agent | grep -qF "/versions/${CURSOR_CLI_VERSION}/" \
    && /home/cursor/.local/bin/agent --version | grep -qF "${CURSOR_CLI_VERSION}"
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

USER root
# `install -d` creates just the config dirs with the right owner. A `chown -R` over
# /home/cursor would be a no-op (the installer above ran AS cursor) that still copied
# up the whole 229 MB install — bundled node included — into this layer
# (docs/research/technical-agent-image-size-audit-2026-08-04.md).
RUN test -x /home/cursor/.local/bin/agent \
    && ln -sf /home/cursor/.local/bin/agent /usr/local/bin/agent \
    && install -d -o cursor -g cursor /home/cursor/.config /home/cursor/.config/cursor /home/cursor/.cursor

# =============================================================================
# Shared scripts — ordered by stability (most stable first, entrypoint last)
# =============================================================================
COPY base/tmux.conf /etc/tmux.conf
COPY base/inputrc /etc/inputrc
COPY base/vscode-settings.json /opt/openvscode-server/default-settings.json

WORKDIR /opt/watcher
COPY base/watcher/package.json ./
RUN npm install --production && npm cache clean --force
COPY base/watcher/index.js ./

COPY base/auth-check/index.js /opt/auth-check/index.js
COPY base/logger/ /opt/mitm/
RUN chmod +x /opt/mitm/*.sh

COPY base/entrypoint.sh /app/
RUN chmod +x /app/entrypoint.sh

# =============================================================================
# Final setup
# =============================================================================
RUN chown -R cursor:cursor /opt/watcher

WORKDIR /workspace
ENV HOME=/home/cursor \
    AGENT_NAME="Cursor CLI" \
    PATH="/home/cursor/.local/bin:${PATH}" \
    LANG=C.UTF-8

ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
