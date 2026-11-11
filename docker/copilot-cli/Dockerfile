# =============================================================================
# GitHub Copilot CLI Interactive Session Image
#
# Build context: docker/ (parent dir, for access to base/ scripts)
# Build command: docker build -f copilot-cli/Dockerfile -t aixle/copilot-cli:latest .
# =============================================================================
ARG BASE_IMAGE=aixle/agent-base-core:latest
FROM ${BASE_IMAGE}

# -G AGENT_BROWSERS_GROUP: write access to the shared browser tree (Playwright creates
# a server dir inside it on first launch) without a 1 GB-duplicating recursive chown.
RUN useradd -m -d /home/copilot -s /bin/bash -G ${AGENT_BROWSERS_GROUP} copilot

# The CLI updates itself (and its first-party plugins) by default. The image pins the
# release in config/agent_runtimes.json, so updates stay off for every process, the
# auth terminal and execs included, not only for the launch commands that pass
# --no-auto-update.
ENV COPILOT_AUTO_UPDATE=false \
    COPILOT_HOME=/home/copilot/.copilot

# `@github/copilot` is a loader plus a per-platform native package, and the native
# binary unpacks its JavaScript (~250 MB) into ~/.cache/copilot the first time a command
# needs it. `copilot help config` makes it do that here, as the agent's user, so no
# session writes it into its own container layer.
# The cache clean has to be in this instruction: a later `npm cache clean` leaves the
# cache in this layer forever.
# Pinned (config/agent_runtimes.json); the weekly canary builds the newest release.
ARG CLI_VERSION
RUN set -eux; \
    : "${CLI_VERSION:?pinned in config/agent_runtimes.json; build with make build-agents}"; \
    npm install -g "@github/copilot@${CLI_VERSION}"; \
    su - copilot -c "COPILOT_AUTO_UPDATE=false copilot help config >/dev/null"; \
    test -d "/home/copilot/.cache/copilot/pkg/linux-$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/')/${CLI_VERSION}"; \
    npm cache clean --force

# The CLI version this image actually shipped with: `docker run <image> cat /etc/aixle-cli-version`.
RUN su - copilot -c "COPILOT_AUTO_UPDATE=false copilot --version" > /etc/aixle-cli-version

# Integration boundary: Agents::CopilotCliAdapter#context_file_path writes every session's
# task and role context to $COPILOT_HOME/copilot-instructions.md, the CLI's personal
# instructions file. A release that stopped reading it would leave sessions without
# their instructions while every Ruby-side assertion still passed, so ask the installed
# CLI which sources it loads and fail the build instead. Runs offline and unauthenticated.
RUN set -eux; \
    su copilot -c 'set -eux; \
        mkdir -p /home/copilot/.copilot; \
        printf "aixle context probe\n" > /home/copilot/.copilot/copilot-instructions.md; \
        cd /tmp && COPILOT_HOME=/home/copilot/.copilot COPILOT_AUTO_UPDATE=false \
            copilot instruction list > /tmp/copilot-instructions.txt; \
        grep -qF "/home/copilot/.copilot/copilot-instructions.md" /tmp/copilot-instructions.txt; \
        rm -rf /home/copilot/.copilot /tmp/copilot-instructions.txt'

# The model-catalogue reader Agents::CopilotCliAdapter#collect_credential_metadata execs.
COPY copilot-cli/aixle-copilot-models.mjs /opt/aixle/copilot-models.mjs
RUN chmod 0755 /opt/aixle/copilot-models.mjs

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
RUN chown -R copilot:copilot /workspace /home/copilot

WORKDIR /workspace
ENV HOME=/home/copilot \
    AGENT_NAME="Copilot CLI" \
    LANG=C.UTF-8

ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
