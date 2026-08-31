#!/usr/bin/env bash
set -euo pipefail

read -r -s -p "Google AI Studio API key: " api_key
printf '\n'
if [[ -z "$api_key" ]]; then
  echo "API key cannot be empty" >&2
  exit 1
fi
mkdir -p "$HOME/.gemini/antigravity-cli"
python3 -c 'import json,sys; print(json.dumps({"api_key": sys.argv[1]}))' "$api_key" > "$HOME/.gemini/antigravity-cli/aixle-api-key.json"
chmod 600 "$HOME/.gemini/antigravity-cli/aixle-api-key.json"
echo "Antigravity CLI connected. You can close this session."
