# Docker image for interactive Claude Code sessions
FROM node:20-slim

# System tools for code analysis
RUN apt-get update && apt-get install -y \
    git \
    ripgrep \
    fd-find \
    jq \
    curl \
    tree \
    bash-completion \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Create workspace structure
RUN mkdir -p /workspace/repo /workspace/context /workspace/output /workspace/.claude

# Copy entrypoint and prompts
COPY entrypoint.sh /app/
COPY prompts/ /prompts/
RUN chmod +x /app/entrypoint.sh

# Set working directory
WORKDIR /workspace

# Default shell
SHELL ["/bin/bash", "-c"]

ENTRYPOINT ["/app/entrypoint.sh"]
