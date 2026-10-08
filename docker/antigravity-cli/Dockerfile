# Antigravity CLI session image. Build from docker/: docker build -f antigravity-cli/Dockerfile .
ARG BASE_IMAGE=aixle/agent-base-core:latest
FROM ${BASE_IMAGE}

RUN useradd -m -d /home/antigravity -s /bin/bash -G ${AGENT_BROWSERS_GROUP} antigravity

ARG TARGETARCH
# The checksums are per release: raising the pin in config/agent_runtimes.json without
# adding the new release's pair here fails the build at the case below.
ARG CLI_VERSION
RUN set -eux; \
    : "${CLI_VERSION:?pinned in config/agent_runtimes.json; build with make build-agents}"; \
    arch="${TARGETARCH:-amd64}"; [ "$arch" = "amd64" ] && arch=x64; \
    case "${CLI_VERSION}/$arch" in \
      1.1.27/x64) sha256="f874d4f6b8a73c2df660f580f25fb656fcb6e64adbfd746e6692e837fd9a20be" ;; \
      1.1.27/arm64) sha256="97fc9fe5a6067406cd02cbe4ae6e362c9623a24d33bec486911246c17ceb6a94" ;; \
      *) echo "No checksum for agy ${CLI_VERSION} on $arch: add it to docker/antigravity-cli/Dockerfile" >&2; exit 1 ;; \
    esac; \
    archive=/tmp/agy.tar.gz; \
    curl -fsSL "https://github.com/google-antigravity/antigravity-cli/releases/download/${CLI_VERSION}/agy_cli_linux_${arch}.tar.gz" -o "$archive"; \
    echo "$sha256  $archive" | sha256sum -c -; \
    tar -xzf "$archive" -C /usr/local/bin; \
    rm "$archive"; \
    mv /usr/local/bin/antigravity /usr/local/bin/agy; \
    chmod +x /usr/local/bin/agy; \
    test "$(su antigravity -c 'agy --version')" = "$CLI_VERSION"

# The CLI version this image actually shipped with, recorded where anything can read it:
# `docker run <image> cat /etc/aixle-cli-version`. The canary builds the vendor's newest
# release instead of the pin, so the version is not always the one the registry names.
RUN su antigravity -c 'agy --version' > /etc/aixle-cli-version

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
    chown -R antigravity:antigravity /workspace /home/antigravity

WORKDIR /workspace
ENV HOME=/home/antigravity AGENT_NAME="Antigravity CLI" LANG=C.UTF-8 PATH="/home/antigravity/.local/bin:${PATH}"
ENTRYPOINT ["/usr/bin/tini", "--", "/app/entrypoint.sh"]
