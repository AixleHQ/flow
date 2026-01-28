# =============================================================================
# Base Image for AI Coding Agents
#
# Components:
#   - Node.js 22 (Debian slim for glibc compatibility)
#   - ttyd (web terminal)
#   - File watcher service (WebSocket streaming)
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
# File Watcher dependencies
# -----------------------------------------------------------------------------
WORKDIR /opt/watcher
COPY watcher/package.json ./
RUN npm install --production && npm cache clean --force

# Copy watcher source
COPY watcher/index.js ./

# -----------------------------------------------------------------------------
# MITM logger script
# -----------------------------------------------------------------------------
COPY logger/mitm_logger.py /opt/mitm/
COPY logger/start-mitm.sh /opt/mitm/
RUN chmod +x /opt/mitm/start-mitm.sh

# -----------------------------------------------------------------------------
# Workspace setup
# -----------------------------------------------------------------------------
RUN mkdir -p /workspace/repo /workspace/output

WORKDIR /workspace

# Ports:
#   7681 - ttyd web terminal
#   4040 - file watcher WebSocket + HTTP API
#   8888 - MITM proxy (internal)
EXPOSE 7681 4040
