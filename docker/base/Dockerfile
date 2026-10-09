# uv / uvx (Astral), pulled in as a stage so the version stays a single pinned
# ARG. `COPY --from=<image>` does NOT expand build args — BuildKit rejects it
# outright — so a named stage is the only way to keep the tag in one place.
ARG UV_VERSION=0.9.29
FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

# =============================================================================
# tmux builder — 3.6+ for mode 2031 (light/dark theme reporting). Debian trixie
# ships 3.5a, which neither asks the browser terminal for its background nor tells
# the agent CLI when the app switches theme.
# =============================================================================
FROM node:26-slim AS tmux-builder
ARG TMUX_VERSION=3.7c
ARG TMUX_SHA256=7c60cae9a0e25288e2e24750aafc9e8800fc7fd4555e447e1b29ee4201cfb3bf
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl build-essential pkg-config bison libevent-dev libncurses-dev && \
    rm -rf /var/lib/apt/lists/*
RUN curl -fsSL -o /tmp/tmux.tar.gz \
        https://github.com/tmux/tmux/releases/download/${TMUX_VERSION}/tmux-${TMUX_VERSION}.tar.gz && \
    echo "${TMUX_SHA256}  /tmp/tmux.tar.gz" | sha256sum -c - && \
    tar xzf /tmp/tmux.tar.gz -C /tmp && \
    cd /tmp/tmux-${TMUX_VERSION} && ./configure --prefix=/usr/local && \
    make -j"$(nproc)" && strip tmux && install -m 0755 tmux /usr/local/bin/tmux

# =============================================================================
# Core Base Image for AI Coding Agents
#
# Heavy, rarely-changing dependencies only.
# Lightweight scripts (entrypoint, watcher, auth-check, logger) are added
# in each agent Dockerfile AFTER agent-specific installs, so that script
# changes don't invalidate expensive agent CLI install layers.
#
# Components:
#   - Node.js 26 (Debian slim for glibc compatibility)
#   - ttyd (web terminal)
#   - OpenVSCode Server (browser IDE)
#   - MITM proxy for request/response logging
#   - Common development tools (uv/uvx and pipx for Python MCP servers)
# =============================================================================
FROM node:26-slim

# -----------------------------------------------------------------------------
# System dependencies
#
# Every apt layer removes /var/lib/apt/lists itself. Deleting them in a LATER
# layer (as this file used to) leaves ~19 MB of index files in the image forever
# — the deletion only hides them from the final filesystem.
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Terminal & shell
    bash \
    bash-completion \
    # Development tools
    git \
    ripgrep \
    fd-find \
    jq \
    curl \
    tree \
    cloc \
    ca-certificates \
    libnss3-tools \
    # Archive extraction (tar/gzip already in base image)
    unzip \
    xz-utils \
    bzip2 \
    zstd \
    # Process management. procps is for the AGENT, not for us: `ps aux`, `pgrep`,
    # `pkill`, `top` and `free` are what an agent reaches for to find the dev server
    # it started or whatever is holding a port. Without it those commands just fail.
    tini \
    sudo \
    procps \
    # Python runtime for mitmproxy + the pipx MCP runtime
    python3 \
    python3-pip \
    pipx \
    # Build tools (for native npm modules): node-gyp compiles C++ on the spot when a
    # dependency ships no prebuilt binary for this platform (sharp, better-sqlite3,
    # canvas, bcrypt, node-pty). ~233 MiB with its pulled-in deps, and it has to be
    # decided here — an apt layer keeps the bytes of whatever it installed, so
    # purging the toolchain in a later layer would save nothing.
    make \
    g++ \
    # tmux runtime lib (tmux itself is built in the tmux-builder stage).
    libevent-core-2.1-7t64 \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# uv / uvx (Astral)
# -----------------------------------------------------------------------------
# `uvx` is what the MCP ecosystem actually publishes against: the registry's
# `runtimeHint` for pypi packages is overwhelmingly "uvx", not "pipx". Without it
# a catalog install of a Python connector would emit a command the image cannot
# run, and fail at session start after appearing to install cleanly.
#
# Copied from Astral's published image rather than curl|sh so the version is
# pinned and the layer is reproducible. The version lives in the global
# UV_VERSION arg at the top of this file.
COPY --from=uv /uv /uvx /usr/local/bin/

# -----------------------------------------------------------------------------
# GitHub CLI (gh)
# -----------------------------------------------------------------------------
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && apt-get install -y --no-install-recommends gh && \
    rm -rf /var/lib/apt/lists/*

# Authenticates each gh call through the session's git credential helper. It has
# to ship in the image: the platform cannot write into /usr/local/bin at session
# start, because on Kubernetes its exec runs as the non-root agent user.
COPY git/gh-aixle /usr/local/bin/gh
RUN chmod 0755 /usr/local/bin/gh

# -----------------------------------------------------------------------------
# MITM proxy for request/response logging
# -----------------------------------------------------------------------------
RUN python3 -m pip install --no-cache-dir --break-system-packages mitmproxy==11.0.2

# The interception CA is generated per container at start (logger/start-mitm.sh),
# never here: one baked into the image put its private key in every copy of a
# public image, and every agent container trusted it for every host. The system
# bundle is left appendable so that container's own CA can join it — only this
# container's processes read it.
RUN chmod 0666 /etc/ssl/certs/ca-certificates.crt

# Create fd symlink (fd-find installs as fdfind on Debian)
RUN ln -sf /usr/bin/fdfind /usr/bin/fd || true

# -----------------------------------------------------------------------------
# ttyd — the static release binary. Only its websocket server is used: the app
# renders the terminal itself with xterm.js (app/frontend/shared/ui/sessions/
# LiveTerminal.tsx), so ttyd's bundled web client never loads.
# -----------------------------------------------------------------------------
ARG TTYD_VERSION=1.7.7
ARG TTYD_SHA256_X86_64=8a217c968aba172e0dbf3f34447218dc015bc4d5e59bf51db2f2cd12b7be4f55
ARG TTYD_SHA256_AARCH64=b38acadd89d1d396a0f5649aa52c539edbad07f4bc7348b27b4f4b7219dd4165
ARG TARGETARCH
RUN case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
        amd64) arch=x86_64;  sum="${TTYD_SHA256_X86_64}" ;; \
        arm64) arch=aarch64; sum="${TTYD_SHA256_AARCH64}" ;; \
        *) echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac && \
    curl -fsSL -o /usr/local/bin/ttyd \
        "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${arch}" && \
    echo "${sum}  /usr/local/bin/ttyd" | sha256sum -c - && \
    chmod +x /usr/local/bin/ttyd && ttyd --version

COPY --from=tmux-builder /usr/local/bin/tmux /usr/local/bin/tmux
RUN tmux -V

# Helper used by tmux copy bindings (see docker/base/tmux-osc52): forwards a
# copy-mode selection to the browser clipboard via DCS-passthrough-wrapped OSC 52,
# and skips empty/whitespace-only selections so a bare click doesn't wipe the
# clipboard. allow-passthrough must be on (it is, in tmux.conf).
COPY tmux-osc52 /usr/local/bin/tmux-osc52
RUN chmod +x /usr/local/bin/tmux-osc52

# The Azure DevOps git credential helper is deliberately NOT here. The platform
# writes it into each session at clone time (AzureDevops::SessionGitSetup), so a
# checkout can never be configured to call a helper this image predates — which
# is what happened when it lived here: a five-week-old image met a newer
# platform and every push failed with "could not read Username".

# -----------------------------------------------------------------------------
# Install OpenVSCode Server from GitHub releases
# -----------------------------------------------------------------------------
ARG OPENVSCODE_VERSION=1.106.3
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then OVS_ARCH="x64"; else OVS_ARCH="arm64"; fi && \
    curl -fsSL "https://github.com/gitpod-io/openvscode-server/releases/download/openvscode-server-v${OPENVSCODE_VERSION}/openvscode-server-v${OPENVSCODE_VERSION}-linux-${OVS_ARCH}.tar.gz" | \
    tar -xz -C /opt/ && \
    mv /opt/openvscode-server-v${OPENVSCODE_VERSION}-linux-${OVS_ARCH} /opt/openvscode-server && \
    chmod -R 755 /opt/openvscode-server

# -----------------------------------------------------------------------------
# Playwright MCP + Chrome for Testing (headless browser for agent automation)
#
# Installs @playwright/mcp globally so `npx @playwright/mcp` resolves instantly.
#
# IMPORTANT — pin the MCP version. @playwright/mcp bundles its own playwright-core,
# and recent versions resolve the default Chromium browser to the
# "chrome-for-testing" CHANNEL (its executable lives inside the `chromium-<rev>`
# browser folder). If @playwright/mcp floats unpinned, a rebuild can bake one
# browser revision/channel while the version agents actually launch at runtime
# expects another — producing:
#     Error: Browser "chrome-for-testing" is not installed.
#     Run `npx @playwright/mcp install-browser chrome-for-testing` to install
# Pinning the version locks the build-time browser bake to the runtime MCP so
# the browser stays available across rebuilds (see task #340).
#
# The browser is installed with the playwright CLI bundled INSIDE the pinned
# @playwright/mcp so the revision matches by construction. We install the exact
# "chrome-for-testing" channel the MCP launches by default (not the generic
# `chrome` system channel, which would point at a non-existent system Chrome).
# Browsers stored in /opt/playwright-browsers (shared, readable by all users).
# -----------------------------------------------------------------------------
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers

# Playwright does not treat the browsers dir as read-only: at first launch it creates
# a browser-server dir inside it (`.../ms-playwright/b`), so an agent running as a
# non-root user needs write access there or every browser session dies with
#   EACCES: permission denied, mkdir '$HOME/.cache/ms-playwright/b'
#
# The access is granted by GROUP, set once in the layer that installs the browser.
# Each agent image then adds its user to this group (`useradd -G`), which is a
# constant-size operation — the old `chown -R`/`chmod -R` over the ~984 MiB tree in a
# derived image copied up every file and cost 1.03 GB per image.
ENV AGENT_BROWSERS_GROUP=agent-browsers

# Pin to the version verified against task #340. Keep in sync with
# PLAYWRIGHT_MCP_VERSION in app/services/agents/base_adapter.rb (the runtime MCP
# command is pinned to the same version so it cannot float off this baked browser).
# Bump deliberately and rebuild.
ARG PLAYWRIGHT_MCP_VERSION=0.0.78
RUN npm install -g @playwright/mcp@${PLAYWRIGHT_MCP_VERSION} && npm cache clean --force

# Browser install, trim and final permissions in ONE layer.
#
# This must stay a single instruction. A recursive chmod/chown in a separate layer
# copies up every file it touches, so the old three-layer version shipped the
# ~984 MiB browser tree three times (docs/research/technical-agent-image-size-audit-2026-08-04.md).
#
# What gets dropped, and why it is safe:
#   * chromium_headless_shell-* (340 MiB) — playwright's browsers.json marks it
#     installByDefault, but it is only launched by a CHANNEL-LESS headless
#     Chromium. Every browser session here goes through @playwright/mcp, which
#     requests the chrome-for-testing channel, i.e. the chrome binary below.
#   * libgl1-mesa-dri and Xvfb — Chrome renders WebGL via its own bundled
#     SwiftShader (libvk_swiftshader.so), never Mesa, and nothing in this repo
#     starts a virtual X server. On trixie this no longer takes LLVM with it:
#     libgbm1, which Chrome links, depends on mesa-libgallium, which keeps
#     libllvm19 + libz3-4 (~180 MiB) installed.
#   * CJK/Thai fallback fonts — fonts-liberation + fonts-noto-color-emoji stay, so
#     Latin text and emoji still render; only CJK/Thai glyphs degrade to tofu.
# The probe below is the guard: it launches the browser exactly the way the MCP
# does, so a future Playwright bump that changes the default channel fails the
# BUILD instead of failing a live session. It runs twice — as root, and as the
# unprivileged `node` user added to AGENT_BROWSERS_GROUP — because the non-root
# path is the one that broke when the browser tree was left root-only.
COPY probe-browser.js /opt/probe-browser.js
RUN set -eux; \
    apt-get update; \
    node "$(npm root -g)/@playwright/mcp/node_modules/playwright/cli.js" install --with-deps chrome-for-testing; \
    rm -rf ${PLAYWRIGHT_BROWSERS_PATH}/chromium_headless_shell-*; \
    apt-get purge -y libgl1-mesa-dri xvfb xserver-common \
        fonts-wqy-zenhei fonts-unifont fonts-ipafont-gothic fonts-tlwg-loma-otf; \
    apt-get autoremove -y --purge; \
    CHROMIUM_BIN="$(find ${PLAYWRIGHT_BROWSERS_PATH} -name chrome -path '*/chrome-linux*' | head -1)"; \
    test -x "$CHROMIUM_BIN"; \
    echo "Found chromium at: ${CHROMIUM_BIN}"; \
    mkdir -p /opt/google/chrome; \
    ln -s "$CHROMIUM_BIN" /opt/google/chrome/chrome; \
    rm -rf ${PLAYWRIGHT_BROWSERS_PATH}/.links; \
    groupadd -g 2000 ${AGENT_BROWSERS_GROUP}; \
    chgrp -R ${AGENT_BROWSERS_GROUP} ${PLAYWRIGHT_BROWSERS_PATH}; \
    chmod -R 775 ${PLAYWRIGHT_BROWSERS_PATH}; \
    find ${PLAYWRIGHT_BROWSERS_PATH} -type d -exec chmod g+s {} +; \
    install -d -m 0777 /tmp/probe-root /tmp/probe-node; \
    PROBE_CWD=/tmp/probe-root node /opt/probe-browser.js; \
    usermod -aG ${AGENT_BROWSERS_GROUP} node; \
    su node -c "PROBE_CWD=/tmp/probe-node node /opt/probe-browser.js"; \
    npm cache clean --force; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /var/cache/debconf/*-old /tmp/* /root/.npm /root/.cache

