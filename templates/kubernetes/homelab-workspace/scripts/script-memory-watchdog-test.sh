#!/bin/bash
#
# Fixture tests for script-memory-watchdog.sh.
#
# Run it directly; it needs nothing but bash and a writable TMPDIR:
#
#   ./script-memory-watchdog-test.sh
#
# CI runs it too, in the `watchdog` job of .github/workflows/test.yaml, which
# fails the build on the first failed assertion. It exists so that the two
# things in the watchdog that can actually hurt the operator - which processes it
# is willing to kill, and when - can be changed with evidence rather than hope.
#
# The important cases here are the negative ones. A test that asserts "the
# watchdog did not signal the agent session" proves nothing unless the same
# fixture, with one rule removed, produces the opposite result - so each
# exclusion is paired with the mutation that must flip it.
#
# The fixtures are transcribed from a live workspace, not written from a reading
# of how VS Code ought to behave. That distinction is not stylistic: the first
# version of this file assumed `comm` would be `node` for the server processes,
# it is `MainThread` on every real tree, and the whole suite was green while the
# detection it was guarding picked the wrong process.
#
# `kill` is shadowed by a function throughout. The fixture pids are small
# integers - 1, 40, 41 - which in this container name real processes, and a
# harness that sent a real SIGTERM to pid 41 to prove it would have sent one is
# not a harness anybody should run.
set -uo pipefail

SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

PASS=0
FAIL=0
SIGNALS=""

ok() {
  PASS=$((PASS + 1))
  printf '  ok   %s\n' "$1"
}

bad() {
  FAIL=$((FAIL + 1))
  printf '  FAIL %s\n' "$1"
}

assert_eq() {
  local want=$1 got=$2 what=$3
  if [[ $want == "$got" ]]; then
    ok "${what}"
  else
    bad "${what}: want '${want}', got '${got}'"
  fi
}

assert_contains() {
  local hay=$1 needle=$2 what=$3
  if [[ $hay == *"$needle"* ]]; then
    ok "$what"
  else
    bad "${what}: '${needle}' not found"
  fi
}

assert_absent() {
  local hay=$1 needle=$2 what=$3
  if [[ $hay == *"$needle"* ]]; then
    bad "${what}: '${needle}' is present and should not be"
  else
    ok "$what"
  fi
}

# assert_protected <pid> <yes|no> <description>
assert_protected() {
  local pid=$1 want=$2 what=$3 got=no
  [[ -n ${PROTECTED[$pid]:-} ]] && got=yes
  if [[ $got == "$want" ]]; then
    ok "${what}"
  else
    bad "${what}: protected=${got}, expected ${want}"
  fi
}

# assert_armed <role> <yes|no> <description>
assert_armed() {
  local role=$1 want=$2 what=$3 got=no
  role_is_armed "$role" && got=yes
  assert_eq "$want" "$got" "$what"
}

# assert_policed <pid> <role|no> <description>
assert_policed() {
  local pid=$1 want=$2 what=$3
  assert_eq "$want" "${POLICED[$pid]:-no}" "$what"
}

# The stand-in for the kill builtin. Every signal the watchdog believes it sent
# is recorded here and nothing leaves this process.
# shellcheck disable=SC2317,SC2329  # called indirectly, from the sourced watchdog
kill() {
  SIGNALS+="${1#-}:$2 "
  return 0
}

# --------------------------------------------------------------------------- #
# fixtures
# --------------------------------------------------------------------------- #

UPTIME_S=100000

# memory.stat as read from the real 8 GiB workspace pod at rest, trimmed to the
# fields the watchdog reads plus the ones it must be careful to ignore.
write_cgroup() {
  local dir=$1 max=$2 psi_full10=$3
  mkdir -p "$dir"
  cat >"${dir}/memory.stat" <<'EOF'
anon 1979584512
file 4198756352
kernel 1693286400
kernel_stack 2195456
pagetables 10711040
sec_pagetables 0
percpu 13536
sock 4096
shmem 0
unevictable 0
slab_reclaimable 1676590856
slab_unreclaimable 3337768
slab 1679928624
workingset_refault_file 57094899
pgscan_direct 78917443
EOF
  printf '%s\n' "$max" >"${dir}/memory.max"
  printf '%s\n' "7872479232" >"${dir}/memory.current"
  cat >"${dir}/memory.pressure" <<EOF
some avg10=0.00 avg60=0.00 avg300=0.00 total=221199542
full avg10=${psi_full10} avg60=0.00 avg300=0.00 total=214901058
EOF
}

# add_proc <procdir> <pid> <ppid> <comm> <rss-bytes> <argv...>
#
# Every process is old by default; the ones whose age matters set it explicitly
# with set_age. stat's field 22, starttime, is written for real because every
# piece of state the watchdog carries between sweeps is keyed on pid:starttime -
# a recycled pid must not inherit another process's dwell clock.
add_proc() {
  local dir=$1 pid=$2 ppid=$3 comm=$4 rss=$5
  shift 5
  local d="${dir}/${pid}"
  mkdir -p "$d"
  # stat fields 5, 6 and 7 are pgrp, session and tty. The session is the one the
  # helper walk keys on, so it is written for real; everything shares session 1
  # unless set_sid says otherwise.
  printf '%s (%s) S %s 1 1 0 -1 4194560 0 0 0 0 0 0 0 0 20 0 1 0 100\n' \
    "$pid" "$comm" "$ppid" >"${d}/stat"
  printf '0 %s 0 0 0 %s 0\n' "$((rss / 4096))" "$((rss / 4096))" >"${d}/statm"
  set_pss "$dir" "$pid" "$rss"
  cat >"${d}/limits" <<'EOF'
Limit                     Soft Limit           Hard Limit           Units
Max data size             unlimited            unlimited            bytes
EOF
  local arg
  : >"${d}/cmdline"
  for arg in "$@"; do
    printf '%s\0' "$arg" >>"${d}/cmdline"
  done
}

# set_pss <procdir> <pid> <bytes>. PSS is what every budget is compared against,
# so it is the fixture knob the drift tests turn.
set_pss() {
  local dir=$1 pid=$2 bytes=$3
  cat >"${dir}/${pid}/smaps_rollup" <<EOF
55a4c0000000-7ffd0f7ff000 ---p 00000000 00:00 0                          [rollup]
Rss:            $((bytes / 1024)) kB
Pss:            $((bytes / 1024)) kB
Pss_Anon:       $((bytes / 2048)) kB
Private_Dirty:  $((bytes / 2048)) kB
EOF
}

# set_sid <procdir> <pid> <sid>. Claude Code detaches every Bash tool call into
# its own session; this is how a fixture says so.
set_sid() {
  local dir=$1 pid=$2 sid=$3
  local -a f
  read -r -a f <"${dir}/${pid}/stat"
  f[4]=$sid
  f[5]=$sid
  printf '%s\n' "${f[*]}" >"${dir}/${pid}/stat"
}

# set_age <procdir> <pid> <seconds>
set_age() {
  local dir=$1 pid=$2 age=$3 line rest
  read -r line <"${dir}/${pid}/stat"
  rest=${line% *}
  printf '%s %s\n' "$rest" "$(((UPTIME_S - age) * 100))" >"${dir}/${pid}/stat"
}

write_uptime() {
  printf '%s.00 %s.00\n' "$UPTIME_S" "$((UPTIME_S * 4))" >"${1}/uptime"
}

