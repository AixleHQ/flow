#!/bin/bash
# Builds a suspended session's checkpoint inside its container and uploads it.
# Sessions::Checkpoint runs it as `bash -c <this file> aixle-checkpoint <options>`.
# Design: docs/design/session-suspend-restore.md §4.
#
#   --url <url>                      where the archive is PUT
#   --max-bytes <n>                  the largest archive; /workspace is dropped first
#   --upload-timeout <seconds>
#   --workspace <dir>                archived without the --exclude patterns
#   --home <dir>                     the CLI's home
#   --conversation-id-command <sh>   prints the conversation's id, run in --home
#   --conversation <path>            repeated: the CLI's conversation files, under --home
#   --repo <key> <path>              repeated: a checkout whose work is saved
#   --exclude <pattern>              repeated
#
# Prints tab-separated lines, read by Sessions::Checkpoint:
#   REPO <key> ok <branch> <head> <on remote> <dirty> <bundle> <patch> <untracked>
#   REPO <key> missing
#   CONVERSATION <id>
#   ARCHIVE <bytes> <workspace included 0|1>
#   TOO_LARGE <bytes> (exit 3), UPLOAD_FAILED (exit 4)
set -u

url='' max_bytes='' upload_timeout='' workspace='' home='' conversation_id_command=true
conversations=() repos=() excludes=()
while [ $# -gt 0 ]; do
  case $1 in
    --url) url=$2; shift 2 ;;
    --max-bytes) max_bytes=$2; shift 2 ;;
    --upload-timeout) upload_timeout=$2; shift 2 ;;
    --workspace) workspace=$2; shift 2 ;;
    --home) home=$2; shift 2 ;;
    --conversation-id-command) conversation_id_command=$2; shift 2 ;;
    --conversation) conversations+=("$2"); shift 2 ;;
    --repo) repos+=("$2" "$3"); shift 3 ;;
    --exclude) excludes+=("--exclude=$2"); shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 64 ;;
  esac
done

D=$(mktemp -d /tmp/.aixle-checkpoint.XXXXXX) || exit 70
trap 'rm -rf "$D" "$D.tgz"' EXIT

g() { git -c safe.directory='*' "$@"; }
flag() { [ -e "$1" ] && echo 1 || echo 0; }

save_repo() {
  local key=$1 path=$2 out="$D/repos/$1" branch head on_remote dirty
  if [ ! -d "$path/.git" ]; then printf 'REPO\t%s\tmissing\n' "$key"; return; fi
  mkdir -p "$out"; cd "$path" || return
  branch=$(g symbolic-ref -q --short HEAD || true)
  head=$(g rev-parse -q --verify HEAD || true)
  on_remote=false
  if [ -n "$branch" ] && timeout 30 git -c safe.directory='*' ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then on_remote=true; fi
  dirty=false; [ -n "$(g status --porcelain 2>/dev/null)" ] && dirty=true
  g bundle create "$out/head.bundle" --branches --not --remotes >/dev/null 2>&1 || rm -f "$out/head.bundle"
  g diff --binary HEAD > "$out/tracked.patch" 2>/dev/null; [ -s "$out/tracked.patch" ] || rm -f "$out/tracked.patch"
  g ls-files -z --others --exclude-standard > "$out/.untracked" 2>/dev/null
  if [ -s "$out/.untracked" ]; then tar --null -T "$out/.untracked" -cf "$out/untracked.tar" 2>/dev/null || rm -f "$out/untracked.tar"; fi
  rm -f "$out/.untracked"
  printf 'REPO\t%s\tok\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$key" "$branch" "$head" "$on_remote" "$dirty" \
    "$(flag "$out/head.bundle")" "$(flag "$out/tracked.patch")" "$(flag "$out/untracked.tar")"
}

mkdir -p "$D/repos"
for ((i = 0; i < ${#repos[@]}; i += 2)); do save_repo "${repos[i]}" "${repos[i + 1]}"; done

if cd "$home"; then
  printf 'CONVERSATION\t%s\n' "$( { eval "$conversation_id_command"; } 2>/dev/null | head -1)"
  existing=()
  for p in "${conversations[@]}"; do [ -e "$p" ] && existing+=("$p"); done
  if [ ${#existing[@]} -gt 0 ]; then
    tar -cf "$D/conversation.tar" "${existing[@]}" 2>/dev/null
    [ $? -le 1 ] || rm -f "$D/conversation.tar"
  fi
fi

# tar exits 1 when a file changed while it was read: the archive is still usable.
tar -C "$workspace" -cf "$D/workspace.tar" "${excludes[@]}" . 2>/dev/null
[ $? -le 1 ] || rm -f "$D/workspace.tar"

pack() { rm -f "$D.tgz"; tar -C "$D" -czf "$D.tgz" "$@"; }
items=(repos); [ -f "$D/conversation.tar" ] && items+=(conversation.tar)
included=0
if [ -f "$D/workspace.tar" ] && pack "${items[@]}" workspace.tar && [ "$(stat -c %s "$D.tgz")" -le "$max_bytes" ]; then
  included=1
else
  pack "${items[@]}"
fi
size=$(stat -c %s "$D.tgz")
if [ "$size" -gt "$max_bytes" ]; then printf 'TOO_LARGE\t%s\n' "$size"; exit 3; fi
if ! curl -sS --noproxy '*' --fail --max-time "$upload_timeout" -X PUT -T "$D.tgz" "$url" >/dev/null; then
  echo UPLOAD_FAILED; exit 4
fi
printf 'ARCHIVE\t%s\t%s\n' "$size" "$included"
