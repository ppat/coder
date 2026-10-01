#!/bin/bash
set -euo pipefail

# cache-gc: keeps the tool caches under the home directory bounded, while other
# sessions in the same workspace are using those tools.
#
# The home directory is a fixed-size volume: a PVC of the size the workspace
# asked for, or an existing claim, which on the operator's deployment is an NFS
# share with a quota. When it fills, every write in the pod fails, including
# the ones that hold agent sessions' state. Go's build cache alone reached
# 201 GiB in six days on that share: Go trims only entries unused for
# five days, and a workload that builds from a fresh directory per run (Go
# hashes the package directory into every compile, unless -trimpath is set)
# writes cache entries that are never reused at ~10 GB an hour.
#
# Nothing here wipes a cache. Each cache is evicted by the signal its owning
# tool already writes, using the tool's own pruning command where one exists
# and is safe to run concurrently, and with a floor that keeps anything an
# in-flight run may still be reading:
#
#   cache                  rule                                       why it is safe mid-run
#   ---------------------  -----------------------------------------  ----------------------------------------
#   Go build cache         oldest-used first down to a cap; never     the same unlocked mtime-based removal
#   golangci-lint cache    an entry used in the last GO_FLOOR_MIN     Go's own Trim() does (see go_cache)
#   bun install cache      oldest first down to a cap, counting only  entry renamed out of bun's lookup path
#                          bytes no node_modules still hardlinks      before deletion (see bun_install_cache)
#   bun transpiler cache   files older than 14 days                   atomic write, hash-verified on read
#   npm (~/.npm)           _cacache files and _npx installs older     self-healing cache; _npx skips anything
#                          than 14 days                               a live process runs from
#   node-gyp               header dirs for Node versions no longer    skipped while any node-gyp runs
#                          installed, older than 7 days
#   Homebrew               downloads older than 30 days               never brew cleanup: it removes kegs too
#   pip                    http/wheel cache files older than 30 days  writes are tmp-then-replace
#   uv                     uv cache prune                             takes uv's own cache lock
#   mise                   mise cache prune, 7-day age                installs never reference the cache
#   pre-commit             pre-commit gc                              takes pre-commit's store lock
#
# Removing any of these costs a re-download or a rebuild, never an installed
# tool: bun and uv hardlink packages out of their caches, so node_modules and
# venvs keep their files; mise installs and Homebrew kegs live outside their
# caches; pre-commit is left to its own gc because its cache *is* the hook
# environments and a hand-deleted repo leaves a db.db row pointing at nothing.
#
# Template-owned for the reason script-vscode-server-gc.sh is: the caches fill
# whether or not dotfiles were ever applied. Mounted via configmap.tf, invoked
# hourly by scripts.tf's coder_script "cache_gc". A tool that is not installed
# is reported as skipped by name, never silently passed over, and a step that
# fails makes the run fail in the Coder UI after the remaining steps have run.

usage() {
  cat <<'EOF'
Usage: script-cache-gc.sh [--dry-run]

  --dry-run   Print what would be removed without removing anything.

Caches are found the way their tools find them: GOCACHE, GOLANGCI_LINT_CACHE,
BUN_INSTALL_CACHE_DIR and XDG_CACHE_HOME are honoured. Each default cap is
the smaller of a fixed size and a share of the cache's filesystem, so a small
home volume gets a proportionate cap. An override, in MiB of disk blocks, is
used as given:
  CACHE_GC_GO_BUILD_CAP_MIB       (default 16384, at most 25% of the filesystem)
  CACHE_GC_GOLANGCI_LINT_CAP_MIB  (default 1024, at most 5%)
  CACHE_GC_BUN_CAP_MIB            (default 4096, at most 10%)
EOF
}

dry_run=0
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
    *)
      echo "Error: unknown argument $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

# find -printf's %T@ and sort -n both follow the locale's decimal mark.
export LC_ALL=C

cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"
# Read by `mise cache prune`. Its 30-day default leaves abandoned downloads of
# several hundred MB in place for a month.
export MISE_CACHE_PRUNE_AGE=7d

