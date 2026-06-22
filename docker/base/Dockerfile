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
#   - Common development tools (pipx for Python MCP servers, e.g. pipx run analytics-mcp)
# =============================================================================
FROM node:22-slim

# -----------------------------------------------------------------------------
# System dependencies
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
    p7zip-full \
    xz-utils \
    bzip2 \
    zstd \
    # Process management
    tini \
    sudo \
    # Build tools (for native npm modules)
    python3 \
    python3-pip \
    pipx \
    make \
    g++ \
    # ttyd runtime libs (binary built from main in the ttyd-builder stage).
    # ttyd uses the libuv event loop, which libwebsockets loads at runtime via a
    # separate plugin package (libwebsockets-evlib-uv) — without it ttyd dies with
    # "unable to load evlib plugin evlib_uv / libwebsockets context creation failed".
    libjson-c5 \
    libuv1 \
    libwebsockets17 \
    libwebsockets-evlib-uv

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
# Playwright MCP + Chromium (headless browser for agent automation)
#
# Installs @playwright/mcp globally so `npx @playwright/mcp` resolves instantly.
# Chromium is installed using the playwright CLI bundled INSIDE @playwright/mcp
# to ensure the browser revision exactly matches what the MCP expects at runtime.
# Using a mismatched playwright version (e.g. the global `npx playwright`) would
# install the wrong chromium revision, causing EACCES errors when the MCP tries
# to download the correct revision into the root-owned /opt/playwright-browsers/.
# Browsers stored in /opt/playwright-browsers (shared, readable by all users).
# -----------------------------------------------------------------------------
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers

RUN npm install -g @playwright/mcp

RUN apt-get update \
    && node $(npm root -g)/@playwright/mcp/node_modules/playwright/cli.js install --with-deps chromium \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN CHROMIUM_BIN=$(find ${PLAYWRIGHT_BROWSERS_PATH} -name "chrome" -path "*/chrome-linux*" | head -1) \
    && echo "Found chromium at: ${CHROMIUM_BIN}" \
    && mkdir -p /opt/google/chrome \
    && ln -s "$CHROMIUM_BIN" /opt/google/chrome/chrome \
    && rm -rf ${PLAYWRIGHT_BROWSERS_PATH}/.links \
    && chmod -R 755 ${PLAYWRIGHT_BROWSERS_PATH} \
    && npm cache clean --force \
    && rm -rf /tmp/*

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
