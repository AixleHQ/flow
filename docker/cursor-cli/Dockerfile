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
# What https://cursor.com/install does, for the release the registry pins: that script
# embeds the one release it downloads, so it cannot install any other. Cursor publishes
# no checksum for the package; the vendor's installer verifies none either.
ARG TARGETARCH
ARG CLI_VERSION
RUN set -eux; \
    : "${CLI_VERSION:?pinned in config/agent_runtimes.json; build with make build-agents}"; \
    arch="${TARGETARCH:-amd64}"; [ "$arch" = "amd64" ] && arch=x64; \
    dir="/home/cursor/.local/share/cursor-agent/versions/${CLI_VERSION}"; \
    mkdir -p "$dir" /home/cursor/.local/bin; \
    curl -fsSL "https://downloads.cursor.com/lab/${CLI_VERSION}/linux/${arch}/agent-cli-package.tar.gz" \
      | tar --strip-components=1 -xzf - -C "$dir"; \
    ln -s "$dir/cursor-agent" /home/cursor/.local/bin/agent; \
    ln -s "$dir/cursor-agent" /home/cursor/.local/bin/cursor-agent; \
    test "$(/home/cursor/.local/bin/agent --version)" = "$CLI_VERSION"
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

USER root
# `install -d` creates just the config dirs with the right owner. A `chown -R` over
# /home/cursor would be a no-op (the install above ran AS cursor) that still copied
# up the whole 229 MB install — bundled node included — into this layer
# (docs/research/technical-agent-image-size-audit-2026-08-04.md).
RUN test -x /home/cursor/.local/bin/agent \
    && ln -sf /home/cursor/.local/bin/agent /usr/local/bin/agent \
    && install -d -o cursor -g cursor /home/cursor/.config /home/cursor/.config/cursor /home/cursor/.cursor

# The CLI version this image actually shipped with, recorded where anything can read it:
# `docker run <image> cat /etc/aixle-cli-version`. The canary builds the vendor's newest
# release instead of the pin, so the version is not always the one the registry names.
RUN agent --version > /etc/aixle-cli-version

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

WORKDIR /workspace
ENV HOME=/home/cursor \
    AGENT_NAME="Cursor CLI" \
    PATH="/home/cursor/.local/bin:${PATH}" \
    LANG=C.UTF-8

ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
