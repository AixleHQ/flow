# =============================================================================
# Claude Code Interactive Session Image
#
# Components:
#   - Claude Code CLI (official installer)
#   - ttyd (web terminal)
#   - File watcher service (WebSocket streaming)
# =============================================================================
FROM node:22-alpine

# -----------------------------------------------------------------------------
# System dependencies
# -----------------------------------------------------------------------------
RUN apk add --no-cache \
    # Terminal & shell
    bash \
    bash-completion \
    # ttyd for web terminal
    ttyd \
    # Development tools
    git \
    ripgrep \
    fd \
    jq \
    curl \
    tree \
    # Process management
    tini \
    # Build tools (for native npm modules)
    python3 \
    make \
    g++ \
    && rm -rf /var/cache/apk/*

# -----------------------------------------------------------------------------
# Claude Code CLI
# -----------------------------------------------------------------------------
RUN npm install -g @anthropic-ai/claude-code

# -----------------------------------------------------------------------------
# File Watcher dependencies
# -----------------------------------------------------------------------------
WORKDIR /opt/watcher
COPY watcher/package.json ./
RUN npm install --production && npm cache clean --force

# Copy watcher source
COPY watcher/index.js ./

# -----------------------------------------------------------------------------
# Workspace setup
# -----------------------------------------------------------------------------
RUN mkdir -p /workspace/repo /workspace/output

# Create non-root user
RUN adduser -D -h /home/claude -s /bin/bash claude \
    && chown -R claude:claude /workspace /opt/watcher

# -----------------------------------------------------------------------------
# Claude Code managed settings (forces console/API key auth, no login prompts)
# -----------------------------------------------------------------------------
COPY config/claude-code/managed-settings.json /etc/claude-code/managed-settings.json

# Default .claude.json (theme + onboarding state)
COPY config/.claude.json /home/claude/.claude.json
RUN mkdir -p /home/claude/.claude \
    && chown -R claude:claude /home/claude

# -----------------------------------------------------------------------------
# Configuration & entrypoint
# -----------------------------------------------------------------------------
COPY prompts/ /prompts/
COPY entrypoint.sh /app/
RUN chmod +x /app/entrypoint.sh

WORKDIR /workspace

# Ports:
#   7681 - ttyd web terminal
#   4040 - file watcher WebSocket + HTTP API
EXPOSE 7681 4040

# Use tini as init system for proper signal handling
ENTRYPOINT ["/sbin/tini", "--", "/app/entrypoint.sh"]
