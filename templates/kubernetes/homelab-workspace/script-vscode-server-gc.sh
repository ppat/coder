#!/bin/bash
set -euo pipefail

# vscode-server-gc: reclaims space under ~/.vscode-server, which VS Code
# Remote-SSH grows without bound -- interrupted downloads it never cleans up,
# superseded extension versions, server versions it no longer considers live,
# and the small CLI binaries that go with them.
#
# Every deletion is driven by a signal VS Code itself already writes to disk,
# plus one extra safety check against currently-running processes -- never by
# guessing at "newest N" from version numbers or mtimes:
#   - cli/servers/*.staging           -> interrupted download, never usable
#   - cli/servers/lru.json            -> server versions VS Code considers live
#   - code-<hash> with no matching cli/servers/Stable-<hash>  -> orphaned binary
#   - extensions/.obsolete            -> extension dirs VS Code already marked obsolete
#   - extensions/extensions.json      -> cross-check: skip if still referenced
# ~/.vscode-server/data/logs is deliberately left alone: nothing on disk marks
# a dated log directory as safe to remove, and none of the above signals cover
# it.
#
# This is template-owned rather than shipped from the operator's dotfiles
# repo: ~/.vscode-server appears the moment VS Code connects to a workspace
# whether or not dotfiles have ever been applied to it (confirmed on the
# `test` workspace, which reached ~11 GB with dotfiles never applied), so a
# cleanup script that only exists via a dotfiles deploy can't cover the case
# that motivated writing it. See configmap.tf (mounts this into the
# ConfigMap the pod reads from) and deployment.tf (mounts it into the
# workspace container at /vscode-server-gc.sh); scripts.tf's coder_script
# "vscode_server_gc" invokes it directly on its weekly cron -- no existence
# check, because the ConfigMap mount guarantees it's there whenever the pod
# is, and see that resource's comment for the silent-no-op failure mode this
# replaced.

usage() {
  cat <<'EOF'
Usage: vscode-server-gc.sh [--dry-run] [root-dir]

  --dry-run   Print what would be removed without removing anything.
  root-dir    Directory to operate on (default: $HOME/.vscode-server).
              Exists for testing against a throwaway copy; production use
              should never need to pass this.
EOF
}

dry_run=0
root=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)
      dry_run=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "Error: unknown option $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [ -n "$root" ]; then
        echo "Error: unexpected extra argument $1" >&2
        exit 1
      fi
      root="$1"
      shift
      ;;
  esac
done

root="${root:-$HOME/.vscode-server}"

if [ ! -d "$root" ]; then
  echo "no $root; nothing to do"
  exit 0
fi

# Refuse to operate on something that doesn't look like a vscode-server data
# directory, so a bad root-dir argument (or a future refactor) can't turn
# this into rm -rf of something unrelated.
if [ ! -d "$root/cli/servers" ] && [ ! -d "$root/extensions" ]; then
  echo "Error: $root doesn't look like a vscode-server directory (no cli/servers or extensions); refusing to touch it" >&2
  exit 1
fi

bytes_freed=0
count_removed=0
declare -A logically_removed

# in_use PATH: true if a running process' command line references PATH. An
# extra safety net on top of the disk-based signals below, so a stale or
# lagging lru.json/.obsolete entry can never cause us to delete something
# actually serving a live session.
in_use() {
  pgrep -f -- "$1" > /dev/null 2>&1
}

# path_gone PATH: true if PATH no longer exists, or was already removed
# earlier in this run (tracked even under --dry-run, so later steps see a
# consistent preview of the cascade rather than stale on-disk state).
path_gone() {
  [ -n "${logically_removed[$1]+x}" ] || [ ! -e "$1" ]
}