# Go refreshes an entry's mtime on use only when it is over an hour old, so a
# file in use can look up to an hour older than it is. Three hours is that
# hour plus two for the longest build that may have resolved the entry and not
# yet read it.
GO_FLOOR_MIN=180
# Bun's entry mtime is extraction time, not last use, so its floor only has to
# outlast an install in progress.
BUN_FLOOR_MIN=1440

# Hourly runs can outlast the hour on a large first pass over a slow
# filesystem; a second copy would only race the first. The lock lives on the
# pod-local /tmp, whatever backs the home directory, and only a held lock (exit 75) skips the run: any other flock
# failure is an error, so a lock that can never be taken does not turn every
# run into a quiet skip.
lock_file="${TMPDIR:-/tmp}/cache-gc.lock"
exec 9>"$lock_file"
flock_rc=0
flock -n -E 75 9 || flock_rc=$?
case "$flock_rc" in
  0) ;;
  75)
    echo "cache-gc: previous run still in progress; skipping"
    exit 0
    ;;
  *)
    echo "cache-gc: cannot lock $lock_file (flock exit $flock_rc)" >&2
    exit 1
    ;;
esac
freed_file="$(mktemp)"
trap 'rm -f "$freed_file"' EXIT

# Walking these caches is mostly stats, slow over NFS; yield to the builds using them.
renice -n 19 -p $$ >/dev/null 2>&1 || true
ionice -c 3 -p $$ >/dev/null 2>&1 || true

failed=()

log() { echo "cache-gc: $*"; }

# cap_mib OVERRIDE DEFAULT_MIB PERCENT DIR: OVERRIDE if set, else the smaller
# of DEFAULT_MIB and PERCENT of DIR's filesystem. A fixed cap alone would fill
# a home volume smaller than it; a share alone would be meaningless on an NFS
# share, whose reported size is the whole export rather than its quota.
cap_mib() {
  local override="$1" default="$2" pct="$3" dir="$4" probe fs_kib share
  if [ -n "$override" ]; then
    echo "$override"
    return
  fi
  probe="$dir"
  while [ ! -e "$probe" ] && [ "$probe" != / ]; do probe="$(dirname "$probe")"; done
  fs_kib="$(df -Pk -- "$probe" 2>/dev/null | awk 'NR == 2 { print $2 }')"
  share=$((${fs_kib:-0} * pct / 100 / 1024))
  if [ "$share" -gt 0 ] && [ "$share" -lt "$default" ]; then
    echo "$share"
  else
    echo "$default"
  fi
}

