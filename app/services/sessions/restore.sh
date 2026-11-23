#!/bin/bash
# Puts a checkpoint (checkpoint.sh) back into the session that continues it, after
# provisioning and before the CLI starts. Sessions::Restore runs it as
# `bash -c <this file> aixle-restore <options>`. Design: docs/design/session-suspend-restore.md §5.
#
#   --url <url>                     the archive
#   --download-timeout <seconds>
#   --workspace <dir>               the archived workspace is unpacked over it
#   --home <dir>                    the CLI's home, for its conversation files
#   --leftovers <dir>               where a bundle or patch that does not apply is left
#   --repo <key> <path> <branch> <head> <on remote>
#                                   repeated: a checkout to put its saved work back into
#
# Prints tab-separated lines, read by Sessions::Restore:
#   WORKSPACE_OK, CONVERSATION_OK
#   REPO <key> <ok|missing|bundle_failed|head_missing|patch_failed|untracked_failed>
#   DOWNLOAD_FAILED (exit 5), UNPACK_FAILED (exit 6)
set -u

url='' download_timeout='' workspace='' home='' leftovers=''
repos=()
while [ $# -gt 0 ]; do
  case $1 in
    --url) url=$2; shift 2 ;;
    --download-timeout) download_timeout=$2; shift 2 ;;
    --workspace) workspace=$2; shift 2 ;;
    --home) home=$2; shift 2 ;;
    --leftovers) leftovers=$2; shift 2 ;;
    --repo) repos+=("$2" "$3" "$4" "$5" "$6"); shift 6 ;;
    *) echo "unknown option: $1" >&2; exit 64 ;;
  esac
done

D=$(mktemp -d /tmp/.aixle-restore.XXXXXX) || exit 70
trap 'rm -rf "$D"' EXIT

if ! curl -sS --noproxy '*' --fail --max-time "$download_timeout" -o "$D/archive.tgz" "$url"; then
  echo DOWNLOAD_FAILED; exit 5
fi
tar -C "$D" -xzf "$D/archive.tgz" || { echo UNPACK_FAILED; exit 6; }
if [ -f "$D/workspace.tar" ]; then tar -C "$workspace" -xf "$D/workspace.tar" 2>/dev/null; echo WORKSPACE_OK; fi
if [ -f "$D/conversation.tar" ] && tar -C "$home" -xf "$D/conversation.tar" 2>/dev/null; then echo CONVERSATION_OK; fi

g() { git -c safe.directory='*' "$@"; }

restore_repo() {
  local key=$1 path=$2 branch=$3 head=$4 on_remote=$5 src="$D/repos/$1" status=ok
  if [ ! -d "$path/.git" ]; then printf 'REPO\t%s\tmissing\n' "$key"; return; fi
  cd "$path" || return
  if [ -n "$branch" ] && [ "$on_remote" = true ]; then g fetch -q origin "$branch" >/dev/null 2>&1 || true; fi
  # A fetch into refs/heads/* refuses to update the checked-out branch.
  g checkout -q --detach 2>/dev/null
  if [ -f "$src/head.bundle" ] && ! g fetch -q "$src/head.bundle" 'refs/heads/*:refs/heads/*' >/dev/null 2>&1; then
    cp "$src/head.bundle" "$leftovers/$key.bundle"; status=bundle_failed
  fi
  if [ -n "$branch" ]; then
    if g rev-parse -q --verify "refs/heads/$branch" >/dev/null; then g checkout -q -f "$branch"
    elif g rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null; then g checkout -q -f -B "$branch" "origin/$branch"; fi
  fi
  if [ -n "$head" ]; then
    if g cat-file -e "$head^{commit}" 2>/dev/null; then g reset -q --hard "$head"; elif [ "$status" = ok ]; then status=head_missing; fi
  fi
  if [ -f "$src/tracked.patch" ] && ! g apply --binary "$src/tracked.patch" 2>/dev/null; then
    cp "$src/tracked.patch" "$leftovers/$key.patch"; [ "$status" = ok ] && status=patch_failed
  fi
  if [ -f "$src/untracked.tar" ] && ! tar -xf "$src/untracked.tar" 2>/dev/null; then [ "$status" = ok ] && status=untracked_failed; fi
  printf 'REPO\t%s\t%s\n' "$key" "$status"
}

mkdir -p "$leftovers"
for ((i = 0; i < ${#repos[@]}; i += 5)); do
  restore_repo "${repos[i]}" "${repos[i + 1]}" "${repos[i + 2]}" "${repos[i + 3]}" "${repos[i + 4]}"
done
rmdir "$leftovers" 2>/dev/null || true
exit 0
