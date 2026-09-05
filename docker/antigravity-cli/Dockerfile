# Antigravity CLI session image. Build from docker/: docker build -f antigravity-cli/Dockerfile .
ARG BASE_IMAGE=aixle/agent-base-core:latest
FROM ${BASE_IMAGE}

RUN useradd -m -d /home/antigravity -s /bin/bash -G ${AGENT_BROWSERS_GROUP} antigravity

ARG TARGETARCH
ARG ANTIGRAVITY_CLI_VERSION=1.1.27
RUN set -eux; \
    arch="${TARGETARCH:-amd64}"; [ "$arch" = "amd64" ] && arch=x64; \
    case "$arch" in \
      x64) sha256="f874d4f6b8a73c2df660f580f25fb656fcb6e64adbfd746e6692e837fd9a20be" ;; \
      arm64) sha256="97fc9fe5a6067406cd02cbe4ae6e362c9623a24d33bec486911246c17ceb6a94" ;; \
      *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    archive=/tmp/agy.tar.gz; \
    curl -fsSL "https://github.com/google-antigravity/antigravity-cli/releases/download/${ANTIGRAVITY_CLI_VERSION}/agy_cli_linux_${arch}.tar.gz" -o "$archive"; \
    echo "$sha256  $archive" | sha256sum -c -; \
    tar -xzf "$archive" -C /usr/local/bin; \
    rm "$archive"; \
    mv /usr/local/bin/antigravity /usr/local/bin/agy; \
    chmod +x /usr/local/bin/agy; \
    test "$(su antigravity -c 'agy --version')" = "$ANTIGRAVITY_CLI_VERSION"

COPY base/tmux.conf /etc/tmux.conf
COPY base/inputrc /etc/inputrc
COPY base/vscode-settings.json /opt/openvscode-server/default-settings.json
WORKDIR /opt/watcher
COPY base/watcher/package.json ./
RUN npm install --production && npm cache clean --force
COPY base/watcher/index.js ./
COPY base/auth-check/index.js /opt/auth-check/index.js
COPY base/logger/ /opt/mitm/
COPY base/entrypoint.sh /app/
RUN chmod +x /app/entrypoint.sh /opt/mitm/*.sh && \
    chown -R antigravity:antigravity /workspace /opt/watcher /home/antigravity

WORKDIR /workspace
ENV HOME=/home/antigravity AGENT_NAME="Antigravity CLI" LANG=C.UTF-8 PATH="/home/antigravity/.local/bin:${PATH}"
ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
