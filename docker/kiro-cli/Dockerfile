# =============================================================================
# Kiro CLI Interactive Session Image
#
# Build context: docker/ (parent dir, for access to base/ scripts)
# Build command: docker build -f kiro-cli/Dockerfile -t aixle/kiro-cli:latest .
# =============================================================================
ARG BASE_IMAGE=aixle/agent-base-core:latest
FROM ${BASE_IMAGE}

# =============================================================================
# Agent-specific layers (CACHED when only shared scripts change)
# =============================================================================
# -G AGENT_BROWSERS_GROUP: write access to the shared browser tree (Playwright creates
# a server dir inside it on first launch) without a 1 GB-duplicating recursive chown.
RUN useradd -m -d /home/kiro -s /bin/bash -G ${AGENT_BROWSERS_GROUP} kiro

# The Kiro installer is a shell script that unpacks prebuilt binaries into
# $HOME/.local/bin — so it must run AS the agent user, not as root, or the CLI lands
# in /root and the session cannot reach it. `--force` skips the interactive
# "already installed / update your PATH" prompts; nothing in a build has a tty to
# answer them. `unzip`, `jq` and `curl` all come from the base image.
#
# Kiro ships ~1.1 GB of binaries (kiro-cli 100 MB + kiro-cli-chat 926 MB +
# kiro-cli-term 77 MB), which is several times any other runtime here — so the two
# reductions that are safe are taken in THIS instruction, where they actually shrink
# the layer instead of merely hiding files in a later one:
#   * kiro-cli-term is the shell/autocomplete integration (`kiro-cli integrations`,
#     `kiro-cli inline`). Nothing in a session uses it, and the CLI runs without it —
#     verified below, after the removal.
#   * the remaining binaries carry symbol tables; stripping takes kiro-cli-chat from
#     926 MB to 780 MB with no behaviour change.
#
# The install is verified here rather than in a live session: a broken download or a
# musl/glibc mismatch fails the BUILD instead of every user's first Kiro terminal.
RUN set -eux; \
    su kiro -c 'set -eux; \
        export HOME=/home/kiro PATH=/home/kiro/.local/bin:$PATH; \
        curl -fsSL https://cli.kiro.dev/install | bash -s -- --force; \
        test -x /home/kiro/.local/bin/kiro-cli; \
        rm -f /home/kiro/.local/bin/kiro-cli-term; \
        strip /home/kiro/.local/bin/kiro-cli /home/kiro/.local/bin/kiro-cli-chat; \
        kiro-cli --version; \
        kiro-cli chat --help > /dev/null'

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
# /home/kiro is deliberately NOT in this list. `useradd -m` created it owned by kiro
# and the CLI was installed as kiro, so there is nothing to fix — and a recursive
# chown would rewrite all ~900 MB of binaries into a second layer, doubling the image
# for no change (the failure mode documented in the agent-image size audit).
RUN chown -R kiro:kiro /workspace /opt/watcher

WORKDIR /workspace
# ~/.local/bin is where the installer puts kiro-cli, and it is NOT on the default
# Debian PATH for a non-login shell — which is what tmux starts the CLI in.
ENV HOME=/home/kiro \
    PATH=/home/kiro/.local/bin:$PATH \
    AGENT_NAME="Kiro CLI" \
    LANG=C.UTF-8

ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
