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

# What https://cli.kiro.dev/install does, for the release the registry pins: that
# script installs only the channel's latest release. The archive's own install.sh just
# copies bin/kiro-cli, kiro-cli-chat and kiro-cli-term into ~/.local/bin; kiro-cli-term
# is the shell/autocomplete integration (`kiro-cli integrations`, `kiro-cli inline`),
# which no session uses, so only the other two are installed. The glibc archive needs
# glibc 2.34 (x86_64) or 2.39 (aarch64); the base image's Debian has 2.41.
#
# The checksums are per release: Kiro publishes them only in the channel's latest
# manifest (versioned manifests return 403), so a pinned release keeps its pair here. A
# version without one is accepted only while it is the channel's latest release, checked
# against that manifest — how the canary builds the newest release — and otherwise fails
# the build.
#
# The install is verified here rather than in a live session: a broken download or a
# glibc mismatch fails the BUILD instead of every user's first Kiro terminal.
ARG TARGETARCH
ARG CLI_VERSION
RUN set -eux; \
    : "${CLI_VERSION:?pinned in config/agent_runtimes.json; build with make build-agents}"; \
    arch="${TARGETARCH:-amd64}"; [ "$arch" = "amd64" ] && arch=x86_64; [ "$arch" = "arm64" ] && arch=aarch64; \
    package="kirocli-${arch}-linux.zip"; \
    channel=https://prod.download.cli.kiro.dev/stable; \
    case "${CLI_VERSION}/$arch" in \
      2.28.0/x86_64) sha256="4d6d20c3ffed99904081a062678b3c1978dc7d68c9f6c530f3f28f163011c8ee" ;; \
      2.28.0/aarch64) sha256="39169fc43557ff3c007ccf5388ff95413539b2c6a8dfab6c69e4a7b8899bebbc" ;; \
      *) sha256="$(curl -fsSL "$channel/latest/manifest.json" | jq -r --arg v "$CLI_VERSION" --arg f "${CLI_VERSION}/$package" \
           'select(.version == $v) | .packages[] | select(.download == $f) | .sha256')"; \
         [ -n "$sha256" ] || { echo "No checksum for kiro-cli ${CLI_VERSION} on $arch: add it to docker/kiro-cli/Dockerfile" >&2; exit 1; } ;; \
    esac; \
    curl -fsSL "$channel/${CLI_VERSION}/$package" -o /tmp/kiro.zip; \
    echo "$sha256  /tmp/kiro.zip" | sha256sum -c -; \
    unzip -q /tmp/kiro.zip 'kirocli/bin/kiro-cli' 'kirocli/bin/kiro-cli-chat' -d /tmp/kiro; \
    install -d -o kiro -g kiro /home/kiro/.local /home/kiro/.local/bin; \
    install -o kiro -g kiro -m 755 /tmp/kiro/kirocli/bin/kiro-cli /tmp/kiro/kirocli/bin/kiro-cli-chat /home/kiro/.local/bin/; \
    rm -rf /tmp/kiro /tmp/kiro.zip; \
    su kiro -c 'set -eux; \
        export HOME=/home/kiro PATH=/home/kiro/.local/bin:$PATH; \
        test "$(kiro-cli --version)" = "kiro-cli '"${CLI_VERSION}"'"; \
        kiro-cli chat --help > /dev/null'

# The CLI version this image actually shipped with, recorded where anything can read it:
# `docker run <image> cat /etc/aixle-cli-version`. The canary builds the vendor's newest
# release instead of the pin, so the version is not always the one the registry names.
RUN su kiro -c '/home/kiro/.local/bin/kiro-cli --version' > /etc/aixle-cli-version

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
# and the CLI was installed owned by kiro, so there is nothing to fix — and a recursive
# chown would rewrite all ~260 MB of binaries into a second layer, doubling the image
# for no change (the failure mode documented in the agent-image size audit).
RUN chown -R kiro:kiro /workspace

WORKDIR /workspace
# ~/.local/bin is where the CLI is installed, and it is NOT on the default
# Debian PATH for a non-login shell — which is what tmux starts the CLI in.
ENV HOME=/home/kiro \
    PATH=/home/kiro/.local/bin:$PATH \
    AGENT_NAME="Kiro CLI" \
    LANG=C.UTF-8

ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
