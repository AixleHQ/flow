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
#   - Common development tools
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
    # Archive extraction (tar/gzip already in base image)
    unzip \
    p7zip-full \
    xz-utils \
    bzip2 \
    zstd \
    # Process management
    tini \
    # Build tools (for native npm modules)
    python3 \
    python3-pip \
    make \
    g++

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

# Create fd symlink (fd-find installs as fdfind on Debian)
RUN ln -sf /usr/bin/fdfind /usr/bin/fd || true

# -----------------------------------------------------------------------------
# Install ttyd from GitHub releases (not in Debian repos)
# -----------------------------------------------------------------------------
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then TTYD_ARCH="x86_64"; else TTYD_ARCH="aarch64"; fi && \
    curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.${TTYD_ARCH}" -o /usr/local/bin/ttyd && \
    chmod +x /usr/local/bin/ttyd

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
# Chromium binary + system deps are installed via `npx playwright install`.
# Browsers stored in /opt/playwright-browsers (shared, readable by all users).
# -----------------------------------------------------------------------------
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers

RUN npm install -g @playwright/mcp

RUN apt-get update \
    && npx playwright install --with-deps chromium \
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