# A representative tree, transcribed from `ps -eo pid,ppid,comm,args` on a live
# workspace with a VS Code server attached, and extended with the second
# population this watchdog now polices: the helpers an agent session spawns.
#
# The PSS figures are the maxima the watchdog's own sweep log recorded for each
# role over ~38 hours on that workspace, not sizes invented to make a test pass.
# One of them matters more than the rest: the extension host is written at the
# 738 MB it actually reached, which is *above* its 480 MiB share of the envelope,
# because that is the real situation this design has to survive. In the fixture
# as in the pod it is therefore classified oversize and never signalled - which
# is also what keeps every kill assertion below about exactly one process.
#
# The `comm` values are load-bearing. Every node process in a real server tree
# reports MainThread, because V8 renames its main thread with prctl(PR_SET_NAME).
# An earlier version of this fixture wrote `node`, and that one wrong string hid
# a root-selection bug that only a real tree could expose.
#
#   1  coder agent
#   +- 30  bash -l
#   |   +- 31  sh
#   |       +- 32  code-<commit> command-shell        (the CLI, not the server)
#   |           +- 33  code-<commit> agent host
#   |           +- 34  sh .../bin/code-server --start-server
#   |               +- 40  server-main.js            <- the root
#   |                   +- 41  extensionHost
#   |                   |   +- 44  tsserver.js
#   |                   |   |   +- 57  typingsInstaller.js  <- treeHelper
#   |                   |   +- 45  yaml languageserver.js
#   |                   |   +- 46  terraform-ls      (native, not node)
#   |                   |   +- 47  claude-code cli.js  (mise's node, not VS Code's)
#   |                   |   +- 48  an extension task   (mise's node, not VS Code's)
#   |                   |   +- 55  markdown serverWorkerMain  <- treeHelper
#   |                   |   +- 56  even-better-toml server.js <- treeHelper
#   |                   +- 42  fileWatcher
#   |                   +- 49  an unrecognised core fork  <- NOT policed
#   |                   +- 43  ptyHost               <- positional protection
#   |                       +- 50  bash
#   |                           +- 51  tmux: server
#   |                               +- 52  claude    (a session in a VS Code terminal)
#   |                               |   +- 54  python MCP server  <- policed
#   |                               +- 53  node (the hog)
#   +- 60  claude (a session under `coder ssh`)
#       +- 61  python MCP server                     <- policed
#       +- 62  node MCP server                       <- policed
#       +- 63  bash -c (a tool call)                 <- boundary
#       |   +- 64  a build the session is running    <- never policed
#       +- 65  claude (a child session)
#           +- 66  python MCP server of the child    <- policed
#
# Decoys 3 and 4 both sort before 40 in /proc glob order, which is how the root
# used to be picked when no process had comm=node - i.e. always, on a real tree.
build_tree() {
  local dir=$1 ptyhost_arg=${2:---type=ptyHost} nc=${3:-MainThread}
  local vsc="/home/coder/.vscode-server"
  local sdir="${vsc}/cli/servers/Stable-abc123/server"
  local srv="${sdir}/out/server-main.js"
  local ext="${vsc}/extensions"
  # The operator's node, from mise, on PATH. Nothing to do with VS Code's.
  local mnode="/home/coder/.local/share/mise/installs/node/22.14.0/bin/node"
  mkdir -p "$dir"
  write_uptime "$dir"
  add_proc "$dir" 1 0 coder 14208 ./coder agent
  # Mentions both marker strings, and carries a ptyHost-like flag inside a larger
  # argument. Substring matching over the joined command line would elect it.
  add_proc "$dir" 3 1 bash 3000000 bash -c \
    "tail -f ${srv}.log --type=extensionHost-ish"
  # Harder: the server path appears here as a whole argv element. Only argv[0]
  # separates this from the real thing.
  add_proc "$dir" 4 1 cat 3000000 cat "$srv"

  add_proc "$dir" 30 1 bash 8000000 /bin/bash -l
  add_proc "$dir" 31 30 sh 3000000 sh
  add_proc "$dir" 32 31 code-abc123 60000000 \
    "${vsc}/code-abc123" command-shell --reconnection-grace-time 28800 \
    --cli-data-dir "${vsc}/cli" --parent-process-id 31
  add_proc "$dir" 33 32 code-abc123 40000000 \
    "${vsc}/code-abc123" --cli-data-dir "${vsc}/cli" agent host
  add_proc "$dir" 34 32 sh 3000000 sh "${sdir}/bin/code-server" \
    --connection-token=remotessh --start-server --enable-remote-auto-shutdown

  add_proc "$dir" 40 34 "$nc" 233000000 "${sdir}/node" "$srv" \
    --connection-token=remotessh --start-server --enable-remote-auto-shutdown
  add_proc "$dir" 41 40 "$nc" 738000000 "${sdir}/node" \
    --dns-result-order=ipv4first "${sdir}/out/bootstrap-fork" \
    --type=extensionHost --transformURIs --useHostProxy=false
  add_proc "$dir" 44 41 "$nc" 208000000 "${sdir}/node" \
    "${ext}/ms-vscode.typescript/lib/tsserver.js" --useInferredProjectPerProjectRoot
  add_proc "$dir" 45 41 "$nc" 31000000 "${sdir}/node" \
    "${ext}/redhat.vscode-yaml-1.24.0/dist/languageserver.js" --node-ipc --clientProcessId=41
  add_proc "$dir" 46 41 terraform-ls 24000000 \
    "${ext}/hashicorp.terraform-2.40.0-linux-x64/bin/terraform-ls" serve
  # Two processes the extension host spawned that run the *operator's* node, not
  # VS Code's. There is no /usr/bin/node and nothing named node on PATH in this
  # image without dotfiles; mise's node and VS Code's bundled node are unrelated
  # installations, and the operator's agent sessions run on the former. Both of
  # these are children of the extension host and neither is under ptyHost, so
  # nothing about tree position saves them - only argv[0] does.
  add_proc "$dir" 47 41 "$nc" 2500000000 "$mnode" \
    "${ext}/anthropic.claude-code-2.1.232/resources/claude-code/cli.js" --ide
  add_proc "$dir" 48 41 "$nc" 600000000 "$mnode" \
    "${ext}/hverlin.mise-vscode-1.6.0/dist/taskRunner.js" --cwd /home/coder/code
  # The three processes role_of used to return `other` for, transcribed from
  # `ps -eo pid,ppid,sid,comm,args` on the live workspace along with their
  # measured PSS. All three run VS Code's own node, all three hang off the
  # extension host or off another helper rather than off the server root, and
  # none of the role patterns reaches any of them:
  #
  #   - a user-installed extension's language server, whose script is called
  #     `server.js` like roughly every other extension's. 280 MB PSS measured,
  #     i.e. already above the 256 MiB languageServer budget it would have been
  #     given had a pattern matched it. Written here at the 287 MB figure the
  #     investigation recorded.
  #   - a built-in extension's server, under the *server's* extensions
  #     directory rather than the user one, and named by neither convention.
  #   - tsserver's typings installer, a grandchild: helpers spawn helpers.
  add_proc "$dir" 55 41 "$nc" 56000000 "${sdir}/node" \
    "${sdir}/extensions/markdown-language-features/dist/serverWorkerMain" \
    --node-ipc --clientProcessId=41
  add_proc "$dir" 56 41 "$nc" 287000000 "${sdir}/node" \
    "${ext}/tamasfe.even-better-toml-0.21.2/dist/server.js" --node-ipc --clientProcessId=41
  add_proc "$dir" 57 44 "$nc" 63000000 "${sdir}/node" \
    "${sdir}/extensions/node_modules/typescript/lib/typingsInstaller.js" \
    --globalTypingsCacheLocation /home/coder/.cache/typescript/6.0 --enableTelemetry
  # A core fork whose --type= flag this script does not recognise - the shape a
  # VS Code upgrade produces if it renames or adds one. It is a *direct child of
  # the server root*, which is what every core fork is and what no extension
  # helper is, and that is the whole reason the treeHelper fallback declines it:
  # a renamed extensionHost must become unmanaged and loud, never managed on a
  # guessed 512 MiB budget.
  add_proc "$dir" 49 40 "$nc" 200000000 "${sdir}/node" \
    "${sdir}/out/bootstrap-fork" --type=sharedProcess

  add_proc "$dir" 42 40 "$nc" 107000000 "${sdir}/node" \
    "${sdir}/out/bootstrap-fork" --type=fileWatcher
  add_proc "$dir" 43 40 "$nc" 100000000 "${sdir}/node" \
    "${sdir}/out/bootstrap-fork" "$ptyhost_arg" --logsPath "${vsc}/data/logs/20260816T162519"
  add_proc "$dir" 50 43 bash 20000000 /bin/bash -l
  add_proc "$dir" 51 50 "tmux: server" 5000000 tmux new -s work
  add_proc "$dir" 52 51 claude 900000000 claude
  # Deliberately inside its budget: this one is in the fixture to prove it is
  # *reachable*, and a second process over budget would make every assertion
  # about which pid was killed depend on hash iteration order.
  add_proc "$dir" 54 52 python3 300000000 \
    /usr/bin/python3 -m mcp_server_terminal --stdio
  add_proc "$dir" 53 51 "$nc" 3000000000 node -e "const a=[];setInterval(()=>a.push(Buffer.alloc(1)),1)"

  # A session started with `coder ssh`, i.e. a child of the agent rather than of
  # the editor, and the helpers it spawned. This is the population the
  # tree-scoped selection could not see at all.
  add_proc "$dir" 60 1 claude 700000000 claude
  add_proc "$dir" 61 60 python3 1660000000 \
    /home/coder/.local/share/mise/installs/python/3.13/bin/python3 \
    -m homelab_mcp.server --transport stdio
  add_proc "$dir" 62 60 MainThread 200000000 \
    /home/coder/.local/share/mise/installs/node/22.14.0/bin/node \
    /home/coder/.local/share/npm/mcp-server-github/dist/index.js
  add_proc "$dir" 63 60 bash 3000000 /bin/bash -c "cargo build --release"
  add_proc "$dir" 64 63 cargo 2000000000 cargo build --release
  # Measured on the live workspace: a session root has sid = the login shell's
  # session, and every Bash tool call has pgid = sid = its own pid. The build
  # below therefore has two independent reasons not to be policed, and the tests
  # remove them one at a time.
  set_sid "$dir" 63 63
  set_sid "$dir" 64 63
  # The shape that makes the session rule matter on its own: a tool call whose
  # shell exec'd itself away, so there is no shell left in the chain at all.
  add_proc "$dir" 67 60 python3 1500000000 /usr/bin/python3 ./scripts/train.py
  set_sid "$dir" 67 67
  add_proc "$dir" 65 60 claude 400000000 claude --child-session
  add_proc "$dir" 66 65 python3 300000000 /usr/bin/python3 -m mcp_server_fetch
}

# A second, stale server left behind by --reconnection-grace-time, on a different
# commit. Its ptyHost subtree must be excised too, which only happens if it is
# discovered as a root in its own right.
add_second_server() {
  local dir=$1
  local sdir="/home/coder/.vscode-server/cli/servers/Stable-def456/server"
  add_proc "$dir" 70 1 MainThread 200000000 "${sdir}/node" \
    "${sdir}/out/server-main.js" --connection-token=remotessh --start-server
  add_proc "$dir" 71 70 MainThread 90000000 "${sdir}/node" \
    "${sdir}/out/bootstrap-fork" --type=ptyHost --logsPath /home/coder/.vscode-server/data/logs/x
  add_proc "$dir" 72 71 bash 10000000 /bin/bash -l
  add_proc "$dir" 73 70 MainThread 500000000 "${sdir}/node" \
    "${sdir}/out/bootstrap-fork" --type=fileWatcher
}

# Always set explicitly, and never left at its default: the real default is
# /proc/1/fd/1, i.e. the container's own stdout.
#
# This is not hypothetical. The first run of this suite after the stdout path was
# added - before load_watchdog set the seam - wrote its fixture kill lines into
# the live workspace's container log, where they reached Loki labelled as that
# workspace and reading `event=kill role=extensionHost pss_mb=1907`. Nothing was
# signalled (kill is shadowed), but for as long as those lines are retained they
# describe kills that never happened, on a real workspace, in the exact format a
# post-mortem would trust. A test fixture that can write into production
# telemetry is a defect in the test, so the seam is asserted below rather than
# merely set.
STDOUT_FILE=""

load_watchdog() {
  local mode=${3:-observe}
  STDOUT_FILE="${WORK}/stdout.log"
  : >"$STDOUT_FILE"
  WATCHDOG_SOURCE_ONLY=1 \
    WATCHDOG_CGROUP_DIR="$1" \
    WATCHDOG_PROC_DIR="$2" \
    WATCHDOG_STATE_DIR="${WORK}/state" \
    WATCHDOG_STDOUT_PATH="$STDOUT_FILE" \
    WATCHDOG_MODE="$mode" \
    . "${SELF_DIR}/script-memory-watchdog.sh"
  # Not an assertion - a refusal. If the seam ever fails to take, every later
  # test in this file writes fixture actions to the container's real stdout.
  if [[ ${STDOUT_PATH:-} != "$STDOUT_FILE" ]]; then
    printf 'FATAL: the stdout seam did not take (STDOUT_PATH=%s); refusing to run\n' \
      "${STDOUT_PATH:-unset}" >&2
    exit 1
  fi
  mkdir -p "${WORK}/state"
  SIGNALS=""
  # Budgets are installed on the first cycle rather than at source time, so a
  # harness that skipped this would be testing a watchdog with no budgets at all
  # - which is not a state the real thing is ever in, and which silently passes
  # any assertion about not killing anything.
  read_cgroup_memory && derive_budgets
  read_cgroup_pressure
}

scan_fixture() {
  read_uptime
  read_process_table
  build_server_tree
  compute_protected
  compute_policed
  read_usage "${PIDS[@]}"
}

sweep_at() {
  sweep_once "$1"
  SWEEPS=$((SWEEPS + 1))
}

# Replaces the watchdog's role classifier with the one this file used before a
# live tree was consulted: keyed on the joined command line rather than on
# argv[0]. Defined here rather than inline so that the tests below can call
# role_of before the mutation exists.
mutate_role_of_to_cmdline() {
  # shellcheck disable=SC2317,SC2329  # invoked indirectly, via the sourced watchdog
  role_of() {
    case " ${P_CMD[$1]:-} " in
    *"/.vscode-server/extensions/"*) ROLE=extensionHelper ;;
    *) ROLE=other ;;
    esac
  }
}

# --------------------------------------------------------------------------- #
# 1. the measurement
# --------------------------------------------------------------------------- #

