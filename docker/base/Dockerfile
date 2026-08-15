# uv / uvx (Astral), pulled in as a stage so the version stays a single pinned
# ARG. `COPY --from=<image>` does NOT expand build args — BuildKit rejects it
# outright — so a named stage is the only way to keep the tag in one place.
ARG UV_VERSION=0.9.29
FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

# =============================================================================
# ttyd builder — build from main (pinned SHA), NOT the 1.7.7 release.
#
# The 1.7.7 release bundles xterm.js 5.4 with NO clipboard addon, so the web
# terminal silently ignores OSC 52 and the browser clipboard never receives
# "c to copy" — which breaks copying the long Claude Code OAuth login URL.
# The xterm clipboard addon was merged to ttyd main on 2024-11-26 but has never
# been released. We pin a commit for reproducibility. (Also requires the iframe
# to carry allow="clipboard-write" and tmux `allow-passthrough on`.)
# =============================================================================
FROM node:22-slim AS ttyd-builder
ARG TTYD_REF=647d55ad865f5ad85ad89ba5e1b28d9b6ac8fd55
RUN apt-get update && apt-get install -y --no-install-recommends \
        git ca-certificates build-essential cmake \
        libjson-c-dev libwebsockets-dev libuv1-dev zlib1g-dev libssl-dev && \
    rm -rf /var/lib/apt/lists/*
RUN git clone https://github.com/tsl0922/ttyd.git /ttyd-src && \
    cd /ttyd-src && git checkout ${TTYD_REF}
# Patch the xterm client: copy the FULL url on click, rejoining hard-wrapped rows
# (xterm.js bug #5412 — WebLinksAddon only stitches soft-wraps; tmux/Claude emit
# hard newlines). Lets the user just click the login URL to copy it whole.
COPY patch-ttyd.js /tmp/patch-ttyd.js
RUN cd /ttyd-src && node /tmp/patch-ttyd.js
RUN cd /ttyd-src && corepack enable && \
    (cd html && yarn install --immutable && yarn run build) && \
    cmake -B build -S . && \
    cmake --build build -j"$(nproc)" && \
    strip build/ttyd

# =============================================================================
# Core Base Image for AI Coding Agents
#
# Heavy, rarely-changing dependencies only.
# Lightweight scripts (entrypoint, watcher, auth-check, logger) are added
# in each agent Dockerfile AFTER agent-specific installs, so that script
# changes don't invalidate expensive agent CLI install layers.
#
# Components:
#   - Node.js 22 (Debian slim for glibc compatibility)
#   - ttyd (web terminal)
#   - OpenVSCode Server (browser IDE)
#   - MITM proxy for request/response logging
#   - Common development tools (uv/uvx and pipx for Python MCP servers)
# =============================================================================
FROM node:22-slim

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
    tmux \
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
    # ttyd runtime libs (binary built from main in the ttyd-builder stage).
    # ttyd uses the libuv event loop, which libwebsockets loads at runtime via a
    # separate plugin package (libwebsockets-evlib-uv) — without it ttyd dies with
    # "unable to load evlib plugin evlib_uv / libwebsockets context creation failed".
    libjson-c5 \
    libuv1 \
    libwebsockets17 \
    libwebsockets-evlib-uv \
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

# -----------------------------------------------------------------------------
# MITM proxy for request/response logging
# -----------------------------------------------------------------------------
RUN python3 -m pip install --no-cache-dir --break-system-packages mitmproxy==10.2.4

# Pre-generate MITM CA so every container starts with certs already in place
# (eliminates the race between mitmdump startup and agent HTTPS requests).
RUN mkdir -p /opt/mitm/ca && \
    mitmdump --listen-port 0 -q & PID=$! && sleep 1 && kill $PID 2>/dev/null; \
    cp /root/.mitmproxy/mitmproxy-ca*.pem /root/.mitmproxy/mitmproxy-ca*.p12 \
       /root/.mitmproxy/mitmproxy-dhparam.pem /opt/mitm/ca/ && \
    cat /etc/ssl/certs/ca-certificates.crt /opt/mitm/ca/mitmproxy-ca-cert.pem \
        > /opt/mitm/ca/combined-ca-bundle.pem && \
    chmod -R 644 /opt/mitm/ca/* && \
    rm -rf /root/.mitmproxy

# Trust MITM CA in the system bundle (curl/apt/OpenSSL; may help Chromium via platform hooks).
# No runtime hook — same CA files are baked at build time.
RUN cp /opt/mitm/ca/mitmproxy-ca-cert.pem /usr/local/share/ca-certificates/mitmproxy-ca.crt \
    && update-ca-certificates

# Create fd symlink (fd-find installs as fdfind on Debian)
RUN ln -sf /usr/bin/fdfind /usr/bin/fd || true

# -----------------------------------------------------------------------------
# ttyd — copy the binary built from main in the ttyd-builder stage above.
# (main, not the 1.7.7 release, for the xterm clipboard addon → OSC 52 copy.)
# -----------------------------------------------------------------------------
COPY --from=ttyd-builder /ttyd-src/build/ttyd /usr/local/bin/ttyd
RUN chmod +x /usr/local/bin/ttyd && ttyd --version

# Helper used by tmux copy bindings (see docker/base/tmux-osc52): forwards a
# copy-mode selection to the browser clipboard via DCS-passthrough-wrapped OSC 52,
# and skips empty/whitespace-only selections so a bare click doesn't wipe the
# clipboard. allow-passthrough must be on (it is, in tmux.conf).
COPY tmux-osc52 /usr/local/bin/tmux-osc52
RUN chmod +x /usr/local/bin/tmux-osc52

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
#   * libgl1-mesa-dri + libllvm15 (~130 MiB) and Xvfb — Chrome renders WebGL via
#     its own bundled SwiftShader (libvk_swiftshader.so), never Mesa, and nothing
#     in this repo starts a virtual X server.
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
ENV LANG=C.UTF-8 \
    GIT_SSL_NO_VERIFY=1

# Ports:
#   7681 - ttyd web terminal
#   4040 - file watcher WebSocket + HTTP API / auth-check
#   8443 - OpenVSCode Server (IDE)
EXPOSE 7681 4040 8443
