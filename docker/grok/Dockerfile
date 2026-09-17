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

# `@xai-official/grok` ships a thin node trampoline plus a native binary, and
# materialises that binary under `$HOME/.grok/bin` on first launch. Doing it here, as the
# `grok` user, keeps the decompression out of every container start and fails the BUILD
# (not a live session) if the install is broken.
#
# Three things about that layout changed under us, and 1.0.34 is the version that showed
# it (the image stopped building on 2026-09-17):
#   * the payload no longer ships as a `@xai-official/grok-linux-*` sibling package, so
#     the removal that deduplicated it has nothing to remove;
#   * it is unpacked by the package's own postinstall — under the user running `npm
#     install`, i.e. root — rather than by the agent user's first launch;
#   * the unpacked file is VERSIONED (`grok-1.0.34`), so a fixed-name assertion could only
#     ever have passed by accident.
# What is worth asserting is therefore what proves the install: the payload exists after
# the postinstall, and the CLI runs as the agent user. The old assertion also guaranteed
# the decompression was paid at build time for the AGENT's home; that is no longer true,
# so a session may pay it once on first launch.
#
# The cache clean has to be in THIS instruction: a later `npm cache clean` (the
# watcher layer runs one) leaves ~69 MB of /root/.npm in this layer forever.
RUN set -eux; \
    npm install -g @xai-official/grok; \
    ls /root/.grok/bin/grok-* >/dev/null; \
    su - grok -c "grok --version"; \
    npm cache clean --force

# The CLI version this image actually shipped with, recorded where anything can read it:
# `docker run <image> cat /etc/aixle-cli-version`. Three of these CLIs are installed from a
# vendor script with no version to pin (claude, cursor, kiro), so two builds of the same
# Dockerfile are not the same image and nothing else says which one a container is running.
RUN su - grok -c "grok --version" > /etc/aixle-cli-version

# Integration boundary: Agents::GrokAdapter#context_file_path writes every session's
# task/role context to ~/.grok/rules/aixle-session-context.md, which the CLI is
# documented to scan as a global rules root. If a CLI release ever stops scanning it,
# sessions would silently run without their instructions and every Ruby-side assertion
# would still pass — they only pin the string we write. So ask the installed CLI
# instead: `grok inspect` prints the instruction files it discovers, and the build
# fails here rather than in a live session. Runs offline and unauthenticated.
RUN set -eux; \
    su grok -c 'set -eux; \
        mkdir -p /home/grok/.grok/rules; \
        printf "aixle context probe\n" > /home/grok/.grok/rules/aixle-session-context.md; \
        HOME=/home/grok GROK_DISABLE_AUTOUPDATER=1 GROK_TELEMETRY_ENABLED=false \
            grok inspect > /tmp/grok-inspect.txt; \
        grep -qF "/home/grok/.grok/rules/aixle-session-context.md" /tmp/grok-inspect.txt; \
        rm -f /home/grok/.grok/rules/aixle-session-context.md /tmp/grok-inspect.txt'

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