test_measurement() {
  printf 'measurement\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  local pdir="${WORK}/proc1"
  build_tree "$pdir"
  load_watchdog "${WORK}/cg" "$pdir"
  read_cgroup_memory

  # Hand-computed from the fixture, which is the real pod's memory.stat:
  #   1979584512 + 0 + 0 + 3337768 + 2195456 + 10711040 + 0 + 13536 + 4096
  assert_eq 1995846408 "$M_U" "U excludes slab_reclaimable and page cache"
  assert_eq 6594088184 "$M_H" "H = memory.max - U"

  # The whole reason this formula exists: the naive readings disagree by 4x.
  assert_eq 23 "$((M_U * 100 / M_MAX))" "U is 23% of the limit"
  assert_eq 91 "$((M_CURRENT * 100 / M_MAX))" "memory.current is 91% of the limit"
  assert_eq ok "$PRESSURE" "and the pod is labelled comfortable, because it is"

  assert_eq "6.14 GiB" "$(fmt_gib 6594088184)" "headroom formats as GiB"
  assert_eq "-1.50 GiB" "$(fmt_gib -1610612736)" "a negative value formats with one sign"
  assert_eq "512 MiB" "$(fmt_mib 536870912)" "budgets format as MiB"

  read_cgroup_pressure
  assert_eq 0 "$M_PSI_CENTI" "psi full avg10 parses as 0"
  write_cgroup "${WORK}/cg" 8589934592 12.34
  read_cgroup_pressure
  assert_eq 1234 "$M_PSI_CENTI" "psi full avg10 parses to centi-units"

  write_cgroup "${WORK}/cg" max 0.00
  read_cgroup_memory
  assert_eq 2 "$?" "an unlimited cgroup is reported, not treated as huge headroom"

  # PSS is the quantity every budget is compared against, and it is not RSS.
  write_cgroup "${WORK}/cg" 8589934592 0.00
  load_watchdog "${WORK}/cg" "$pdir"
  scan_fixture
  set_pss "$pdir" 41 123456789
  read_usage 41
  assert_eq 123456512 "${P_PSS[41]}" "PSS is read from smaps_rollup"
  assert_eq 737996800 "${P_RSS[41]}" "and RSS separately from statm"
  assert_eq 0 "$PSS_UNAVAILABLE" "with PSS available, nothing is flagged"

  # And the fallback, which must be visible rather than silent: RSS is the larger
  # number, so substituting it quietly would make every budget look tighter.
  rm -f "${pdir}/41/smaps_rollup"
  read_usage 41
  assert_eq 737996800 "${P_PSS[41]}" "without smaps_rollup, RSS stands in"
  assert_eq 1 "$PSS_UNAVAILABLE" "and the substitution is recorded, not hidden"
  set_pss "$pdir" 41 738000000
}

# --------------------------------------------------------------------------- #
# 2. what is policed, and what is never touched
# --------------------------------------------------------------------------- #

test_selection() {
  printf 'selection\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  local pdir="${WORK}/proc2"
  build_tree "$pdir"
  load_watchdog "${WORK}/cg" "$pdir"
  scan_fixture

  # The regression this whole fixture exists for: on a real tree no process has
  # comm=node, so any rule that preferred or required it fell through to picking
  # the first /proc-glob match - which is decoy pid 4, not the server.
  assert_eq MainThread "${P_COMM[40]}" "the fixture encodes the real comm value"
  assert_eq 40 "$SERVER_PID" "server root found with comm=MainThread, not comm=node"
  assert_eq "40" "${SERVER_ROOTS[*]}" "and the decoys are not roots"
  assert_eq 18 "${#SERVER_TREE[@]}" "server tree spans every descendant, ptyHost included"

  local d
  for d in 3 4; do
    if [[ -n ${SERVER_TREE[$d]:-} ]]; then
      bad "decoy pid ${d} joined the tree"
    else
      ok "decoy pid ${d} stays out of the tree"
    fi
  done
  for d in 30 31 32 33 34; do
    if [[ -n ${SERVER_TREE[$d]:-} ]]; then
      bad "ancestor pid ${d} joined the tree"
    else
      ok "ancestor pid ${d} stays out of the tree"
    fi
  done

  role_of 3
  assert_eq other "$ROLE" "a --type=extensionHost-ish argument is not read as a role flag"
  role_of 43
  assert_eq ptyHost "$ROLE" "the real --type=ptyHost argument is"
  role_of 40
  assert_eq serverMain "$ROLE" "the root reads as serverMain"
  role_of 41
  assert_eq extensionHost "$ROLE" "the real extension-host argv reads as extensionHost"
  role_of 42
  assert_eq fileWatcher "$ROLE" "the real file-watcher argv reads as fileWatcher"
  role_of 44
  assert_eq tsserver "$ROLE" "tsserver reads as tsserver"
  role_of 45
  assert_eq languageServer "$ROLE" "a node language server under extensions/ keeps its role"
  role_of 46
  assert_eq extensionHelper "$ROLE" "terraform-ls reads as a native extension helper"

  # ptyHost is matched loosely on purpose, unlike every other role. Reading
  # something as ptyHost that is not only ever protects more than necessary.
  # shellcheck disable=SC2034  # P_CMD is a global of the sourced watchdog
  P_CMD[9001]="/usr/bin/node fork --type=ptyHostSomethingNew"
  role_of 9001
  assert_eq ptyHost "$ROLE" "an unrecognised ptyHost variant still reads as ptyHost"
  unset 'P_CMD[9001]'

  assert_policed 40 serverMain "the server root is policed"
  assert_policed 41 extensionHost "so is the extension host"
  assert_policed 42 fileWatcher "so is the file watcher"
  assert_policed 44 tsserver "so is tsserver"
  assert_policed 46 extensionHelper "so is terraform-ls"

  assert_policed 43 no "the ptyHost fork itself is never policed"
  assert_policed 50 no "nor the shell beneath it"
  assert_policed 51 no "nor tmux"
  assert_policed 52 no "nor a session running in a VS Code terminal"
  assert_policed 53 no "nor the hog that session started"
  assert_policed 47 no "nor an agent session the extension host spawned"
  assert_policed 48 no "nor an extension task on the operator's node"
  assert_policed 60 no "nor a session under coder ssh"
  assert_policed 64 no "nor a build a session is running"
  assert_policed 1 no "nor the coder agent"

  assert_protected 1 yes "pid 1 is protected"
  assert_protected 60 yes "an agent session is protected"
  assert_protected 52 yes "including one inside a terminal"
}

# --------------------------------------------------------------------------- #
# 2b. the second population: helpers an agent session spawned
#
# These are what the tree-scoped selection could not see at all, and where the
# largest single offender ever measured lived - 1.66 GB of python. The rule is
# structural: descend from a session root, stop at any shell, police what is
# left. The shell boundary is the difference between "anything a session invokes
# is fair game" as a principle and as a foot-gun, because below a shell is the
# session's in-flight work and nothing restarts that.
# --------------------------------------------------------------------------- #

test_claude_helpers() {
  printf 'helpers spawned by an agent session\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  local pdir="${WORK}/proc2b"
  build_tree "$pdir"
  load_watchdog "${WORK}/cg" "$pdir"
  scan_fixture

  assert_eq 3 "${#CLAUDE_ROOTS[@]}" "every session root is found, including a child session"
  assert_policed 61 claudeHelper "the python MCP server is policed"
  assert_policed 62 claudeHelper "and the node one"
  assert_policed 66 claudeHelper "and a child session's MCP server"
  assert_policed 63 no "a tool call's shell is not"
  assert_policed 64 no "and neither is what that shell is running"
  assert_policed 67 no "nor a tool call whose shell exec'd itself away - the session says so"
  assert_policed 65 no "a child session is a session, not a helper"

  # The identity breadcrumb is what makes the sweep log answerable later: three
  # of these are `python3` or `node` and only the argument distinguishes them.
  assert_eq "homelab_mcp.server" "$(identity_of 61 claudeHelper)" \
    "a python MCP server is identified by its module, not by python3"
  assert_eq "index" "$(identity_of 62 claudeHelper)" \
    "and a node one by its script, not by node"
  assert_eq "terraform-ls" "$(identity_of 46 extensionHelper)" \
    "a native extension helper by its binary"

  # The case the ptyHost hole exists for. A session in a VS Code terminal is the
  # same thing to the operator as one under `coder ssh`; only its terminal
  # differs. Its MCP server is policed, and everything that makes it a terminal
  # is not.
  assert_policed 54 claudeHelper "an MCP server of a session in a VS Code terminal is policed"
  local p
  for p in 43 50 51 52 53; do
    if [[ -n ${NOT_EDITOR[$p]:-} ]]; then
      ok "pid ${p} is inside the ptyHost subtree"
    else
      bad "pid ${p} is NOT inside the ptyHost subtree"
    fi
  done
  if signal_pid TERM 53 other "test"; then
    bad "the hog in a terminal could be signalled"
  else
    ok "the hog in a terminal is refused by the positional guard"
  fi
  if signal_pid TERM 52 claudeHelper "test"; then
    bad "a session in a terminal could be signalled by claiming a helper role"
  else
    ok "a session in a terminal is refused whatever role is claimed"
  fi

  # Falsification. All of the above would pass equally against a watchdog that
  # polices nothing at all, so each rule is removed in turn and must flip a
  # result.
  #
  # Mutation 1 - the session boundary is removed, the shell test kept. The
  # exec'd-away tool call has nothing left and becomes policed; the ordinary one
  # is still held by its shell. That asymmetry is the measurement of what each
  # rule is doing, and why neither may be dropped as redundant.
  local saved_sid=${P_SID[63]}
  P_SID[63]=1
  P_SID[64]=1
  P_SID[67]=1
  compute_policed
  assert_policed 67 claudeHelper "without the session rule, an exec'd-away tool call is policed"
  assert_policed 64 no "while the shell rule still holds the ordinary one"
  P_SID[63]=$saved_sid
  P_SID[64]=$saved_sid
  P_SID[67]=67

  # Mutation 2 - shells stop being a boundary, sessions kept. The build is still
  # spared, because its session differs.
  # shellcheck disable=SC2317,SC2329  # invoked indirectly, via the sourced watchdog
  is_shell_like() { return 1; }
  compute_policed
  assert_policed 64 no "with the session rule alone, a running build is still spared"
  P_SID[63]=1
  P_SID[64]=1
  compute_policed
  assert_policed 64 claudeHelper "and with neither rule it is policed - which is the harm both prevent"

  # Mutation 3 - session roots stop being recognised. Every helper disappears
  # from the policed set, which proves the walk is what put them there.
  # shellcheck disable=SC2317,SC2329  # invoked indirectly, via the sourced watchdog
  is_claude_root() { return 1; }
  compute_policed
  assert_policed 61 no "with no session roots there are no session helpers"
  assert_policed 54 no "including the one in a terminal"
}

# --------------------------------------------------------------------------- #
# 2c. the operator's runtime is never a VS Code helper
#
# An agent session spawned by an extension is a child of the extension host, is
# not under ptyHost, and would be policed by anything that decides "is this a VS
# Code helper" by asking "is this node".
# --------------------------------------------------------------------------- #

test_operator_runtime_is_never_a_helper() {
  printf 'the operator runtime is never a VS Code helper\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  local pdir="${WORK}/proc2c"
  build_tree "$pdir"
  load_watchdog "${WORK}/cg" "$pdir"
  scan_fixture

  role_of 47
  assert_eq other "$ROLE" "an agent session under the extension host is not a helper role"
  role_of 48
  assert_eq other "$ROLE" "nor is an extension task run on the operator's node"
  role_of 46
  assert_eq extensionHelper "$ROLE" "while the extension's own binary still is one"

  assert_protected 47 yes "the agent session is protected by identity"
  assert_protected 48 no "the extension task is not - it is excluded by position and by role"
  assert_policed 48 no "and so it is not policed"
  assert_policed 47 no "nor is the agent session"

  # Two guards stand between these processes and a signal, and each is mutated
  # separately so that neither can be credited with the other's work.
  #
  # Mutation 1 - drop the tree-position rule that says "this does not run VS
  # Code's binary". The agent session survives on its name, which is identity and
  # absolute; the extension task loses its only positional protection and is left
  # standing on one thing alone - that role_of keys on argv[0].
  #
  # The mutation clears the two pids out of NOT_EDITOR rather than overriding
  # is_vscode_binary, and the difference is the point. role_of now consults that
  # same predicate for its treeHelper fallback, so stubbing it `return 0`
  # falsifies the position rule and the role rule at once and proves neither -
  # the suite caught exactly that when the fallback was added. A mutation has to
  # remove one rule, or it is not evidence about which rule was carrying the
  # weight.
  compute_protected
  unset 'NOT_EDITOR[47]' 'NOT_EDITOR[48]'
  compute_policed
  assert_protected 47 yes "without the position rule the agent session still has its name"
  assert_policed 47 no "and is still not policed"
  assert_policed 48 no "the extension task is spared by role_of keying on argv[0], not by position"

  # Mutation 2 - additionally key roles on the joined command line instead of on
  # argv[0], which is what this file did before a live tree was consulted. The
  # extension task's arguments name the extension directory, so it is classified
  # as a sheddable helper and policed.
  mutate_role_of_to_cmdline
  compute_policed
  assert_policed 48 extensionHelper \
    "keying roles on arguments instead of argv[0] is what would police it"
  assert_policed 47 no "while the name guard still keeps the session out"
}

