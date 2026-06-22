#!/usr/bin/env bash
set -euo pipefail

ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *)
    echo "Unsupported architecture: ${ARCH}" >&2
    exit 1
    ;;
esac

OS=linux

# docker cli
apk add --no-cache docker docker-cli-compose unzip

echo "Installed docker $(docker --version)"
echo "Installed docker-compose $(docker-compose --version)"
