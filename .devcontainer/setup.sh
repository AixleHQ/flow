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

ensure_persistent_home_state() {
  local claude_state_dir=/root/.claude-state
  local claude_json="${claude_state_dir}/.claude.json"

  mkdir -p /root/.claude "${claude_state_dir}"

  if [[ -f /root/.claude.json && ! -L /root/.claude.json && ! -f "${claude_json}" ]]; then
    mv /root/.claude.json "${claude_json}"
  fi

  touch "${claude_json}"
  ln -sfn "${claude_json}" /root/.claude.json

  chmod 700 /root/.claude 2>/dev/null || true
  chmod 700 "${claude_state_dir}" 2>/dev/null || true
  chmod 600 "${claude_json}" 2>/dev/null || true

  echo "Claude auth state is persisted through /root/.claude and /root/.claude-state/.claude.json"
}

ensure_persistent_home_state

# docker cli
apk add --no-cache docker docker-cli-compose unzip

echo "Installed docker $(docker --version)"
echo "Installed docker-compose $(docker-compose --version)"