# --------------------------------------------------------------------------- #
# 2d. comm is not a selection criterion, and must never become one again
# --------------------------------------------------------------------------- #

test_comm_is_not_a_criterion() {
  printf 'comm is not a selection criterion\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  local comm n=0
  for comm in MainThread node something-nobody-predicted; do
    n=$((n + 1))
    local pdir="${WORK}/proc-comm-${n}"
    build_tree "$pdir" --type=ptyHost "$comm"
    load_watchdog "${WORK}/cg" "$pdir"
    scan_fixture
    assert_eq 40 "$SERVER_PID" "comm=${comm}: the server root is still pid 40"
    assert_eq 18 "${#SERVER_TREE[@]}" "comm=${comm}: the tree is still complete"
    assert_policed 53 no "comm=${comm}: the hog in a terminal is still not policed"
  done
}

# --------------------------------------------------------------------------- #
# 2e. more than one server, and none of them named `node`
# --------------------------------------------------------------------------- #

test_two_servers() {
  printf 'two concurrent servers\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  local pdir="${WORK}/proc5"
  build_tree "$pdir"
  add_second_server "$pdir"
  load_watchdog "${WORK}/cg" "$pdir"
  scan_fixture

  assert_eq "40 70" "${SERVER_ROOTS[*]}" "both server roots are discovered"
  assert_eq 22 "${#SERVER_TREE[@]}" "the managed tree is the union of both subtrees"
  assert_policed 73 fileWatcher "the second server's file watcher is policed"
  assert_policed 72 no "and the shell under its ptyHost is not"
  if [[ -n ${NOT_EDITOR[71]:-} ]]; then
    ok "the second server's ptyHost subtree is recognised"
  else
    bad "the second server's tree is not managed at all"
  fi
}

# --------------------------------------------------------------------------- #
# 2f. the guards are precise, and each of them is reachable
#
# Both historical over-matches were substring matches over the joined command
# line, both were found by accident, and both were invisible to a green suite -
# the second one protected every process in a fixture harness because the
# harness's own directory path contained the string the guard matched on, so two
# full runs asserted nothing at all. The decoys below are those exact paths.
# --------------------------------------------------------------------------- #

add_decoys() {
  local dir=$1
  local vsc="/home/coder/.vscode-server"
  local sdir="${vsc}/cli/servers/Stable-abc123/server"
  local ext="${vsc}/extensions"
  # Historical over-match 1: a path that merely contains /claude. The segment is
  # `claude-10001`, which is not the program `claude`.
  add_proc "$dir" 80 41 MainThread 700000000 "${sdir}/node" \
    "${sdir}/out/bootstrap-fork" --type=fileWatcher \
    --logsPath /tmp/claude-10001/-home-coder-code-coder/scratchpad
  # Historical over-match 2: the watchdog's own name appearing in an unrelated
  # path. Self-identity is structural now, so nothing here can match it.
  add_proc "$dir" 81 41 MainThread 600000000 "${sdir}/node" \
    "${ext}/redhat.vscode-yaml-1.24.0/dist/languageserver.js" \
    --config /home/coder/watchdog-live-evidence/memory-watchdog-run2/settings.json
  # The case the payload rule genuinely exists for: an agent session that an
  # extension started with the editor's own interpreter. argv[0] is VS Code's
  # node, so is_vscode_binary says "editor"; it is not under ptyHost, so the
  # positional rule never sees it.
  add_proc "$dir" 82 41 MainThread 900000000 "${sdir}/node" \
    "${ext}/anthropic.claude-code-2.1.232/resources/claude-code/cli.js" --ide
  # Outside the tree, and the reason argv[0] is consulted at all: for a script
  # with a shebang the kernel sets comm from the *interpreter*, so a launcher on
  # PATH called `claude` reports comm=bash.
  add_proc "$dir" 83 1 bash 500000000 /home/coder/.local/bin/claude --resume
  add_proc "$dir" 84 83 python3 800000000 /usr/bin/python3 -m mcp_server_git
}

test_guards_are_precise() {
  printf 'the guards are precise\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  local pdir="${WORK}/proc2f"
  build_tree "$pdir"
  add_decoys "$pdir"
  load_watchdog "${WORK}/cg" "$pdir"
  scan_fixture

  assert_protected 80 no "a helper whose log path contains /claude is not protected by it"
  assert_protected 81 no "nor is one whose config path contains memory-watchdog"
  assert_protected 82 yes "while a claude-code payload on VS Code's own node is"
  assert_eq payload "${PROTECT_REASON[82]}" "and it is the payload rule that claims it"
  assert_protected 83 yes "a shebang launcher named claude is protected"
  assert_eq argv0 "${PROTECT_REASON[83]}" "by argv[0], since its comm is the interpreter"
  assert_policed 84 claudeHelper "and its MCP server is policed, so the launcher counts as a session root"

  # Falsification: if the two decoys were unpoliced for some other reason, the
  # assertions above would pass against a watchdog that polices nothing.
  assert_policed 80 fileWatcher "decoy pid 80 is genuinely policed, so its non-protection means something"
  assert_policed 81 languageServer "and so is decoy pid 81"
  assert_policed 82 no "while the claude-code payload is policed by nothing"

  # Every guard the code can apply is applied to something here. A rule nothing
  # exercises is a rule nobody has established the correctness of.
  local want reasons=" " p
  for p in "${!PROTECT_REASON[@]}"; do
    reasons+="${PROTECT_REASON[$p]} "
  done
  for want in pid1 comm argv0 payload ptyhost foreign-binary; do
    if [[ $reasons == *" $want "* ]]; then
      ok "guard '${want}' is exercised by the fixture"
    else
      bad "guard '${want}' is never exercised - it is untested, not correct"
    fi
  done

  # And the watchdog's own kin, which is structural rather than named: the
  # harness process is this process, so it must claim itself.
  compute_watchdog_kin
  if [[ -n ${WATCHDOG_KIN[$$]:-} ]]; then
    ok "the watchdog recognises its own pid structurally"
  else
    bad "the watchdog does not recognise itself"
  fi
}

# --------------------------------------------------------------------------- #
# 2f. the tree helpers nothing used to name
#
# role_of returned `other` for three real processes on the live workspace, and
# compute_policed skips `other`, so they had no budget, no dwell clock, no
# signal and - the part that made it a design defect rather than a gap - no
# warning. The largest was a language server holding 280 MB PSS, already above
# the 256 MiB budget it would have been given had any pattern matched it.
#
# The fix inverts the default inside the tree: unknown means governed, not
# invisible. The risk that buys is a guessed budget applied to a process whose
# legitimate resting size is bigger than the guess, which is the failure this
# design has already shipped twice, so the guess is disarmed by default and the
# one shape that would be catastrophic - a core fork whose --type= flag stopped
# being recognised - is excluded structurally rather than hopefully.
# --------------------------------------------------------------------------- #

# role_of exactly as it was before the treeHelper fallback existed. Used as the
# mutation that must flip the coverage assertions red: with this in place the
# three processes below go back to being unpoliced and unreported, which is the
# bug, stated as a test.
mutate_role_of_to_other_fallback() {
  # shellcheck disable=SC2317,SC2329  # invoked indirectly, via the sourced watchdog
  role_of() {
    local cmd=" ${P_CMD[$1]:-} "
    local argv0=${P_ARGV0[$1]:-}
    case "$cmd" in
    *" --type=ptyHost "* | *"--type=ptyHost"*) ROLE=ptyHost ;;
    *" --type=extensionHost "*) ROLE=extensionHost ;;
    *" --type=fileWatcher "*) ROLE=fileWatcher ;;
    *"tsserver.js "* | *"/typescript/lib/tsserver"*) ROLE=tsserver ;;
    *yaml-language-server* | *jsonServerMain* | *-language-server* | *languageserver*) ROLE=languageServer ;;
    *"out/server-main.js "*) ROLE=serverMain ;;
    *)
      if [[ $argv0 == *"/.vscode-server/extensions/"* ]]; then
        ROLE=extensionHelper
      else
        ROLE=other
      fi
      ;;
    esac
    return 0
  }
}

