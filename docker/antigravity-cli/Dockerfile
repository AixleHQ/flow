# Antigravity CLI session image. Build from docker/: docker build -f antigravity-cli/Dockerfile .
ARG BASE_IMAGE=aixle/agent-base-core:latest
FROM ${BASE_IMAGE}

RUN useradd -m -d /home/antigravity -s /bin/bash -G ${AGENT_BROWSERS_GROUP} antigravity

ARG ANTIGRAVITY_CLI_VERSION=1.1.16
ARG TARGETARCH
RUN set -eux; \
    arch="${TARGETARCH:-amd64}"; [ "$arch" = "amd64" ] && arch=x64; \
    curl -fsSL "https://github.com/google-antigravity/antigravity-cli/releases/download/${ANTIGRAVITY_CLI_VERSION}/agy_cli_linux_${arch}.tar.gz" \
      | tar -xz -C /usr/local/bin; \
    chmod +x /usr/local/bin/agy; \
    su antigravity -c "agy --version"

COPY base/tmux.conf /etc/tmux.conf
COPY base/inputrc /etc/inputrc
COPY base/vscode-settings.json /opt/openvscode-server/default-settings.json
WORKDIR /opt/watcher
COPY base/watcher/package.json ./
RUN npm install --production && npm cache clean --force
COPY base/watcher/index.js ./
COPY base/auth-check/index.js /opt/auth-check/index.js
COPY base/logger/ /opt/mitm/
COPY antigravity-cli/auth.sh /app/antigravity-auth.sh
COPY base/entrypoint.sh /app/
RUN chmod +x /app/entrypoint.sh /app/antigravity-auth.sh /opt/mitm/*.sh && \
    chown -R antigravity:antigravity /workspace /opt/watcher /home/antigravity

WORKDIR /workspace
ENV HOME=/home/antigravity AGENT_NAME="Antigravity CLI" LANG=C.UTF-8 PATH="/home/antigravity/.local/bin:${PATH}"
ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
