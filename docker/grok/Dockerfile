# =============================================================================
# Grok CLI Interactive Session Image
#
# Build context: docker/ (parent dir, for access to base/ scripts)
# Build command: docker build -f grok/Dockerfile -t aixle/grok:latest .
# =============================================================================
ARG BASE_IMAGE=aixle/agent-base-core:latest
FROM ${BASE_IMAGE}

# =============================================================================
# Agent-specific layers (CACHED when only shared scripts change)
# =============================================================================
# -G AGENT_BROWSERS_GROUP: write access to the shared browser tree (Playwright creates
# a server dir inside it on first launch) without a 1 GB-duplicating recursive chown.
RUN useradd -m -d /home/grok -s /bin/bash -G ${AGENT_BROWSERS_GROUP} grok

# `@xai-official/grok` ships a thin node trampoline plus a brotli-compressed native
# binary in a per-platform sibling package, and materialises the binary into
# $GROK_HOME/bin on first launch. Doing that here, as the `grok` user, keeps ~160 MB of
# decompression out of every container start and fails the BUILD (not a live session) if
# the install is broken. The payload is then redundant — the trampoline returns the
# canonical path without ever looking at it again — so it goes, rather than shipping the
# same binary twice.
#
# The cache clean has to be in THIS instruction: a later `npm cache clean` (the
# watcher layer runs one) leaves ~69 MB of /root/.npm in this layer forever.
RUN set -eux; \
    npm install -g @xai-official/grok; \
    su grok -c "grok --version"; \
    test -x /home/grok/.grok/bin/grok; \
    rm -f "$(npm root -g)"/@xai-official/grok-linux-*/bin/grok.br; \
    npm cache clean --force

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
RUN chown -R grok:grok /workspace /opt/watcher /home/grok

WORKDIR /workspace
ENV HOME=/home/grok \
    AGENT_NAME="Grok CLI" \
    LANG=C.UTF-8

ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