test_tree_helpers() {
  printf 'in-tree helpers that no pattern names\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  local pdir="${WORK}/proc2f"
  build_tree "$pdir"
  load_watchdog "${WORK}/cg" "$pdir"
  scan_fixture

  # None of the role patterns reaches these, and the point is that none of them
  # ever could: the launch shape is each extension's own choice.
  role_of 55
  assert_eq treeHelper "$ROLE" "a built-in extension's server is a tree helper"
  role_of 56
  assert_eq treeHelper "$ROLE" "so is a user extension's server.js"
  role_of 57
  assert_eq treeHelper "$ROLE" "so is a helper's own helper, two levels down"

  assert_policed 55 treeHelper "and it is policed rather than skipped"
  assert_policed 56 treeHelper "including the one already over a language server's budget"
  assert_policed 57 treeHelper "including the grandchild"

  # The breadcrumb. Three unrelated extensions all ship a `server.js`, so the
  # script name alone re-hides exactly what this role exists to reveal.
  assert_eq "tamasfe.even-better-toml-0.21.2/server" "$(identity_of 56 treeHelper)" \
    "a tree helper is named for its extension, not just its script"
  assert_eq "markdown-language-features/serverWorkerMain" "$(identity_of 55 treeHelper)" \
    "including a built-in extension under the server's own extensions directory"
  assert_eq "typescript/typingsInstaller" "$(identity_of 57 treeHelper)" \
    "and node_modules is skipped for the name that means something"

  # This role used to be armed only under enforce-all, because its budget was a
  # guess and this design has twice shipped a limit below what a healthy process
  # already held. It now holds a named share of the envelope like every other
  # role and is armed like every other role; what protects a tree helper whose
  # legitimate size is larger than its share is the oversize rule, not an arming
  # exception. See section 3b.
  # shellcheck disable=SC2034  # MODE is a global of the sourced watchdog
  MODE=observe
  assert_armed treeHelper no "observe arms nothing, tree helpers included"
  # shellcheck disable=SC2034
  MODE=enforce
  assert_armed treeHelper yes "enforce arms tree helpers like everything else"
  assert_armed extensionHelper yes "and native extension helpers"
  assert_armed extensionHost yes "and the extension host"
  assert_armed serverMain yes "and the process holding the remote connection"
  # shellcheck disable=SC2034
  MODE=observe

  # A core fork whose --type= flag stopped being recognised. This is the shape
  # that makes inverting the default dangerous rather than merely uncertain: the
  # extension host holds 685 MB at rest, and handing it a 512 MiB helper budget
  # is a standing kill order on the largest, most user-visible process here.
  role_of 49
  assert_eq other "$ROLE" "an unrecognised core fork is NOT given a guessed helper budget"
  assert_policed 49 no "it is left unmanaged, where the sweep log still records it"

  # Falsification 1 - the guard that declines it is the only thing declining it.
  # shellcheck disable=SC2317,SC2329  # invoked indirectly, via the sourced watchdog
  is_server_fork() { return 1; }
  compute_policed
  assert_policed 49 treeHelper \
    "without the direct-child-of-the-root rule that core fork would be budgeted as a helper"
  # Re-source rather than hand-restore: a mutation left in place would silently
  # weaken every assertion after it, which is how this suite has been green
  # while testing nothing before.
  load_watchdog "${WORK}/cg" "$pdir"
  scan_fixture
  assert_policed 49 no "and with the real rule back it is unmanaged again"

  # Falsification 2 - the whole coverage claim, against the classifier that was
  # here before. If this does not flip, nothing above is evidence of anything.
  mutate_role_of_to_other_fallback
  compute_policed
  assert_policed 56 no "with the previous classifier the 280 MB language server is invisible"
  assert_policed 55 no "and so is the built-in server"
  assert_policed 57 no "and so is the typings installer"

  # Falsification 3 - argv[0], not tree position, is what separates a tree helper
  # from the operator's own runtime. Two synthetic processes identical in every
  # way except the binary they execute.
  load_watchdog "${WORK}/cg" "$pdir"
  scan_fixture
  local sdir="/home/coder/.vscode-server/cli/servers/Stable-abc123/server"
  local mnode="/home/coder/.local/share/mise/installs/node/22.14.0/bin/node"
  local args="/home/coder/.vscode-server/extensions/some.ext-1.0.0/dist/server.js --node-ipc"
  # shellcheck disable=SC2034  # globals of the sourced watchdog
  P_PPID[9002]=41 P_ARGV0[9002]="$mnode" P_CMD[9002]="${mnode} ${args}"
  # shellcheck disable=SC2034
  P_PPID[9003]=41 P_ARGV0[9003]="${sdir}/node" P_CMD[9003]="${sdir}/node ${args}"
  role_of 9002
  assert_eq other "$ROLE" "the operator's node in the tree is not a tree helper"
  role_of 9003
  assert_eq treeHelper "$ROLE" "VS Code's own node, same arguments, is"
  unset 'P_PPID[9002]' 'P_ARGV0[9002]' 'P_CMD[9002]'
  unset 'P_PPID[9003]' 'P_ARGV0[9003]' 'P_CMD[9003]'
}

# What enforce actually does to a drifted tree helper, end to end, because
# "armed" is a claim about behaviour and not about a string. This is the class of
# process the whole inverted default exists for: a helper no pattern names,
# holding 280 MB on the live tree, which used to be invisible and then for a
# while was visible but unenforceable.
test_tree_helper_arming_is_end_to_end() {
  printf 'a drifted tree helper is killed under enforce\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  local pdir="${WORK}/proc2g"
  build_tree "$pdir"

  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir" enforce
  # 287 MB is what this process was measured at, and it is inside the 320 MiB
  # share - so the fixture starts it fitting, and then drifts it out.
  sweep_at 1000
  set_pss "$pdir" 56 700000000
  sweep_at 1060
  sweep_at $((1060 + DWELL_SECONDS))
  assert_contains "$SIGNALS" "TERM:56" "a tree helper that drifted out of its share is shed"
  assert_absent "$SIGNALS" ":49" "and the unrecognised core fork is still never touched"
  assert_absent "$SIGNALS" ":41" \
    "nor the extension host, which never fitted and is therefore reported instead"

  # And the per-process record carries it as a budgeted role rather than as one
  # of the `unmanaged` rows it used to be lost among. 327680 kB is the 320 MiB
  # share in the sweep log's units.
  local latest
  latest="$(cat "${WORK}/state/sweep.latest")"
  assert_contains "$latest" "treeHelper" "the sweep log records the role"
  assert_contains "$latest" "327680" "with the share it is being held to"

  # Observe mode still only reports, for this role as for every other.
  SIGNALS=""
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir" observe
  set_pss "$pdir" 56 287000000
  sweep_at 2000
  set_pss "$pdir" 56 700000000
  sweep_at 2060
  sweep_at $((2060 + DWELL_SECONDS))
  assert_absent "$SIGNALS" ":56" "observe mode signals no tree helper"
  assert_contains "$(cat "${WORK}/state/actions.log")" \
    "event=would-kill armed=no pid=56 role=treeHelper" \
    "but says exactly what it would have done, with the identity to act on"
  set_pss "$pdir" 56 287000000
}

# --------------------------------------------------------------------------- #
# 3. the envelope and its shares
#
# The construction under test is one sentence: the VS Code tree gets a fixed
# 2048 MiB envelope, each role holds a named share of it that does not vary with
# pod size, and everything with a budget is armed under enforce.
#
# So the assertions here are *properties*, not one pod's arithmetic. The three
# terms this replaced - a per-role constant, a memory.max/8 share and a
# resting x 1.5 floor - could each be checked on the 8 GiB pod and pass while the
# total was unbounded, which is how a design with no bound on the sum passed a
# budget suite twice.
# --------------------------------------------------------------------------- #

POD_SIZES="2147483648 4294967296 8589934592 17179869184 68719476736"

budgets_at() {
  BUDGET=()
  derive_budgets
}

test_envelope() {
  printf 'the envelope\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  load_watchdog "${WORK}/cg" "${WORK}/proc2"

  # The apportionment, named. These are the numbers a reviewer is arguing with,
  # so they are asserted individually rather than only as a sum: a change to one
  # of them should have to be made here as well as in the script.
  budgets_at
  assert_eq 536870912 "${BUDGET[serverMain]}" "serverMain holds 512 MiB"
  assert_eq 503316480 "${BUDGET[extensionHost]}" "the extension host holds 480 MiB"
  assert_eq 335544320 "${BUDGET[tsserver]}" "tsserver holds 320 MiB"
  assert_eq 335544320 "${BUDGET[treeHelper]}" "a tree helper holds 320 MiB"
  assert_eq 167772160 "${BUDGET[fileWatcher]}" "the file watcher holds 160 MiB"
  assert_eq 134217728 "${BUDGET[languageServer]}" "a language server holds 128 MiB"
  assert_eq 134217728 "${BUDGET[extensionHelper]}" "an extension helper holds 128 MiB"
  assert_eq 536870912 "${BUDGET[claudeHelper]}" "an MCP server holds 512 MiB, outside the envelope"

  # Property 1: the shares add up to the envelope, at every pod size. This is the
  # assertion the old construction could not have had - min(x, memory.max/8) and
  # a resting floor have no sum to check. Mutation: change any single share, or
  # reintroduce a term that scales one with the pod, and this goes red at some
  # pod size.
  local m total role
  for m in $POD_SIZES; do
    write_cgroup "${WORK}/cg" "$m" 0.00
    read_cgroup_memory
    budgets_at
    total=$(envelope_in_force)
    assert_eq "$ENVELOPE" "$total" "memory.max=${m}: the shares in force add up to the envelope"
  done

  # Property 2: and they are the *same* shares at every pod size. Summing to the
  # envelope is not enough on its own - two roles could trade with each other as
  # the pod changed and still sum correctly.
  local -A at8=()
  write_cgroup "${WORK}/cg" 8589934592 0.00
  read_cgroup_memory
  budgets_at
  for role in "${!BUDGET[@]}"; do at8[$role]=${BUDGET[$role]}; done
  for m in $POD_SIZES; do
    write_cgroup "${WORK}/cg" "$m" 0.00
    read_cgroup_memory
    budgets_at
    for role in "${!BUDGET[@]}"; do
      # shellcheck disable=SC2004
      # The $ is NOT unnecessary: these are associative arrays, so inside (( ))
      # the subscript is a string. Dropping it looks up the literal key "role"
      # and silently reads 0, which would make this pass for every role.
      if ((BUDGET[$role] == at8[$role])); then
        ok "memory.max=${m}: the ${role} share is the same number it is on any other pod"
      else
        bad "memory.max=${m}: the ${role} share moved with the pod (${BUDGET[$role]} vs ${at8[$role]})"
      fi
    done
  done
  write_cgroup "${WORK}/cg" 8589934592 0.00
  read_cgroup_memory
  budgets_at

  # Property 3: what the removed memory.max/8 divisor was protecting against - a
  # budget reasoned about for the large pod letting one role own a quarter of the
  # small one - still holds, now by construction rather than by arithmetic. The
  # smallest pod this template offers is 4 GiB.
  local smallest=4294967296
  for role in "${!BUDGET[@]}"; do
    # shellcheck disable=SC2004
    # The $ is NOT unnecessary: BUDGET is associative, so inside (( )) the
    # subscript is a string, and dropping it looks up the literal key "role" and
    # silently reads 0 - which would make this assertion pass for every role.
    if ((BUDGET[$role] <= smallest / 8)); then
      ok "the ${role} share is within an eighth of the smallest supported pod"
    else
      bad "the ${role} share (${BUDGET[$role]}) exceeds an eighth of a 4 GiB pod - the divisor's protection is gone"
    fi
  done

  # Property 4: the connection-holding process has the largest single share. It
  # is the operator's rule and it is allocated by consequence rather than by
  # size, so nothing in the numbers themselves would catch a later edit that
  # broke it.
  local biggest="" role
  for role in ${ENVELOPE_ROLES}; do
    # shellcheck disable=SC2004
    if [[ -z $biggest ]] || ((BUDGET[$role] > BUDGET[$biggest])); then biggest=$role; fi
  done
  assert_eq serverMain "$biggest" "the process holding the remote connection has the largest share"
  for role in ${ENVELOPE_ROLES}; do
    [[ $role == serverMain ]] && continue
    # shellcheck disable=SC2004
    if ((BUDGET[$role] < BUDGET[serverMain])); then
      ok "and ${role} is strictly smaller, so the largest share is unambiguous"
    else
      bad "${role} ties or beats serverMain - there is no single largest share"
    fi
  done

  # Property 5: BUDGET_ORDER names every declared role and nothing else. It is
  # what the budget report iterates, and a literal list at a reporting call site
  # is exactly where a fully-enforced share goes unreported.
  local listed=" ${BUDGET_ORDER// / } "
  for role in "${!BUDGET_ROLE[@]}"; do
    assert_contains "$listed" " ${role} " "BUDGET_ORDER names ${role}"
  done
  for role in ${BUDGET_ORDER}; do
    if [[ -n ${BUDGET_ROLE[$role]:-} ]]; then
      ok "BUDGET_ORDER's ${role} is a declared role"
    else
      bad "BUDGET_ORDER names ${role}, which has no budget"
    fi
  done
  assert_eq "${#BUDGET_ROLE[@]}" "$(printf '%s\n' ${BUDGET_ORDER} | wc -l)" \
    "and names each of them exactly once"

  # Property 6: every role inside the envelope is armed under enforce, and none
  # is armed under observe. A share that cannot be signalled is a share that is
  # not enforced, which would make the envelope a description of the tree rather
  # than a bound on it.
  #
  # Mutation: restore the old `enforce) [[ $HELPER_ROLES == *" $role "* ]]`
  # clause and the extensionHost, serverMain and treeHelper assertions go red.
  # shellcheck disable=SC2034
  MODE=observe
  for role in "${!BUDGET_ROLE[@]}"; do
    assert_armed "$role" no "observe arms nothing, ${role} included"
  done
  # shellcheck disable=SC2034
  MODE=enforce
  for role in "${!BUDGET_ROLE[@]}"; do
    assert_armed "$role" yes "enforce arms ${role}"
  done
  # A role with no declared budget is armed by nothing, in any mode: arming keys
  # on having a share, so a future role added without one cannot be signalled on
  # a budget of zero.
  assert_armed somethingNew no "a role with no share is armed by nothing"
  # shellcheck disable=SC2034
  MODE=observe

  # An explicit budget must win, or a number cannot be tried on a live workspace
  # without editing the script under test.
  BUDGET=()
  WATCHDOG_BUDGET_extensionHost=268435456 derive_budgets
  assert_eq 268435456 "${BUDGET[extensionHost]}" "an explicit budget overrides the declared share"
  assert_eq 536870912 "${BUDGET[serverMain]}" "while the rest is unchanged"
  # And an override that breaks the total says so, rather than leaving a sum
  # nobody can reconstruct from the log.
  local overridden
  overridden=$(envelope_in_force)
  if ((overridden != ENVELOPE)); then
    ok "an override that changes the total is visible as a total"
  else
    bad "an override moved a share without moving the sum - envelope_in_force is not summing the shares in force"
  fi
  budgets_at

  # The budget report is what a reviewer reads the apportionment out of, so it
  # has to carry the envelope and not only the per-role number.
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "${WORK}/proc2" enforce
  read_uptime
  # cycle_once only reports the budgets on the cycle that installs them, and
  # load_watchdog has already installed them.
  BUDGET=()
  cycle_once 1000 >/dev/null 2>&1
  local actions
  actions="$(cat "${WORK}/state/actions.log" 2>/dev/null)"
  assert_contains "$actions" "event=budget role=serverMain budget_mb=512" \
    "the report names each share in MiB"
  assert_contains "$actions" "envelope=yes" "and says which roles are inside the envelope"
  assert_contains "$actions" "event=budget role=claudeHelper budget_mb=512 envelope=no" \
    "and that the MCP server budget is not one of them"
  assert_contains "$actions" "shares_sum_mb=2048 " "and publishes the total the shares add up to"
  assert_absent "$actions" "event=warning reason=envelope-mismatch" \
    "with no mismatch to report when the shares are the declared ones"
}