remove() {
  local path="$1" reason="$2" size
  size=$(du -sb "$path" 2> /dev/null | cut -f1) || true
  size=${size:-0}
  if [ "$dry_run" -eq 1 ]; then
    echo "[dry-run] would remove $path ($reason, $((size / 1024 / 1024)) MB)"
  else
    rm -rf -- "$path"
    echo "removed $path ($reason, $((size / 1024 / 1024)) MB)"
  fi
  logically_removed["$path"]=1
  bytes_freed=$((bytes_freed + size))
  count_removed=$((count_removed + 1))
}

echo "vscode-server-gc: scanning $root"

# --- 1. cli/servers/*.staging: interrupted downloads, never usable. -------
if [ -d "$root/cli/servers" ]; then
  for dir in "$root"/cli/servers/*.staging; do
    [ -d "$dir" ] || continue
    remove "$dir" "interrupted download (.staging)"
  done
fi

# --- 2. cli/servers/Stable-<hash>: prune anything lru.json doesn't list. --
# lru.json is VS Code's own record of which server versions it considers
# live. Skip this step entirely (fail safe) if it's missing or unparseable
# rather than guess at what's current.
lru_file="$root/cli/servers/lru.json"
if [ -d "$root/cli/servers" ] && [ -f "$lru_file" ] && jq -e . "$lru_file" > /dev/null 2>&1; then
  live=" $(jq -r '.[]' "$lru_file" | tr '\n' ' ') "
  for dir in "$root"/cli/servers/Stable-*; do
    [ -d "$dir" ] || continue
    case "$dir" in *.staging) continue ;; esac
    name=$(basename "$dir")
    case "$live" in
      *" $name "*) continue ;;
    esac
    if in_use "$dir"; then
      echo "skipping $dir: not in lru.json but a running process references it"
      continue
    fi
    remove "$dir" "not in lru.json"
  done
elif [ -d "$root/cli/servers" ]; then
  echo "skipping server-version prune: $lru_file missing or not valid JSON"
fi

# --- 3. code-<hash> binaries orphaned by a removed server directory. ------
shopt -s nullglob
for bin in "$root"/code-*; do
  if [ ! -f "$bin" ] || [ ! -x "$bin" ]; then
    continue
  fi
  hash="${bin##*/code-}"
  case "$hash" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
    *) continue ;; # not a code-<40-hex-hash> binary; leave it alone
  esac
  if ! path_gone "$root/cli/servers/Stable-$hash"; then
    continue
  fi
  if in_use "$bin"; then
    echo "skipping $bin: no matching server directory but a running process references it"
    continue
  fi
  remove "$bin" "no matching cli/servers/Stable-$hash"
done
shopt -u nullglob

# --- 4. extensions/: obsolete versions per .obsolete, unless extensions.json still references them. ---
obsolete_file="$root/extensions/.obsolete"
extensions_json="$root/extensions/extensions.json"
if [ -d "$root/extensions" ] && [ -f "$obsolete_file" ] && jq -e . "$obsolete_file" > /dev/null 2>&1; then
  in_use_locations=""
  if [ -f "$extensions_json" ] && jq -e . "$extensions_json" > /dev/null 2>&1; then
    in_use_locations=" $(jq -r '.[].relativeLocation' "$extensions_json" | tr '\n' ' ') "
  fi
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    dir="$root/extensions/$name"
    [ -d "$dir" ] || continue
    case "$in_use_locations" in
      *" $name "*)
        echo "skipping $dir: marked obsolete but extensions.json still references it"
        continue
        ;;
    esac
    remove "$dir" "marked obsolete in extensions/.obsolete"
  done < <(jq -r 'keys[]' "$obsolete_file")
elif [ -d "$root/extensions" ]; then
  echo "skipping obsolete-extension prune: $obsolete_file missing or not valid JSON"
fi

summary="vscode-server-gc: done. removed $count_removed item(s), freed $((bytes_freed / 1024 / 1024)) MB"
if [ "$dry_run" -eq 1 ]; then
  summary="$summary (dry-run, nothing actually deleted)"
fi
echo "$summary"
