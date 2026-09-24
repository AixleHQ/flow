# =============================================================================
# Gemini CLI Interactive Session Image
#
# Build context: docker/ (parent dir, for access to base/ scripts)
# Build command: docker build -f gemini-cli/Dockerfile -t aixle/gemini-cli:latest .
# =============================================================================
ARG BASE_IMAGE=aixle/agent-base-core:latest
FROM ${BASE_IMAGE}

# =============================================================================
# Agent-specific layers (CACHED when only shared scripts change)
# =============================================================================
# -G AGENT_BROWSERS_GROUP: write access to the shared browser tree (Playwright creates
# a server dir inside it on first launch) without a 1 GB-duplicating recursive chown.
RUN useradd -m -d /home/gemini -s /bin/bash -G ${AGENT_BROWSERS_GROUP} gemini

# The cache clean has to be in THIS instruction: a later `npm cache clean` (the
# watcher layer runs one) leaves ~69 MB of /root/.npm in this layer forever.
ARG GEMINI_CLI_VERSION=0.57.0
RUN npm install -g @google/gemini-cli@${GEMINI_CLI_VERSION} && npm cache clean --force

# The CLI version this image actually shipped with, recorded where anything can read it:
# `docker run <image> cat /etc/aixle-cli-version`. Cursor and Kiro come from vendor
# installers that install only the latest release, and the canary builds the newest
# release of the pinned ones, so the version is not always the one this file names.
RUN gemini --version > /etc/aixle-cli-version

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
RUN chown -R gemini:gemini /workspace /home/gemini

WORKDIR /workspace
ENV HOME=/home/gemini \
    AGENT_NAME="Gemini CLI" \
    LANG=C.UTF-8

ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