# --------------------------------------------------------------------------- #
# 3b. drift is killed; what never fitted is reported
#
# This is the mechanism that replaced the resting x 1.5 floor, and it has to be
# tested as the pair it is: the same role, the same budget, the same final size,
# and opposite outcomes decided only by whether the process was ever seen inside
# its share.
#
# What the floor protected against was a share that lands below what a healthy
# process already holds, which under enforcement is a kill loop with a
# supervisor's restart in the middle of it. A floor cannot survive an envelope -
# enough floors push the sum past the total - so the protection moved to the
# process: nothing that has never fitted is signalled.
# --------------------------------------------------------------------------- #

test_oversize_is_reported_not_killed() {
  printf 'a process that never fitted is reported, not killed\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  local pdir="${WORK}/proc3b"
  build_tree "$pdir"
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir" enforce

  # The extension host as the live pod actually has it: 738 MB against a 480 MiB
  # share, over from the first sweep and for its whole observed life.
  local t=1000
  sweep_at $t
  t=$((t + DWELL_SECONDS + 60))
  sweep_at $t
  assert_absent "$SIGNALS" ":41" "an extension host that has never fitted is not killed"
  assert_contains "$(cat "${WORK}/state/actions.log")" "event=oversize pid=41 role=extensionHost" \
    "it is reported instead, with the identity to act on"
  assert_contains "$(cat "${WORK}/state/sweep.latest")" "oversize" \
    "and the sweep row says which of the two cases this is"
  # It keeps saying so. A mechanism that reports a structural problem once and
  # then goes quiet is indistinguishable from one that fixed it.
  : >"${WORK}/state/actions.log"
  t=$((t + DWELL_SECONDS + 60))
  sweep_at $t
  assert_contains "$(cat "${WORK}/state/actions.log")" "event=oversize pid=41" \
    "and goes on saying so once per dwell period, indefinitely"

  # The pair. Same process, same role, same 738 MB, same budget - but this one is
  # seen inside its share first, so it drifted rather than never fitted.
  #
  # Mutation: delete the `[[ -z ${FIT_SEEN[$key]:-} ]]` branch in sweep_once and
  # the first half of this test goes red (41 is killed); delete the FIT_SEEN
  # assignment and the second half goes red (41 is never killed).
  SIGNALS=""
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir" enforce
  set_pss "$pdir" 41 400000000 # inside the 480 MiB share
  t=5000
  sweep_at $t
  assert_eq 1 "${FIT_SEEN[41:100]:-0}" "a process seen inside its share is recorded as having fitted"
  set_pss "$pdir" 41 738000000
  t=$((t + 60))
  sweep_at $t
  t=$((t + DWELL_SECONDS))
  sweep_at $t
  assert_contains "$SIGNALS" "TERM:41" "and when it later drifts out of it, it is killed"
  set_pss "$pdir" 41 738000000

  # The fit evidence is only taken from a process old enough to have finished
  # starting up. Without that, the classification would depend on whether a sweep
  # happened to catch the process in the seconds after exec, when everything is
  # small - a race, decided by sweep timing rather than by the process.
  #
  # Mutation: drop `age >= MIN_AGE` from the FIT_SEEN assignment and this goes
  # red, because the young small observation would arm the kill.
  SIGNALS=""
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir" enforce
  set_age "$pdir" 41 30
  set_pss "$pdir" 41 100000000
  t=8000
  sweep_at $t
  assert_eq 0 "${FIT_SEEN[41:$((( UPTIME_S - 30 ) * 100))]:-0}" \
    "a small reading from a process that has just started proves nothing"
  set_age "$pdir" 41 50000
  set_pss "$pdir" 41 738000000
  t=$((t + DWELL_SECONDS + 600))
  sweep_at $t
  t=$((t + DWELL_SECONDS + 600))
  sweep_at $t
  assert_absent "$SIGNALS" ":41" "so it is still oversize once it is old and large"
  set_pss "$pdir" 41 738000000

  # And the whole rule is inert in observe mode, like everything else - but it
  # reports the *right* one of the two cases, which is the evidence anyone needs
  # before arming this on a live workspace.
  SIGNALS=""
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir" observe
  t=20000
  set_pss "$pdir" 61 200000000
  sweep_at $t
  set_pss "$pdir" 61 1660000000
  t=$((t + 60))
  sweep_at $t
  t=$((t + DWELL_SECONDS + 60))
  sweep_at $t
  assert_eq "" "$SIGNALS" "observe mode signals nothing either way"
  local obs
  obs="$(cat "${WORK}/state/actions.log")"
  assert_contains "$obs" "event=oversize pid=41" \
    "and calls the extension host oversize rather than would-kill"
  assert_contains "$obs" "event=would-kill armed=no pid=61" \
    "while a helper that did fit and then drifted is still reported as a kill it would have made"
}

# --------------------------------------------------------------------------- #
# 4. dwell: drift is killed, load is not
#
# The whole point of a dwell requirement is that a helper which balloons while
# doing work and then hands the memory back is load, not drift. A watchdog
# without one would kill tsserver every time it indexed a large project, which is
# the "disruption every fifteen minutes" that gets the thing switched off.
# --------------------------------------------------------------------------- #

test_dwell() {
  printf 'dwell\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  local pdir="${WORK}/proc4"
  build_tree "$pdir"
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir" enforce

  # The python MCP server, first at a size a healthy one was actually measured
  # at and then at the 1.66 GB the offending one reached. It has to be seen
  # fitting before it can be said to have drifted - a process that was never
  # inside its share is the other case entirely, and section 3b owns it.
  local t=900
  set_pss "$pdir" 61 200000000
  sweep_at $t
  set_pss "$pdir" 61 1660000000
  t=1000
  sweep_at $t
  assert_eq "" "$SIGNALS" "the first sweep over budget signals nothing"
  assert_eq "$t" "${OVER_SINCE[61:100]}" "but it starts the dwell clock"

  t=$((t + DWELL_SECONDS - 60))
  sweep_at $t
  assert_eq "" "$SIGNALS" "nor does one just short of the dwell period"

  t=$((t + 60))
  sweep_at $t
  assert_eq "TERM:61 " "$SIGNALS" "and at the dwell period it is asked to exit"
  assert_eq 1 "${KILLS[claudeHelper]:-0}" "the kill is counted against its role"

  # It ignored SIGTERM. The escalation is deliberately not an in-loop sleep: a
  # process shutting down politely gets the whole grace period.
  SIGNALS=""
  t=$((t + KILL_GRACE - 5))
  sweep_at $t
  assert_eq "" "$SIGNALS" "inside the grace period it is left alone"
  t=$((t + 10))
  sweep_at $t
  assert_eq "KILL:61 " "$SIGNALS" "past it, SIGKILL"

  # Load, not drift: a helper that goes over budget and comes back must survive.
  SIGNALS=""
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir" enforce
  t=2000
  set_pss "$pdir" 44 900000000 # tsserver indexing, well over its 320 MiB share
  sweep_at $t
  t=$((t + 300))
  sweep_at $t
  set_pss "$pdir" 44 208000000 # indexing finished, memory handed back
  t=$((t + 60))
  sweep_at $t
  assert_eq "" "${OVER_SINCE[44:100]:-}" "coming back under budget clears the dwell clock"
  t=$((t + DWELL_SECONDS))
  sweep_at $t
  assert_absent "$SIGNALS" "44" "a helper that recovered is never killed for the earlier excursion"

  # Young processes are exempt: something over budget seconds after it started is
  # a spike, and spikes are the kernel's problem, not this one's.
  SIGNALS=""
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir" enforce
  set_age "$pdir" 62 30
  set_pss "$pdir" 62 900000000
  t=3000
  sweep_at $t
  t=$((t + DWELL_SECONDS + 60))
  sweep_at $t
  assert_absent "$SIGNALS" "62" "a process younger than MIN_AGE is not killed for drift"
  set_age "$pdir" 62 50000
  set_pss "$pdir" 62 200000000
}

# --------------------------------------------------------------------------- #
# 4b. the kill rate is reported, and disarms nothing
#
# There used to be a circuit breaker here: LOOP_KILLS kills of one role inside
# LOOP_WINDOW disarmed that role permanently. It was protecting against the kill
# loop - kill the extension host, VS Code restarts it, it reloads every
# extension, it exceeds again, kill - which is the failure that arrives looking
# exactly like the watchdog working.
#
# Under a deliberate envelope that inference no longer holds: repeated kills can
# mean the process does not fit in the share it was given, which is a decision
# rather than a defect, and a mechanism that switches itself off after three of
# them is inert by mid-morning. The loop itself is prevented by the oversize rule
# instead (section 3b), which is why removing the breaker does not put it back.
#
# So this section asserts the *negative*: however many times a role is killed,
# enforcement continues, and the rate is reported.
# --------------------------------------------------------------------------- #

