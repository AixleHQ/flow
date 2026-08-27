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

# The application image freezes Bundler so production builds cannot drift from
# Gemfile.lock. Ruby LSP generates .ruby-lsp/Gemfile at development time and
# needs to resolve its own added gems, so unfreeze Bundler only in the created
# devcontainer. Production containers never run this setup script.
bundle config set --local frozen false

# docker cli
apk add --no-cache docker docker-cli-compose unzip

echo "Installed docker $(docker --version)"
echo "Installed docker-compose $(docker-compose --version)"