# scan ARGS: find, skipping start points that do not exist. Other sessions'
# tools, Go's own trim among them, delete from these caches while the walk
# runs, so an entry vanishing mid-walk is expected and ignored. Any other find
# error, such as a directory it cannot read, is printed and fails the caller,
# rather than reading as a cache with nothing to remove.
scan() {
  local starts=() errs rc=0
  while [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; do
    [ -e "$1" ] && starts+=("$1")
    shift
  done
  [ "${#starts[@]}" -gt 0 ] || return 0
  errs="$(mktemp)" || return 1
  find "${starts[@]}" "$@" 2>"$errs" || true
  if grep -v 'No such file or directory' "$errs" >&2; then
    rc=1
  fi
  rm -f "$errs"
  return "$rc"
}

# remove_paths LABEL [RECHECK_MIN]: reads NUL-terminated "<KiB> <path>"
# records from stdin, removes each path whole, and adds the sizes to the run
# total. A size of "-" means measure it here, for the few directory entries
# find cannot size. Sizes are disk blocks, which is what the quota counts: a
# cache of many small files occupies several times its bytes. Removal is
# batched, because a Go cache eviction can name a hundred thousand entries.
#
# With RECHECK_MIN, each path is removed only if its mtime is still older than
# that at the moment of removal. A walk of a large cache takes minutes, and an
# entry a build touched since it was walked must survive; this keeps the gap
# between the age check and the removal as short as Go's own trim keeps it.
remove_paths() {
  local label="$1" recheck_min="${2:-}" rec kib path count=0 freed=0 list rc=0
  list="$(mktemp)" || return 1
  while IFS= read -r -d '' rec; do
    kib="${rec%% *}"
    path="${rec#* }"
    if [ "$kib" = "-" ]; then
      kib=$(du -sk -- "$path" 2>/dev/null | cut -f1) || true
    fi
    printf '%s\0' "$path" >>"$list"
    count=$((count + 1))
    freed=$((freed + ${kib:-0}))
  done
  if [ "$dry_run" -eq 0 ] && [ -s "$list" ]; then
    if [ -n "$recheck_min" ]; then
      # shellcheck disable=SC2016 # $0 and $@ belong to the inner shell.
      xargs -0 sh -c 'find "$@" -maxdepth 0 -mmin +"$0" -exec rm -rf -- {} + 2>/dev/null || true' "$recheck_min" <"$list" || rc=1
    else
      xargs -0 rm -rf -- <"$list" || rc=1
    fi
  fi
  rm -f "$list"
  echo "$freed" >>"$freed_file"
  if [ "$rc" -ne 0 ]; then
    log "$label: removal failed partway; up to $count item(s), $((freed / 1024)) MiB"
    return 1
  fi
  log "$label: removed $count item(s), $((freed / 1024)) MiB"
}

# evict_oldest_to_cap LABEL CAP_MIB FLOOR_MIN: reads "mtime kib path" lines,
# and prints NUL-terminated "kib path" records, oldest first, until the remaining total is
# under the cap. Never prints an entry younger than the floor, so the cap is
# soft: a burst that writes more than the cap inside the floor is kept.
evict_oldest_to_cap() {
  local label="$1" cap_mib="$2" floor_min="$3" sorted total
  # Sorted to a file and streamed twice, once for the total and once to
  # select, so memory stays flat however many entries a first pass sees.
  sorted="$(mktemp)" || return 1
  if ! sort -n -S 32M -T "${TMPDIR:-/tmp}" -o "$sorted"; then
    rm -f "$sorted"
    return 1
  fi
  total="$(awk '{ t += $2 } END { printf "%.0f", t }' "$sorted")"
  awk -v total="$total" -v cap=$((cap_mib * 1024)) -v cutoff="$(($(date +%s) - floor_min * 60))" \
    -v floor="$floor_min" -v label="$label" '
    BEGIN { printf "cache-gc: %s: %d MiB, cap %d MiB\n", label, total / 1024, cap / 1024 > "/dev/stderr" }
    total <= cap { exit }
    $1 >= cutoff {
      printf "cache-gc: %s: stopped at the %d-minute floor, %d MiB over cap\n", label, floor, (total - cap) / 1024 > "/dev/stderr"
      exit
    }
    { kib = $2; sub(/^[^ ]+ [^ ]+ /, ""); printf "%.0f %s%c", kib, $0, 0; total -= kib }' "$sorted"
  rm -f "$sorted"
}

# go_cache LABEL DIR CAP_MIB: Go's build cache layout, which golangci-lint
# copies. Entries are <2 hex>/<hash>-a (action) and <hash>-d (output; a
# directory for a cached executable). Go's own Trim() (cmd/go/internal/cache,
# cache.go) deletes exactly these by mtime, with no lock, while builds run:
# a deleted output is a cache miss, rebuilt, never a failed build, because a
# reader re-checks the output exists when it looks an action up. This applies
# the same predicate with a size cap instead of a fixed five days. trim.txt and
# README are left alone. `go clean -cache` is not used: it removes everything,
# including entries a running build has resolved and not yet read.
go_cache() {
  local label="$1" dir="$2" cap_mib="$3"
  if [ ! -d "$dir" ]; then
    log "$label: no $dir; nothing to do"
    return 0
  fi
  if [ ! -f "$dir/README" ] || [ ! -f "$dir/trim.txt" ]; then
    log "$label: $dir has no README and trim.txt, so is not a Go-layout cache; refusing to touch it"
    return 1
  fi
  # One walk, so each entry is stat'ed once: on NFS the stat is the cost.
  # Executable entries are directories whose size is their contents, which
  # the walk reaches after the directory itself, so those few are held until
  # the end; every file entry streams straight through.
  scan "$dir" -mindepth 2 -maxdepth 3 -regextype posix-extended \
    \( -path "$dir/*/*-d/*" -type f -printf 'F %k %h\n' \) -o \
    \( -regex '.*/[0-9a-f]{2}/[0-9a-f]+-[ad]' -printf 'E %y %T@ %k %p\n' \) |
    awk '
      $1 == "F" { sub_kib[$3] += $2; next }
      $2 == "d" { dmtime[$5] = $3; dkib[$5] = $4; next }
      { printf "%.0f %.0f %s\n", $3, $4, $5 }
      END { for (e in dmtime) printf "%.0f %.0f %s\n", dmtime[e], dkib[e] + sub_kib[e], e }' |
    evict_oldest_to_cap "$label" "$cap_mib" "$GO_FLOOR_MIN" |
    remove_paths "$label" "$GO_FLOOR_MIN"
}

# bun_install_cache DIR: entries are directories named <name>@<version>@@@<n>
# (scoped and nested <name>/<version>@@@<n> forms both occur). Bun counts an
# entry as a hit when <entry>/package.json exists
# (src/install/PackageManager/PackageManagerDirectories.rs,
# is_package_in_cache_at), so an rm -rf that has not reached package.json yet
# would let a concurrent install hardlink a half-deleted package. Each entry is
# therefore renamed into the cache's own .tmp first (bun extracts there and
# renames into place, so it is the same filesystem) and deleted from there.
#
# Only nlink==1 blocks count toward the cap: a file a node_modules still
# hardlinks frees nothing when its cache copy goes. The global install dir
# beside the cache is never touched; it holds globally installed packages.
bun_install_cache() {
  local dir="$1" rec kib entry dest sizes rc=0
  if [ ! -d "$dir" ]; then
    log "bun install cache: no $dir; nothing to do"
    return 0
  fi
  # Everything below renames into and prunes $dir/.tmp, so a directory that
  # holds no bun entries is refused rather than trusted.
  if [ -z "$(scan "$dir" -mindepth 1 -maxdepth 3 \( -name '*@@@*' -o -name '*.npm' \) -print -quit)" ]; then
    if [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
      log "bun install cache: $dir holds no bun entries; refusing to touch it"
      return 1
    fi
    log "bun install cache: $dir is empty; nothing to do"
    return 0
  fi
  mkdir -p "$dir/.tmp" || return 1
  sizes="$(mktemp)" || return 1
  scan "$dir" -mindepth 1 -path "$dir/.tmp" -prune -o -type f -links 1 -printf '%k %P\n' |
    awk -v dir="$dir" '
      { n = split($2, seg, "/"); p = ""
        for (i = 1; i <= n - 1; i++) { p = p (i > 1 ? "/" : "") seg[i]; if (seg[i] ~ /@@@[0-9]+$/) { kib[p] += $1; break } } }
      END { for (p in kib) printf "%.0f %s\n", kib[p], p }' >"$sizes" || rc=1
  scan "$dir" -mindepth 1 -maxdepth 3 -path "$dir/.tmp" -prune -o -type d -name '*@@@*' -printf '%T@ %P\n' -prune |
    awk 'FILENAME == ARGV[1] { kib[$2] = $1; next } { printf "%.0f %.0f %s\n", $1, kib[$2] + 0, $2 }' "$sizes" - |
    evict_oldest_to_cap "bun install cache" "$bun_cap_mib" "$BUN_FLOOR_MIN" |
    while IFS= read -r -d '' rec; do
      kib="${rec%% *}"
      entry="${rec#* }"
      if [ "$dry_run" -eq 1 ]; then
        printf '%s %s\0' "$kib" "$dir/$entry"
        continue
      fi
      dest="$dir/.tmp/cache-gc-$$-${entry//\//_}"
      if mv -T -- "$dir/$entry" "$dest" 2>/dev/null; then
        printf '%s %s\0' "$kib" "$dest"
      fi
    done |
    remove_paths "bun install cache" || rc=1
  rm -f "$sizes"
  # Extractions bun abandoned mid-way, and registry manifests it refetches.
  scan "$dir/.tmp" -mindepth 1 -maxdepth 1 -mmin +"$BUN_FLOOR_MIN" -printf '- %p\0' |
    remove_paths "bun install cache: abandoned extractions" || rc=1
  scan "$dir" -mindepth 1 -maxdepth 1 -type f -name '*.npm' -mtime +7 -printf '%k %p\0' |
    remove_paths "bun install cache: registry manifests" || rc=1
  return "$rc"
}

# bun's runtime transpiler cache writes each file to a temp name and renames it
# into place, and verifies a content hash on every read
# (src/jsc/RuntimeTranspilerCache.rs), so a missing file is a plain miss.
bun_transpiler_cache() {
  scan "$cache_home/bun/@t@" -mindepth 1 -maxdepth 1 -type f -name '*.pile' -mtime +14 -printf '%k %p\0' |
    remove_paths "bun transpiler cache"
}

# snapshot_processes FILE: one line per live process, its working directory
# then its command line, so in_use_by_process does not rescan /proc per
# candidate.
snapshot_processes() {
  local pid
  for pid in /proc/[0-9]*; do
    printf '%s/ %s \n' "$(readlink "$pid/cwd" 2>/dev/null)" "$(tr '\0' ' ' 2>/dev/null <"$pid/cmdline")"
  done >"$1" || return 1
  # This process's own /proc is always there, so an empty snapshot means /proc
  # could not be read, and nothing may be judged unused from it.
  [ -s "$1" ]
}

# in_use_by_process SNAPSHOT PATH: true if a live process had PATH, or
# anything under it, as its working directory or on its command line.
in_use_by_process() {
  grep -qF -e "$2/" -e "$2 " "$1"
}

npm_cache() {
  local dir="${npm_config_cache:-${NPM_CONFIG_CACHE:-$HOME/.npm}}" npx procs rc=0
  if [ ! -d "$dir" ]; then
    log "npm: no $dir; nothing to do"
    return 0
  fi
  # cacache is content-addressed and documented as self-healing: an index
  # entry whose content is gone, or content no index names, is a miss.
  # `npm cache verify` is not used: it takes no lock and empties tmp/ while
  # installs may be writing there.
  scan "$dir/_cacache/content-v2" "$dir/_cacache/index-v5" -type f -mtime +14 -printf '%k %p\0' |
    remove_paths "npm cacache" || rc=1
  # Each _npx/<hash> is a full install npx runs binaries from. npx's lock
  # mkdir/rmdir inside it bumps the directory mtime on every invocation, so
  # that mtime is a true last-used time. Long-running npx servers still run
  # out of it, so anything a process uses is kept regardless of age.
  procs="$(mktemp)" || return 1
  if ! snapshot_processes "$procs"; then
    log "npm: cannot read /proc to tell which npx installs are in use; skipping them"
    rm -f "$procs"
    return 1
  fi
  for npx in "$dir"/_npx/*/; do
    npx="${npx%/}"
    [ -d "$npx" ] || continue
    [ -n "$(scan "$npx" -maxdepth 0 -mtime +14)" ] || continue
    [ -e "$npx/concurrency.lock" ] && continue
    in_use_by_process "$procs" "$npx" && continue
    printf -- '- %s\0' "$npx"
  done | remove_paths "npm npx installs" || rc=1
  rm -f "$procs"
  return "$rc"
}

node_gyp_cache() {
  local dir="$cache_home/node-gyp" v installed=" " procs
  if [ ! -d "$dir" ]; then
    log "node-gyp: no $dir; nothing to do"
    return 0
  fi
  # A native build in flight reads include/ straight from here. A /proc that
  # cannot be read is a failure, never "nothing running".
  procs="$(mktemp)" || return 1
  if ! snapshot_processes "$procs"; then
    log "node-gyp: cannot read /proc to tell whether a build is running; skipping"
    rm -f "$procs"
    return 1
  fi
  if grep -q 'node-gyp' "$procs"; then
    log "node-gyp: a node-gyp process is running; skipping"
    rm -f "$procs"
    return 0
  fi
  rm -f "$procs"
  for v in "$HOME"/.local/share/mise/installs/node/*/bin/node; do
    [ -x "$v" ] && installed="$installed$("$v" --version 2>/dev/null | sed 's/^v//') "
  done
  if command -v node >/dev/null 2>&1; then
    installed="$installed$(node --version 2>/dev/null | sed 's/^v//') "
  fi
  for v in "$dir"/*/; do
    v="${v%/}"
    [ -f "$v/installVersion" ] || continue
    case "$installed" in *" ${v##*/} "*) continue ;; esac
    [ -n "$(scan "$v" -maxdepth 0 -mtime +7)" ] || continue
    printf -- '- %s\0' "$v"
  done | remove_paths "node-gyp"
}

homebrew_cache() {
  local dir="${HOMEBREW_CACHE:-$cache_home/Homebrew}"
  if [ ! -d "$dir/downloads" ]; then
    log "Homebrew: no $dir/downloads; nothing to do"
    return 0
  fi
  # brew cleanup is not used: beyond the cache it removes old kegs and
  # autoremoves formulae, which is installed software. Blobs keep the server's
  # mtime, so age is ctime (when it was written here). Downloads still in
  # progress end in .incomplete and are left alone.
  scan "$dir/downloads" -mindepth 1 -maxdepth 1 -type f -ctime +30 ! -name '*.incomplete' -printf '%k %p\0' |
    remove_paths "Homebrew downloads" || return 1
  if [ "$dry_run" -eq 0 ]; then
    # The <formula>--<version> pointers, relative links into downloads/, whose
    # blobs were removed above.
    scan "$dir" -mindepth 1 -maxdepth 1 -xtype l -lname 'downloads/*' -delete
  fi
}

pip_cache() {
  local dir="${PIP_CACHE_DIR:-$cache_home/pip}"
  if [ ! -d "$dir" ]; then
    log "pip: no $dir; nothing to do"
    return 0
  fi
  scan "$dir/http-v2" "$dir/http" "$dir/wheels" -type f -mtime +30 -printf '%k %p\0' |
    remove_paths "pip"
}

# run_tool LABEL BINARY ARGS...: runs a tool's own pruning command from $HOME
# (mise shims resolve versions by directory). A missing tool is skipped by
# name. timeout bounds a lock held by a long-lived process of that tool; the
# next hourly run retries.
run_tool() {
  local label="$1" bin="$2"
  shift 2
  if ! command -v "$bin" >/dev/null 2>&1; then
    log "$label: $bin not installed; skipped"
    return 0
  fi
  if [ "$dry_run" -eq 1 ]; then
    log "$label: would run $bin $*"
    return 0
  fi
  log "$label: running $bin $*"
  (cd "$HOME" && timeout 600 "$bin" "$@")
}

step() {
  if ! "$@"; then
    failed+=("$1${2:+ ($2)}")
  fi
}

log "starting$([ "$dry_run" -eq 1 ] && echo ' (dry-run, nothing will be deleted)')"

if command -v go >/dev/null 2>&1; then
  go_build_dir="$(cd "$HOME" && go env GOCACHE 2>/dev/null)" || go_build_dir=""
fi
go_build_dir="${go_build_dir:-${GOCACHE:-$cache_home/go-build}}"
case "$go_build_dir" in
  off) log "Go build cache: GOCACHE=off; nothing to do" ;;
  *) step go_cache "Go build cache" "$go_build_dir" \
    "$(cap_mib "${CACHE_GC_GO_BUILD_CAP_MIB:-}" 16384 25 "$go_build_dir")" ;;
esac
golangci_lint_dir="${GOLANGCI_LINT_CACHE:-$cache_home/golangci-lint}"
step go_cache "golangci-lint cache" "$golangci_lint_dir" \
  "$(cap_mib "${CACHE_GC_GOLANGCI_LINT_CAP_MIB:-}" 1024 5 "$golangci_lint_dir")"
bun_dir="${BUN_INSTALL_CACHE_DIR:-$cache_home/.bun/install/cache}"
bun_cap_mib="$(cap_mib "${CACHE_GC_BUN_CAP_MIB:-}" 4096 10 "$bun_dir")"
step bun_install_cache "$bun_dir"
step bun_transpiler_cache
step npm_cache
step node_gyp_cache
step homebrew_cache
step pip_cache
step run_tool "uv" uv cache prune
step run_tool "mise" mise cache prune
step run_tool "pre-commit" pre-commit gc

summary="done. freed $(awk '{ t += $1 } END { printf "%.0f", t / 1024 }' "$freed_file") MiB"
[ "$dry_run" -eq 1 ] && summary="$summary (dry-run, nothing actually deleted)"
if [ "${#failed[@]}" -gt 0 ]; then
  log "$summary; failed: ${failed[*]}"
  exit 1
fi
log "$summary"