test_kill_rate_is_reported_and_nothing_disarms() {
  printf 'the kill rate is reported and disarms nothing\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  local pdir="${WORK}/proc4b"
  build_tree "$pdir"
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir" enforce

  # Each incarnation is seen inside its share first and then drifts out of it, so
  # every one of them is a genuine drift kill rather than an oversize report.
  # That is what makes this a test of the rate rather than of the oversize rule.
  local t=1000 i n=$((LOOP_KILLS + 2))
  for ((i = 1; i <= n; i++)); do
    printf '%s (python3) S 60 1 1 0 -1 4194560 0 0 0 0 0 0 0 0 20 0 1 0 %s\n' \
      61 $((i * 1000)) >"${pdir}/61/stat"
    set_pss "$pdir" 61 200000000 # inside the 512 MiB share
    sweep_at $t
    set_pss "$pdir" 61 1660000000 # the 1.66 GB it was actually measured at
    t=$((t + 60))
    sweep_at $t
    t=$((t + DWELL_SECONDS))
    sweep_at $t
    t=$((t + 60))
  done
  assert_eq "$n" "${KILLS[claudeHelper]:-0}" \
    "the role is killed once per incarnation, past the old breaker threshold and beyond"

  local actions
  actions="$(cat "${WORK}/state/actions.log")"
  assert_contains "$actions" "event=kill-rate role=claudeHelper" \
    "the rate is reported once it crosses the threshold"
  assert_contains "$actions" "enforcing=yes" "and the report says enforcement continues"
  assert_absent "$actions" "event=disarmed" "nothing is disarmed"
  assert_absent "$(cat "${WORK}/state/sweep.latest")" "disarmed" \
    "and no process is recorded as deliberately spared for that reason"

  # The falsification for the whole section: the last kill must be a real signal,
  # not a leftover from before the threshold. Mutation: restore
  # `DISARMED[$role]=1` in record_kill and this goes red.
  SIGNALS=""
  printf '%s (python3) S 60 1 1 0 -1 4194560 0 0 0 0 0 0 0 0 20 0 1 0 99000\n' 61 \
    >"${pdir}/61/stat"
  set_pss "$pdir" 61 200000000
  sweep_at $t
  set_pss "$pdir" 61 1660000000
  t=$((t + 60))
  sweep_at $t
  t=$((t + DWELL_SECONDS))
  sweep_at $t
  assert_contains "$SIGNALS" "TERM:61" \
    "a role well past the old breaker threshold is still enforced"

  # The report is a rate and not a count: kills spread beyond the window must not
  # produce it, or any long-lived workspace would eventually report one for
  # nothing.
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir" enforce
  # shellcheck disable=SC2034  # a global of the sourced watchdog
  LOOP_WINDOW=60
  t=10000
  for ((i = 1; i <= LOOP_KILLS; i++)); do
    record_kill claudeHelper $t
    t=$((t + 600))
  done
  assert_absent "$(cat "${WORK}/state/actions.log" 2>/dev/null)" "event=kill-rate role=claudeHelper" \
    "kills spread beyond the window are not reported as a rate"

  # And the same idea across roles.
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir" enforce
  t=20000
  for ((i = 1; i <= GLOBAL_LOOP_KILLS; i++)); do
    record_kill "role${i}" $t
  done
  assert_contains "$(cat "${WORK}/state/actions.log" 2>/dev/null)" "event=kill-rate role=all" \
    "enough kills across unrelated roles is reported too"
}

# --------------------------------------------------------------------------- #
# 4c. a kill already in flight is finished
#
# A drill on a disposable workspace found this by accident under the old
# breaker: it tripped between a process's SIGTERM and its SIGKILL, the disarm
# branch short-circuited ahead of the escalation, and the process was left alive,
# still over budget, signalled, abandoned, and recorded as neither killed nor
# spared. Nothing in the code or the docs said which of those was intended, so it
# was not a defect anyone could have reviewed.
#
# The breaker is gone but the ladder still has a branch that can short-circuit an
# escalation - the oversize rule - and the lesson is the same one: "do not decide
# to kill this" is not "abandon a kill already decided". Leaving a process
# half-signalled is the worst of both outcomes. So the escalation branch is
# tested first, and this asserts it, by taking the fit evidence away between the
# SIGTERM and the SIGKILL.
#
# Mutation: move the `[[ -z ${FIT_SEEN[$key]:-} ]]` branch above the
# `[[ -n ${KILLED_AT[$key]:-} ]]` branch and this goes red.
# --------------------------------------------------------------------------- #

test_an_escalation_in_flight_is_finished() {
  printf 'a kill already in flight is finished, not abandoned\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  local pdir="${WORK}/proc4c"
  build_tree "$pdir"
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir" enforce

  # 61 fits, drifts, and is asked politely.
  set_pss "$pdir" 61 200000000
  sweep_at 900
  set_pss "$pdir" 61 1660000000
  sweep_at 1000
  sweep_at $((1000 + DWELL_SECONDS))
  assert_contains "$SIGNALS" "TERM:61" "the drifted helper gets a SIGTERM"
  assert_absent "$SIGNALS" "KILL:61" "and not yet a SIGKILL"
  local kills_before=${KILLS[claudeHelper]:-0}

  # The fit evidence disappears while that SIGTERM is outstanding - which is what
  # a pid:starttime key change, or a pruning bug, would look like from inside the
  # ladder.
  unset 'FIT_SEEN[61:100]'
  SIGNALS=""
  sweep_at $((1000 + DWELL_SECONDS + KILL_GRACE))
  assert_contains "$SIGNALS" "KILL:61" \
    "the escalation completes rather than leaving the process half-signalled"
  assert_eq "$kills_before" "${KILLS[claudeHelper]:-0}" \
    "it is the same kill, so the rate does not count it twice"

  # The other half: a process that never fitted starts nothing, however far it
  # has drifted. 62 is a different process of the same role.
  SIGNALS=""
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir" enforce
  set_pss "$pdir" 62 900000000
  sweep_at 5000
  sweep_at $((5000 + DWELL_SECONDS))
  assert_absent "$SIGNALS" ":62" \
    "a process that never fitted begins no kill at all"
  assert_contains "$(cat "${WORK}/state/sweep.latest")" "oversize" \
    "and says it is deliberately sparing it"
  set_pss "$pdir" 62 200000000
}

# --------------------------------------------------------------------------- #
# 5. observe mode really is inert, and says what it would have done
# --------------------------------------------------------------------------- #

test_observe_mode() {
  printf 'observe mode\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  local pdir="${WORK}/proc5b"
  build_tree "$pdir"
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir" observe

  local t=900
  set_pss "$pdir" 61 200000000
  sweep_at $t
  set_pss "$pdir" 61 1660000000
  t=1000
  sweep_at $t
  t=$((t + DWELL_SECONDS))
  sweep_at $t
  assert_eq "" "$SIGNALS" "observe mode signals nothing"
  local log
  log="$(cat "${WORK}/state/actions.log")"
  assert_contains "$log" "event=would-kill armed=no pid=61" \
    "but it logs the kill it would have made"
  assert_contains "$log" "mode=observe" "and records the mode it was in"
  assert_eq 0 "${KILLS[claudeHelper]:-0}" "a kill it did not make is not counted"
  assert_contains "$(cat "${WORK}/state/sweep.latest")" "would-kill" \
    "the sweep row says would-kill rather than killed"

  # enforce-all is the retired third mode. It must not fall through to observe:
  # a workspace still carrying the stored value asked for more enforcement, not
  # for none, so it is honoured as enforce. This is asserted by behaviour rather
  # than by reading MODE, because the fallback that matters is the one in main().
  SIGNALS=""
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir" enforce-all
  MODE=enforce-all
  normalise_mode
  assert_eq enforce "$MODE" "the retired enforce-all mode is honoured as enforce"
  MODE=somethingElse
  normalise_mode
  assert_eq observe "$MODE" "and an unrecognised mode still falls back to the inert one"
  # shellcheck disable=SC2034
  MODE=enforce
  set_pss "$pdir" 61 200000000
  t=8000
  sweep_at $t
  set_pss "$pdir" 61 1660000000
  t=$((t + 60))
  sweep_at $t
  t=$((t + DWELL_SECONDS))
  sweep_at $t
  assert_contains "$SIGNALS" "TERM:61" "and it enforces"
  set_pss "$pdir" 61 1660000000
}

# --------------------------------------------------------------------------- #
# 6. the sweep log
#
# Every post-mortem in this investigation was unanswerable because the watchdog
# computed this table on every cycle and threw it away. The log is therefore a
# deliverable in its own right, not decoration on the killing.
# --------------------------------------------------------------------------- #

test_sweep_log() {
  printf 'the sweep log\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  local pdir="${WORK}/proc6"
  build_tree "$pdir"
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir" observe
  sweep_at 1000

  local log
  log="$(cat "${WORK}/state/sweep.log")"
  assert_contains "$log" "pss_kb" "the log carries a header naming its columns"
  assert_contains "$log" "	extensionHost	" "a policed process appears with its role"
  assert_contains "$log" "	claudeHelper	" "so does an MCP server"
  assert_contains "$log" "homelab_mcp.server" "with the identity that survives a restart"
  assert_contains "$log" "	TOTAL	" "and each sweep ends with a totals row"
  assert_contains "$log" "policed=" "which carries the census"

  # The processes it does NOT manage are the ones every OOM in this investigation
  # actually involved, so they are recorded too - as unmanaged, not as absent.
  assert_contains "$log" "	unmanaged	" "large unmanaged processes are recorded"
  local line
  line=$(printf '%s\n' "$log" | grep -m1 '	60	')
  assert_contains "$line" "unmanaged" "including the agent session itself"

  # Small processes are not, or a sweep is a hundred rows of shells.
  if printf '%s\n' "$log" | grep -q '	31	'; then
    bad "a 3 MB shell was written to the sweep log"
  else
    ok "processes below the log floor are omitted"
  fi

  # Secrets in argv are redacted at the point of writing, because this file is
  # the one thing here that might later be shipped somewhere.
  assert_absent "$log" "remotessh" "a connection token never reaches the log"
  assert_eq "node --connection-token=<redacted> --start" \
    "$(redact "node --connection-token=remotessh --start")" \
    "the value is replaced in place, so the shape is still visible"
  assert_eq "python3 --api-key=<redacted>" "$(redact "python3 --api-key=sk-live-1234")" \
    "and the same for a key on an MCP server's command line"

  # The summary file is what the operator reads first, so its numbers have to be
  # the real ones. Asserted because they were not: `$((BUDGET[role]))` reads the
  # *key* "role" inside an arithmetic context and every budget printed as 0M,
  # which looked like a watchdog with no budgets at all.
  publish_summary 1000
  local summary
  summary="$(cat "${WORK}/state/summary")"
  assert_contains "$summary" "claudeHelper=512M" "the summary prints real budgets"
  assert_contains "$summary" "extensionHost=480M" "including its share of the envelope"
  assert_contains "$summary" "envelope=2048M" "and the envelope those shares add up to"
  assert_contains "$summary" "tree_pss=" "beside what the tree is actually holding against it"
  assert_contains "$summary" "policed=" "and the size of the policed set"

  # The visibility check: a watchdog that manages nothing looks exactly like a
  # watchdog with nothing to do, and only the log can tell them apart.
  rm -rf "${WORK}/state"
  local empty="${WORK}/proc6b"
  mkdir -p "$empty"
  write_uptime "$empty"
  add_proc "$empty" 1 0 coder 14208 ./coder agent
  load_watchdog "${WORK}/cg" "$empty" observe
  local i
  for ((i = 0; i <= VISIBILITY_WARMUP; i++)); do
    sweep_at $((1000 + i))
    check_visibility
  done
  assert_contains "$(cat "${WORK}/state/actions.log")" "event=warning reason=nothing-policed" \
    "an empty policed set is reported rather than passing for health"

  # And it is a warning per *episode of blindness*, not per process lifetime.
  # The latch used to be set at the warmup sweep whether or not it warned, and
  # the condition it tested was a lifetime high-water mark, so a watchdog that
  # policed something once in its first half hour could never warn again however
  # blind it went later. A pod lives for days and the interesting blind spot is
  # the one that arrives on day two, when an upgrade changes a launch shape.
  #
  # Falsification: each half of this is asserted against the fixture that must
  # flip it. A watchdog that warns while it is policing something is crying wolf;
  # one that cannot warn twice is the bug being fixed.
  rm -rf "${WORK}/state"
  local pdir="${WORK}/proc6c"
  build_tree "$pdir"
  load_watchdog "${WORK}/cg" "$pdir" observe
  for ((i = 0; i <= VISIBILITY_WARMUP; i++)); do
    sweep_at $((2000 + i))
    check_visibility
  done
  assert_absent "$(cat "${WORK}/state/actions.log")" "reason=nothing-policed" \
    "a watchdog that is policing something does not warn about blindness"

  # Now selection goes blind, with the same process table it was managing a
  # moment ago - which is what a launch-shape change looks like from in here.
  # shellcheck disable=SC2317,SC2329  # invoked indirectly, via the sourced watchdog
  compute_policed() { POLICED=(); }
  for ((i = 0; i <= VISIBILITY_WARMUP; i++)); do
    sweep_at $((3000 + i))
    check_visibility
  done
  assert_contains "$(cat "${WORK}/state/actions.log")" "reason=nothing-policed" \
    "a blind spot that appears later in the pod's life is still reported"
}

