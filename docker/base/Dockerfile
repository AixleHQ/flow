# =============================================================================
# Base Image for AI Coding Agents
#
# Components:
#   - Node.js 22 (Debian slim for glibc compatibility)
#   - ttyd (web terminal)
#   - OpenVSCode Server (browser IDE)
#   - File watcher service (WebSocket streaming, auth_setup only)
#   - Auth-check service (auth_setup only)
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
    ca-certificates \
    # Process management
    tini \
    # Build tools (for native npm modules)
    python3 \
    python3-pip \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

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

# Pre-seed VS Code settings (Palad dark theme with brand colors)
COPY vscode-settings.json /opt/openvscode-server/default-settings.json

# -----------------------------------------------------------------------------
# File Watcher dependencies
# -----------------------------------------------------------------------------
WORKDIR /opt/watcher
COPY watcher/package.json ./
RUN npm install --production && npm cache clean --force

# Copy watcher source
COPY watcher/index.js ./

# -----------------------------------------------------------------------------
# Auth Check — lightweight standalone service for auth_setup sessions
# -----------------------------------------------------------------------------
COPY auth-check/index.js /opt/auth-check/index.js

# -----------------------------------------------------------------------------
# MITM logger script
# -----------------------------------------------------------------------------
COPY logger/mitm_logger.py /opt/mitm/
COPY logger/http2-logger.js /opt/mitm/
COPY logger/start-mitm.sh /opt/mitm/
RUN chmod +x /opt/mitm/start-mitm.sh

# -----------------------------------------------------------------------------
# Shell comfort: readline config for web terminal (ttyd)
# -----------------------------------------------------------------------------
COPY inputrc /etc/inputrc

# -----------------------------------------------------------------------------
# tmux config: session persistence for web terminal
# Keeps command alive across browser reconnects, provides scrollback history
# -----------------------------------------------------------------------------
RUN printf '%s\n' \
    'set -g history-limit 50000' \
    'set -g remain-on-exit on' \
    'set -g status off' \
    'set -g set-clipboard on' \
    'set -g allow-passthrough on' \
    > /etc/tmux.conf

# -----------------------------------------------------------------------------
# UTF-8 locale (required for tmux + Russian/CJK text)
# -----------------------------------------------------------------------------
ENV LANG=C.UTF-8

# -----------------------------------------------------------------------------
# Shared entrypoint (agents customize via ENV vars)
# -----------------------------------------------------------------------------
COPY entrypoint.sh /app/
RUN chmod +x /app/entrypoint.sh

# -----------------------------------------------------------------------------
# Workspace setup
# -----------------------------------------------------------------------------
RUN mkdir -p /workspace/repo /workspace/outputs

WORKDIR /workspace

# Ports:
#   7681 - ttyd web terminal
#   4040 - file watcher WebSocket + HTTP API
#   8443 - OpenVSCode Server (IDE)
#   8888 - MITM proxy (internal)
EXPOSE 7681 4040 8443

ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
