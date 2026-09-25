# =============================================================================
# OpenAI Codex CLI Interactive Session Image
#
# Build context: docker/ (parent dir, for access to base/ scripts)
# Build command: docker build -f codex/Dockerfile -t aixle/codex:latest .
# =============================================================================
ARG BASE_IMAGE=aixle/agent-base-core:latest
FROM ${BASE_IMAGE}

# =============================================================================
# Agent-specific layers (CACHED when only shared scripts change)
# =============================================================================
# The cache clean has to be in THIS instruction: a later `npm cache clean` (the
# watcher layer runs one) leaves ~180 MB of /root/.npm in this layer forever.
# Pinned: the registry build cache keys this layer on the Dockerfile text, so an unpinned
# install kept shipping whichever release first filled the cache. The weekly canary
# builds the newest release instead.
ARG CODEX_VERSION=0.156.1
RUN npm install -g "@openai/codex@${CODEX_VERSION}" && npm cache clean --force

# The CLI version this image actually shipped with, recorded where anything can read it:
# `docker run <image> cat /etc/aixle-cli-version`. Cursor and Kiro come from vendor
# installers that install only the latest release, and the canary builds the newest
# release of the pinned ones, so the version is not always the one this file names.
RUN codex --version > /etc/aixle-cli-version

# -G AGENT_BROWSERS_GROUP: write access to the shared browser tree (Playwright creates
# a server dir inside it on first launch) without a 1 GB-duplicating recursive chown.
RUN useradd -m -d /home/codex -s /bin/bash -G ${AGENT_BROWSERS_GROUP} codex

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
RUN chown -R codex:codex /workspace /home/codex

WORKDIR /workspace
ENV HOME=/home/codex \
    AGENT_NAME="Codex" \
    LANG=C.UTF-8

ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