# Make the baked browser discoverable WITHOUT relying on PLAYWRIGHT_BROWSERS_PATH
# reaching the MCP subprocess (task #340).
#
# PLAYWRIGHT_BROWSERS_PATH is set as an ENV above, so it is present in the
# container environment — but a STDIO MCP server only sees it if the launching
# agent CLI forwards the parent env to the subprocess. Claude Code forwards the
# full env, so it works there; Codex (and potentially other CLIs) spawn STDIO
# servers with a restricted environment that DROPS custom vars. With the var
# gone, playwright-core falls back to its Linux default browser location,
# $HOME/.cache/ms-playwright, where nothing is baked — producing:
#   Error: Browser "chrome-for-testing" is not installed.
#
# Symlinking that default location to the shared browser dir makes the baked
# browser resolvable under the fallback too, so Chrome launches regardless of
# whether any given CLI forwards the env var. We seed the symlink into /etc/skel
# so every derived agent image's `useradd -m <user>` copies it into that user's
# home automatically (all five agents — claude/codex/cursor/gemini/grok — create
# their user with -m), keeping this a single, DRY, forward-compatible fix.
# The symlink is copied verbatim (not dereferenced) by useradd, and a later
# `chown -R` on the home operates on the link itself (lchown), never on the
# shared target, so /opt/playwright-browsers ownership/permissions are unchanged.
RUN mkdir -p /etc/skel/.cache \
    && ln -sfn "${PLAYWRIGHT_BROWSERS_PATH}" /etc/skel/.cache/ms-playwright

# -----------------------------------------------------------------------------
# Workspace setup
# -----------------------------------------------------------------------------
RUN mkdir -p /workspace/repo /workspace/outputs /opt/watcher /opt/auth-check /opt/mitm /app \
    /var/log/mitm && chmod 777 /var/log/mitm /var/log

WORKDIR /workspace

# UTF-8 locale (required for tmux + Russian/CJK text)
ENV LANG=C.UTF-8

# Ports:
#   7681 - ttyd web terminal (the session's owner)
#   7682 - read-only ttyd (everyone else)
#   4040 - file watcher WebSocket + HTTP API / auth-check
#   4041 - pasted-image upload (owner only)
#   8443 - OpenVSCode Server (IDE)
EXPOSE 7681 7682 4040 4041 8443