# --------------------------------------------------------------------------- #
# 6b. the action lines reach the container's stdout
#
# The cluster's log agent tails container stdout and nothing else, and PID 1 in
# the workspace container is the coder agent - so /proc/1/fd/1 is the only route
# out of this pod, and it is free. What goes through it is deliberately limited
# to actions: the sweep is dozens of rows a minute and belongs in the local file.
# --------------------------------------------------------------------------- #

test_stdout_emission() {
  printf 'action lines reach container stdout\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  local pdir="${WORK}/proc6c"
  build_tree "$pdir"
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir" enforce

  # Driven through cycle_once rather than sweep_once, because the budget and
  # census lines are emitted by the cycle and a test that only swept would be
  # asserting on half the output.
  # shellcheck disable=SC2034  # globals of the sourced watchdog
  SWEEP_EVERY=1
  # Emptied so the first cycle installs its budgets exactly as the daemon does at
  # startup, and emits them.
  BUDGET=()
  local t=1000
  # Seen inside its share first, so what follows is a drift kill rather than the
  # oversize report a process that never fitted would get.
  set_pss "$pdir" 61 200000000
  cycle_once $t
  set_pss "$pdir" 61 1660000000
  t=$((t + 60))
  cycle_once $t
  # shellcheck disable=SC2034  # a global of the sourced watchdog
  CYCLE=1
  t=$((t + DWELL_SECONDS))
  cycle_once $t

  local out
  out="$(cat "$STDOUT_FILE")"
  assert_contains "$out" "event=kill sig=TERM" "a kill is emitted to stdout"
  assert_contains "$out" "event=budget role=" "so are the budgets in force"
  assert_contains "$out" "envelope_pct=" "including each share as a fraction of the envelope"
  assert_contains "$out" "event=oversize pid=41 role=extensionHost" \
    "and the structurally-over-budget extension host, which is the case a post-mortem cannot otherwise tell from a drift"
  assert_contains "$out" "event=census" "and a census line"
  assert_contains "$out" "id=homelab_mcp.server" "with the identity breadcrumb, not just a pid"
  assert_contains "$out" "top_role=" "and the census carries the standing population's largest member"

  # Queryable without anyone adding a stream label: every line is logfmt and
  # starts with the same key, so `|= "component=memory-watchdog" | logfmt` works.
  local line n=0 bad_lines=0
  while IFS= read -r line; do
    [[ -z $line ]] && continue
    n=$((n + 1))
    [[ $line == "component=memory-watchdog time="* ]] || bad_lines=$((bad_lines + 1))
    [[ $line == *" event="* ]] || bad_lines=$((bad_lines + 1))
  done <"$STDOUT_FILE"
  assert_eq 0 "$bad_lines" "every emitted line is logfmt with component and event first (${n} lines)"

  # Free text is quoted, so a sentence in detail= cannot become five bogus keys.
  record_action "event=warning reason=test detail=@a sentence with spaces in it@"
  out="$(cat "$STDOUT_FILE")"
  assert_contains "$out" 'detail="a sentence with spaces in it"' \
    "free text is quoted rather than spilling into the parse"
  assert_absent "$out" "detail=a sentence" "an unquoted sentence never reaches the line"

  # The volume rule: the sweep stays local. This is the assertion that stops a
  # later change from putting forty thousand rows a day into the log pipeline.
  assert_absent "$out" "	unmanaged	" "sweep rows are not emitted to stdout"
  assert_absent "$out" "pss_kb" "nor the sweep header"
  assert_contains "$(cat "${WORK}/state/sweep.log")" "	unmanaged	" "they are in the local sweep log"

  # Observe mode emits what it *would* have done, which is the data anyone needs
  # before arming this on a live workspace.
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir" observe
  t=5000
  set_pss "$pdir" 61 200000000
  sweep_at $t
  set_pss "$pdir" 61 1660000000
  t=$((t + 60))
  sweep_at $t
  t=$((t + DWELL_SECONDS))
  sweep_at $t
  out="$(cat "$STDOUT_FILE")"
  assert_contains "$out" "event=would-kill armed=no" "observe mode emits the kill it would have made"
  assert_contains "$out" "mode=observe" "labelled with the mode, so the two cannot be confused"
  assert_absent "$out" "event=kill " "and never emits a kill it did not make"

  # Best effort, always. The fd may not be writable in some contexts, and a
  # watchdog that died because logging failed would be worse than any bug it
  # prevents.
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir" enforce
  # shellcheck disable=SC2034  # a global of the sourced watchdog
  STDOUT_PATH="${WORK}/no-such-dir/stdout.log"
  record_action "event=kill sig=TERM pid=1234 role=claudeHelper"
  assert_eq 0 "$STDOUT_OK" "an unwritable stdout path disables itself"
  local log
  log="$(cat "${WORK}/state/actions.log")"
  assert_contains "$log" "reason=stdout-unavailable" "and says so once, locally"
  assert_contains "$log" "event=kill sig=TERM pid=1234" "while the local record is unaffected"
  record_action "event=kill sig=TERM pid=1235 role=claudeHelper"
  assert_contains "$(cat "${WORK}/state/actions.log")" "pid=1235" "and later actions still record"
  assert_eq 1 "$(grep -c "reason=stdout-unavailable" "${WORK}/state/actions.log")" \
    "the warning is not repeated on every action"
}

# --------------------------------------------------------------------------- #
# 7. a stale pidfile does not disarm the watchdog forever
#
# Found on the live test workspace, not here. The pod was OOM-killed, the
# watchdog died by SIGKILL without running its EXIT trap, and its pidfile
# survived on the NFS-backed home directory. Every restart afterwards logged
# "another instance is already running" and exited - so the first kill left the
# pod unwatched from then on, which is the worst possible time for that.
# --------------------------------------------------------------------------- #

test_singleton_survives_a_hard_kill() {
  printf 'a stale pidfile does not disarm the watchdog\n'
  write_cgroup "${WORK}/cg" 4294967296 0.00
  local pdir="${WORK}/proc7"
  build_tree "$pdir"
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir"

  printf '99999\n' >"${WORK}/state/watchdog.pid"
  if acquire_singleton; then
    ok "a pidfile naming a dead process is taken over"
  else
    bad "a dead process's pidfile locks the watchdog out"
  fi

  printf '44\n' >"${WORK}/state/watchdog.pid"
  if acquire_singleton; then
    ok "a pidfile naming an unrelated live process is taken over"
  else
    bad "an unrelated process holding a recycled pid locks the watchdog out"
  fi

  : >"${WORK}/state/watchdog.pid"
  if acquire_singleton; then
    ok "an empty pidfile is taken over"
  else
    bad "an empty pidfile locks the watchdog out"
  fi

  # And the mutation that must flip it: a live process genuinely running this
  # script. Without this, the three assertions above would pass equally against a
  # watchdog with no singleton guard at all.
  local d="${pdir}/4242"
  mkdir -p "$d"
  printf '4242 (bash) S 1 1 1 0 -1 4194560 0 0 0 0 0 0 0 0 20 0 1 0 100\n' >"${d}/stat"
  printf '/bin/bash\0%s\0' "${SELF_DIR}/script-memory-watchdog.sh" >"${d}/cmdline"
  printf '4242\n' >"${WORK}/state/watchdog.pid"
  if acquire_singleton; then
    bad "a genuinely running watchdog did not stop a second one"
  else
    ok "a live process running this same script does hold the lock"
  fi

  printf '4242\n' >"${WORK}/state/watchdog.pid"
  release_singleton
  if [[ -s "${WORK}/state/watchdog.pid" ]]; then
    ok "releasing leaves another instance's pidfile alone"
  else
    bad "releasing removed a pidfile this instance did not own"
  fi
}

# --------------------------------------------------------------------------- #
# 8. pid recycling
#
# Every piece of state carried between sweeps is keyed on pid:starttime. Without
# the starttime a recycled pid inherits the dwell clock of whatever held that
# number before it, and can be killed for someone else's drift.
# --------------------------------------------------------------------------- #

test_pid_recycling() {
  printf 'pid recycling\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  local pdir="${WORK}/proc8"
  build_tree "$pdir"
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir" enforce

  local t=1000
  sweep_at $t
  assert_eq "$t" "${OVER_SINCE[61:100]}" "the dwell clock is keyed on pid and starttime"

  # Same pid, different process. The starttime changes, so the key changes.
  printf '61 (python3) S 60 1 1 0 -1 4194560 0 0 0 0 0 0 0 0 20 0 1 0 55500\n' \
    >"${pdir}/61/stat"
  t=$((t + DWELL_SECONDS))
  sweep_at $t
  assert_eq "" "$SIGNALS" "a recycled pid does not inherit the previous dwell"
  assert_eq "$t" "${OVER_SINCE[61:55500]}" "it starts its own clock"
  if [[ -n ${OVER_SINCE[61:100]:-} ]]; then
    bad "the dead process's dwell entry was left behind to grow forever"
  else
    ok "and the dead process's entry is pruned"
  fi
}

# --------------------------------------------------------------------------- #

main() {
  test_measurement
  test_selection
  test_claude_helpers
  test_operator_runtime_is_never_a_helper
  test_comm_is_not_a_criterion
  test_two_servers
  test_guards_are_precise
  test_tree_helpers
  test_tree_helper_arming_is_end_to_end
  test_envelope
  test_oversize_is_reported_not_killed
  test_dwell
  test_kill_rate_is_reported_and_nothing_disarms
  test_an_escalation_in_flight_is_finished
  test_observe_mode
  test_sweep_log
  test_stdout_emission
  test_singleton_survives_a_hard_kill
  test_pid_recycling
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  ((FAIL == 0))
}

main "$@"
