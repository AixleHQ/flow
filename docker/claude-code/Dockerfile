# =============================================================================
# Claude Code Interactive Session Image
#
# Build context: docker/ (parent dir, for access to base/ scripts)
# Build command: docker build -f claude-code/Dockerfile -t aixle/claude-code:latest .
# =============================================================================
ARG BASE_IMAGE=aixle/agent-base-core:latest
FROM ${BASE_IMAGE}

# =============================================================================
# Agent-specific layers (CACHED when only shared scripts change)
# =============================================================================
# Browser access comes from the group membership (-G), NOT from re-owning
# /opt/playwright-browsers: the base image already made that tree group-writable for
# AGENT_BROWSERS_GROUP. A `chown -R`/`chmod -R` over those ~984 MiB here copied up
# every file and added 1.03 GB to this image alone
# (docs/research/technical-agent-image-size-audit-2026-08-04.md).
RUN useradd -m -d /home/claude -s /bin/bash -G ${AGENT_BROWSERS_GROUP} claude \
    && chown -R claude:claude /workspace /home/claude

USER claude
WORKDIR /home/claude
ARG CLAUDE_CODE_VERSION=2.1.251
# Download THEN run, and verify the binary — never `curl … | bash`. In a pipe, a failed
# curl still leaves bash reading empty stdin and exiting 0, so a network blip produced an
# image with no Claude CLI at all and the build reported success (seen 2026-08-05).
RUN curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh \
    && bash /tmp/claude-install.sh "${CLAUDE_CODE_VERSION}" \
    && rm -f /tmp/claude-install.sh \
    && test -x /home/claude/.local/bin/claude \
    && /home/claude/.local/bin/claude --version | grep -qF "${CLAUDE_CODE_VERSION}"

ENV PATH="/home/claude/.local/bin:${PATH}"

USER root

# -----------------------------------------------------------------------------
# AWS CLI v2 — for Amazon Bedrock connections (diagnostics, and the fallback
# in-container Identity Center login). Deliberately placed AFTER the Claude
# install layer so that expensive layer stays cached; putting it in
# docker/base/Dockerfile instead would invalidate all four agent images.
#
# Version floor matters: [sso-session] needs >=2.9, but a headless container
# needs >=2.22 for `aws sso login --use-device-code`. PKCE is the default from
# 2.22 and cannot work here — its callback URL must open on the machine running
# the CLI. Pair the flag with --no-browser or the autofill URL is swallowed by a
# failed browser launch and never printed.
# -----------------------------------------------------------------------------
ARG AWSCLI_VERSION=2.33.29
RUN set -eux; \
    case "$(uname -m)" in \
      x86_64) awscli_arch=x86_64 ;; \
      aarch64|arm64) awscli_arch=aarch64 ;; \
      *) echo "unsupported arch for AWS CLI: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${awscli_arch}-${AWSCLI_VERSION}.zip" -o /tmp/awscliv2.zip; \
    unzip -q /tmp/awscliv2.zip -d /tmp; \
    /tmp/aws/install; \
    rm -rf /tmp/awscliv2.zip /tmp/aws; \
    aws --version

# .aws must exist and be agent-owned: the Bedrock setup wizard reads the profile
# from the literal $HOME/.aws/config (it ignores AWS_CONFIG_FILE), and an SSO
# login has to create ~/.aws/sso/cache/ next to it.
#
# `install -d` creates just these two dirs with the right owner. A `chown -R` over
# /home/claude would be a no-op (the CLI above was installed AS claude) that still
# copied up the whole 272 MB install into this layer.
RUN install -d -o claude -g claude /home/claude/.claude /home/claude/.aws

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

# AWS SDK credential_process helper — the container's only route to cloud credentials.
COPY base/cloud/aixle-aws-creds /usr/local/bin/aixle-aws-creds
RUN chmod +x /usr/local/bin/aixle-aws-creds

COPY base/auth-check/index.js /opt/auth-check/index.js
COPY base/logger/ /opt/mitm/
RUN chmod +x /opt/mitm/*.sh

COPY base/entrypoint.sh /app/
RUN chmod +x /app/entrypoint.sh

RUN printf '%s\n' \
        '# Full passwordless sudo for the agent user (trusted environments only).' \
        'claude ALL=(root) NOPASSWD: ALL' \
        > /etc/sudoers.d/claude-agent \
    && chmod 440 /etc/sudoers.d/claude-agent \
    && visudo -cf /etc/sudoers.d/claude-agent

# =============================================================================
# Final setup
# =============================================================================
RUN chown -R claude:claude /opt/watcher

WORKDIR /workspace
ENV HOME=/home/claude \
    AGENT_NAME="Claude Code" \
    LANG=C.UTF-8

# Run as non-root user (required for --dangerously-skip-permissions)
USER claude

ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
