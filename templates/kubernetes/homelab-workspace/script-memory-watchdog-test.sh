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
# things in the watchdog that can actually hurt the operator - the
# unreclaimable-memory arithmetic and the process-selection rules - can be
# changed with evidence rather than hope.
#
# The important cases here are the negative ones. A test that asserts "the
# watchdog did not signal the memory hog" proves nothing unless the same fixture,
# with the ptyHost marker removed, produces the opposite result - so each
# exclusion is paired with the mutation that must flip it.
#
# The fixtures are transcribed from a live workspace, not written from a reading
# of how VS Code ought to behave. That distinction is not stylistic: the first
# version of this file assumed `comm` would be `node` for the server processes,
# it is `MainThread` on every real tree, and the whole suite was green while the
# detection it was guarding picked the wrong process.
set -uo pipefail

SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

PASS=0
FAIL=0

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

# Seeds the debounce state the watchdog carries between samples. These are
# globals of the sourced script, which shellcheck cannot see assigned here.
# shellcheck disable=SC2034
reset_tier_state() {
  C_L1=0
  C_L2=0
  C_L3=0
  LAST_ACTION_AT=${1:-0}
  RUNG_FIRED=()
  IN_EXCURSION=0
  EXCURSIONS=0
}

# --------------------------------------------------------------------------- #
# fixtures
# --------------------------------------------------------------------------- #

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
add_proc() {
  local dir=$1 pid=$2 ppid=$3 comm=$4 rss=$5
  shift 5
  local d="${dir}/${pid}"
  mkdir -p "$d"
  printf '%s (%s) S %s 0 0 0 -1 4194560 0 0 0 0 0 0 0 0 20 0 1 0 0\n' \
    "$pid" "$comm" "$ppid" >"${d}/stat"
  # statm: size resident shared text lib data dt. `data` is what RLIMIT_DATA
  # accounts, and on a real V8 process it is several times resident - see
  # set_proc_data, and read_rss() in the watchdog for the live measurements.
  # Defaulting it to resident keeps the fixtures honest about which field is
  # being read without asserting a relationship that does not hold.
  printf '0 %s 0 0 0 %s 0\n' "$((rss / 4096))" "$((rss / 4096))" >"${d}/statm"
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

# set_proc_data <procdir> <pid> <rss-bytes> <data-bytes>
set_proc_data() {
  local dir=$1 pid=$2 rss=$3 data=$4
  printf '0 %s 0 0 0 %s 0\n' "$((rss / 4096))" "$((data / 4096))" >"${dir}/${pid}/statm"
}

# A representative tree, transcribed from `ps -eo pid,ppid,comm,args` on a live
# workspace with a VS Code server attached. Argument shapes, argv[0] paths and -
# the part that matters most - the `comm` values are what that capture showed,
# not what a reading of the VS Code source would suggest.
#
# The `comm` values are load-bearing. Every node process in a real server tree
# reports MainThread, because V8 renames its main thread with prctl(PR_SET_NAME).
# An earlier version of this fixture wrote `node`, and that one wrong string hid
# a root-selection bug that only a real tree could expose.
#
# The hog is three levels below ptyHost, exactly like a tmux session or an agent
# started from a VS Code integrated terminal.
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
#   |                   |   +- 45  yaml languageserver.js
#   |                   |   +- 46  terraform-ls      (native, not node)
#   |                   |   +- 47  claude-code cli.js  (mise's node, not VS Code's)
#   |                   |   +- 48  an extension task   (mise's node, not VS Code's)
#   |                   +- 42  fileWatcher
#   |                   +- 43  ptyHost               <- excised, whole subtree
#   |                       +- 50  bash
#   |                           +- 51  tmux: server
#   |                               +- 52  claude
#   |                               +- 53  node (the hog)
#   +- 60  claude (outside the tree)
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

  add_proc "$dir" 40 34 "$nc" 300000000 "${sdir}/node" "$srv" \
    --connection-token=remotessh --start-server --enable-remote-auto-shutdown
  add_proc "$dir" 41 40 "$nc" 1500000000 "${sdir}/node" \
    --dns-result-order=ipv4first "${sdir}/out/bootstrap-fork" \
    --type=extensionHost --transformURIs --useHostProxy=false
  add_proc "$dir" 44 41 "$nc" 2000000000 "${sdir}/node" \
    "${ext}/ms-vscode.typescript/lib/tsserver.js" --useInferredProjectPerProjectRoot
  add_proc "$dir" 45 41 "$nc" 400000000 "${sdir}/node" \
    "${ext}/redhat.vscode-yaml-1.24.0/dist/languageserver.js" --node-ipc --clientProcessId=41
  add_proc "$dir" 46 41 terraform-ls 800000000 \
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
  add_proc "$dir" 42 40 "$nc" 250000000 "${sdir}/node" \
    "${sdir}/out/bootstrap-fork" --type=fileWatcher
  add_proc "$dir" 43 40 "$nc" 100000000 "${sdir}/node" \
    "${sdir}/out/bootstrap-fork" "$ptyhost_arg" --logsPath "${vsc}/data/logs/20260816T162519"
  add_proc "$dir" 50 43 bash 20000000 /bin/bash -l
  add_proc "$dir" 51 50 "tmux: server" 5000000 tmux new -s work
  add_proc "$dir" 52 51 claude 900000000 claude
  add_proc "$dir" 53 51 "$nc" 3000000000 node -e "const a=[];setInterval(()=>a.push(Buffer.alloc(1)),1)"
  add_proc "$dir" 60 1 claude 700000000 claude
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

load_watchdog() {
  WATCHDOG_SOURCE_ONLY=1 \
    WATCHDOG_CGROUP_DIR="$1" \
    WATCHDOG_PROC_DIR="$2" \
    WATCHDOG_STATE_DIR="${WORK}/state" \
    WATCHDOG_MODE=observe \
    . "${SELF_DIR}/script-memory-watchdog.sh"
  mkdir -p "${WORK}/state"
  # The thresholds and the RLIMIT_DATA ceilings are derived from memory.max on
  # the first successful scan rather than being constants, so a harness that
  # skipped this would be testing a watchdog with an empty ladder - which is not
  # a state the real thing is ever in, and which silently passes any assertion
  # about *not* acting.
  read_cgroup_memory && derive_limits "$M_MAX"
}

scan_fixture() {
  read_cgroup_memory
  read_cgroup_pressure
  read_process_table
  build_server_tree
  compute_protected
}

candidate_pids() {
  select_candidates "$1"
  local row pid acc=""
  for row in "${CANDIDATES[@]}"; do
    pid=${row#* }
    acc+="${pid%% *} "
  done
  printf '%s' "${acc% }"
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

  # Found on a live pod: the projection term is routinely negative, and bash
  # division truncates toward zero, so a naive formatter prints "-27.-79 GiB".
  assert_eq "6.14 GiB" "$(fmt_gib 6594088184)" "headroom formats as GiB"
  assert_eq "-1.50 GiB" "$(fmt_gib -1610612736)" "a negative projection formats with one sign"
  assert_eq "0.00 GiB" "$(fmt_gib 0)" "zero formats without a sign"

  read_cgroup_pressure
  assert_eq 0 "$M_PSI_CENTI" "psi full avg10 parses as 0"

  write_cgroup "${WORK}/cg" 8589934592 12.34
  read_cgroup_pressure
  assert_eq 1234 "$M_PSI_CENTI" "psi full avg10 parses to centi-units"

  write_cgroup "${WORK}/cg" max 0.00
  read_cgroup_memory
  assert_eq 2 "$?" "an unlimited cgroup is reported, not treated as huge headroom"
}

# --------------------------------------------------------------------------- #
# 2. process selection - the part that can hurt the operator
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
  assert_eq 13 "${#SERVER_TREE[@]}" "server tree spans every descendant, ptyHost included"

  local d
  for d in 3 4; do
    if [[ -n ${SERVER_TREE[$d]:-} ]]; then
      bad "decoy pid ${d} joined the tree"
    else
      ok "decoy pid ${d} stays out of the tree"
    fi
  done
  # The CLI and the shells above the server are ancestors, not descendants: the
  # root is server-main.js, so scoping starts there and not at `code command-shell`.
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
  role_of 45
  assert_eq languageServer "$ROLE" "a node language server under extensions/ keeps its role"
  role_of 46
  assert_eq extensionHelper "$ROLE" "terraform-ls reads as a native extension helper"
  # It is sheddable but never pre-emptively capped - see role_of() for why a
  # ceiling that is graceful for V8 is an abrupt abort for a Go runtime.
  if [[ -n ${CEILING[extensionHelper]:-} ]]; then
    bad "a native extension helper was given an RLIMIT_DATA ceiling"
  else
    ok "a native extension helper is given no RLIMIT_DATA ceiling"
  fi

  # ptyHost is matched loosely on purpose, unlike every other role. Reading
  # something as ptyHost that is not only ever protects more than necessary;
  # reading something as extensionHost that is not gets it signalled at L3.
  # shellcheck disable=SC2034  # P_CMD is a global of the sourced watchdog
  P_CMD[9001]="/usr/bin/node fork --type=ptyHostSomethingNew"
  role_of 9001
  assert_eq ptyHost "$ROLE" "an unrecognised ptyHost variant still reads as ptyHost"
  unset 'P_CMD[9001]'

  local p
  for p in 43 50 51 52 53; do
    if [[ -n ${PROTECTED[$p]:-} ]]; then
      ok "pid ${p} in the ptyHost subtree is protected"
    else
      bad "pid ${p} in the ptyHost subtree is NOT protected"
    fi
  done
  assert_protected 1 yes "pid 1 is protected"
  assert_protected 60 yes "a claude outside the tree is protected"

  assert_eq "44 46 45 42" "$(candidate_pids L2)" \
    "L2 offers only kill-safe helpers, heaviest first"
  assert_eq "41" "$(candidate_pids L3)" "L3 offers only the extension host"
  # Ordered by RSS, so serverMain (300M) precedes fileWatcher (250M).
  assert_eq "44 41 46 45 40 42" "$(candidate_pids L4)" \
    "L4 offers the whole tree except the ptyHost subtree"

  # The negative assertion, stated explicitly for every tier.
  local tier all
  for tier in L2 L3 L4; do
    all=" $(candidate_pids "$tier") "
    if [[ $all == *" 53 "* ]]; then
      bad "${tier} would signal the hog inside a VS Code terminal"
    else
      ok "${tier} never signals the hog inside a VS Code terminal"
    fi
  done
}

# --------------------------------------------------------------------------- #
# 3. the mutation that must flip the result
#
# Without this, "the hog was not selected" is unfalsifiable - it would pass just
# as happily against a watchdog that selects nothing at all.
# --------------------------------------------------------------------------- #

test_selection_is_falsifiable() {
  printf 'selection is falsifiable\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  local pdir="${WORK}/proc3"
  # Same tree, but pid 43 is no longer marked as the ptyHost fork.
  build_tree "$pdir" --type=notThePtyHost
  load_watchdog "${WORK}/cg" "$pdir"
  scan_fixture
  # The hog runs the operator's node, so the path rule protects it too. It is
  # dropped here so that this test measures the ptyHost subtree rule and only
  # that; the path rule has its own mutation in the previous test.
  # shellcheck disable=SC2317,SC2329  # invoked indirectly, via the sourced watchdog
  is_vscode_binary() { return 0; }
  compute_protected

  assert_protected 53 no "without the ptyHost marker the hog loses subtree protection"
  if [[ " $(candidate_pids L4) " == *" 53 "* ]]; then
    ok "and L4 would then select it - the exclusion is what keeps it safe"
  else
    bad "L4 still ignores the hog, so the ptyHost assertion proves nothing"
  fi

  # The name-based net still holds independently of tree position.
  assert_protected 52 yes "claude is still protected by name with the subtree rule disabled"
  assert_protected 51 yes "tmux is still protected by name with the subtree rule disabled"
}

# --------------------------------------------------------------------------- #
# 2b. the operator's runtime is never a VS Code helper
#
# The failure this guards against is the one the whole design exists to prevent,
# arriving through the detection layer instead of the action layer: an agent
# session spawned by an extension is a child of the extension host, is not under
# ptyHost, and would be stamped with an RLIMIT_DATA ceiling and shed at L2/L3 by
# anything that decides "is this a VS Code helper" by asking "is this node".
# --------------------------------------------------------------------------- #

test_operator_runtime_is_never_a_helper() {
  printf 'the operator runtime is never a VS Code helper\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  local pdir="${WORK}/proc2b"
  build_tree "$pdir"
  load_watchdog "${WORK}/cg" "$pdir"
  scan_fixture

  role_of 47
  assert_eq other "$ROLE" "an agent session under the extension host is not a helper role"
  role_of 48
  assert_eq other "$ROLE" "nor is an extension task run on the operator's node"
  # Same directory in the arguments, opposite classification - argv[0] is the
  # only thing separating pid 46 from pid 47.
  role_of 46
  assert_eq extensionHelper "$ROLE" "while the extension's own binary still is one"

  assert_protected 47 yes "the agent session is protected"
  assert_protected 48 yes "and so is the extension task"
  local tier all p
  for tier in L2 L3 L4; do
    all=" $(candidate_pids "$tier") "
    for p in 47 48; do
      if [[ $all == *" $p "* ]]; then
        bad "${tier} would signal pid ${p}, which runs the operator's node"
      else
        ok "${tier} never signals pid ${p}, which runs the operator's node"
      fi
    done
  done

  # Two guards stand between these processes and a signal, and each is mutated
  # separately so that neither can be credited with the other's work.
  #
  # Mutation 1 - drop the path rule, keep the name guard. The agent session
  # survives on its name; the extension task has nothing left and is reachable.
  # That asymmetry is the measurement of how much the path rule is doing, and why
  # the name guard must not be relied on by itself.
  # shellcheck disable=SC2317,SC2329  # invoked indirectly, via the sourced watchdog
  is_vscode_binary() { return 0; }
  compute_protected
  assert_protected 47 yes "without the path rule the agent session still has its name"
  assert_protected 48 no "but the extension task has nothing left"
  if [[ " $(candidate_pids L4) " == *" 48 "* ]]; then
    ok "and L4 would then select it - the path rule is what prevents that"
  else
    bad "L4 still ignores it, so the path assertion proves nothing"
  fi

  # Mutation 2 - additionally key roles on the joined command line instead of on
  # argv[0], which is what this file did before a live tree was consulted. The
  # extension task's arguments name the extension directory, so it is classified
  # as a sheddable helper and L2 - the corroborated, everyday tier - picks it up.
  # shellcheck disable=SC2317,SC2329  # invoked indirectly, via the sourced watchdog
  role_of() {
    case " ${P_CMD[$1]:-} " in
    *"/.vscode-server/extensions/"*) ROLE=extensionHelper ;;
    *) ROLE=other ;;
    esac
  }
  if [[ " $(candidate_pids L2) " == *" 48 "* ]]; then
    ok "keying roles on arguments instead of argv[0] makes L2 shed the extension task"
  else
    bad "the role assertion proves nothing - argv[0] keying is not what excludes it"
  fi
}

# --------------------------------------------------------------------------- #
# 3a. comm is not a selection criterion, and must never become one again
#
# Pinning the fixture to MainThread would only trade one hardcoded assumption for
# another. What is actually required is that comm does not participate in the
# decision at all, so the same tree is built under three different comm values -
# the real one, the one the fixtures used to assume, and a value nothing has ever
# reported - and the root must come out the same every time.
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
    assert_eq 13 "${#SERVER_TREE[@]}" "comm=${comm}: the tree is still complete"
    assert_protected 53 yes "comm=${comm}: the hog under ptyHost is still protected"
  done
}

# --------------------------------------------------------------------------- #
# 3b. more than one server, and none of them named `node`
#
# --reconnection-grace-time keeps a disconnected server alive for eight hours, so
# two live server trees is an ordinary state, not an exotic one. Electing a
# single root would leave the other tree's ptyHost subtree un-excised, because
# excision only runs inside the tree that was discovered.
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
  assert_eq 17 "${#SERVER_TREE[@]}" "the managed tree is the union of both subtrees"
  assert_protected 71 yes "the second server's ptyHost is protected"
  assert_protected 72 yes "and so is the shell beneath it"
  if [[ " $(candidate_pids L4) " == *" 73 "* ]]; then
    ok "the second server's fileWatcher is reachable at L4"
  else
    bad "the second server's tree is not managed at all"
  fi
}

# --------------------------------------------------------------------------- #
# 3c. the guards are precise, and each of them is reachable
#
# Both historical over-matches were substring matches over the joined command
# line, both were found by accident, and both were invisible to a green suite -
# the second one protected every process in a fixture harness because the
# harness's own directory path contained the string the guard matched on, so two
# full runs asserted nothing at all. The decoys below are those exact paths.
#
# Each rule is also asserted to be *reachable*: a guard that no fixture can
# trigger is not being tested, it is only being carried.
# --------------------------------------------------------------------------- #

# Three processes that all run VS Code's own node, inside the tree, outside the
# ptyHost subtree - so nothing structural separates them. Only the guards do.
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
  # The case the payload rule genuinely exists for, and the reason it cannot
  # simply be deleted: an agent session that an extension started with the
  # editor's own interpreter. argv[0] is VS Code's node, so is_vscode_binary
  # says "editor"; it is not under ptyHost, so the subtree rule never sees it.
  add_proc "$dir" 82 41 MainThread 900000000 "${sdir}/node" \
    "${ext}/anthropic.claude-code-2.1.232/resources/claude-code/cli.js" --ide
  # Outside the tree, and the reason argv[0] is consulted at all: for a script
  # with a shebang the kernel sets comm from the *interpreter*, so a launcher on
  # PATH called `claude` reports comm=bash. The name the operator knows it by
  # survives only in argv[0].
  add_proc "$dir" 83 1 bash 500000000 /home/coder/.local/bin/claude --resume
}

test_guards_are_precise() {
  printf 'the guards are precise\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  local pdir="${WORK}/proc3c"
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

  # Falsification: if the two decoys were unreachable for some other reason, the
  # assertions above would pass against a watchdog that selects nothing.
  local l4
  l4=" $(candidate_pids L4) "
  for p in 80 81; do
    if [[ $l4 == *" $p "* ]]; then
      ok "decoy pid ${p} is genuinely reachable, so its non-protection means something"
    else
      bad "decoy pid ${p} is unreachable anyway - the assertion proves nothing"
    fi
  done
  if [[ $l4 == *" 82 "* ]]; then
    bad "the claude-code payload is reachable at L4"
  else
    ok "the claude-code payload is not reachable at any tier"
  fi

  # Every guard the code can apply is applied to something here. A rule nothing
  # exercises is a rule nobody has established the correctness of.
  local want got reasons=" "
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

  # And the census says something usable about all of it: a managed tree with
  # nothing eligible is the shape of the harness bug, whatever the cause.
  got="$(census_line)"
  if [[ $got == *"eligible=0" ]]; then
    bad "census reports no eligible processes on a healthy tree: ${got}"
  else
    ok "census reports the tree, the guards and what is left: ${got}"
  fi
}

# --------------------------------------------------------------------------- #
# 3d. an acting tier never acts silently
#
# The bug that hid the second over-match was not the over-match: it was that
# enforce mode logged tier=L3 with no signal line and no refusal line, a state
# that reads as "nothing needed doing". Whatever the guards do, every path out of
# an acting tier must now say what happened.
# --------------------------------------------------------------------------- #

test_acting_tier_never_acts_silently() {
  printf 'an acting tier never acts silently\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  local pdir="${WORK}/proc3d"
  build_tree "$pdir"
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir"
  scan_fixture

  # Reproduce the failure exactly: a guard that swallows the entire tree.
  # shellcheck disable=SC2317,SC2329  # invoked indirectly, via the sourced watchdog
  is_operator_payload() { return 0; }
  compute_protected
  : >"${WORK}/state/actions.log"
  shed_load L3 1000
  if [[ "$(cat "${WORK}/state/actions.log")" == *"no-candidates tier=L3"* ]]; then
    ok "a tier with nothing left to signal says so, with the census"
  else
    bad "an acting tier signalled nothing and logged nothing - the original bug"
  fi

  # And the other silent path: a candidate too small to be worth the disruption.
  # shellcheck disable=SC2317,SC2329  # invoked indirectly, via the sourced watchdog
  is_operator_payload() { return 1; }
  compute_protected
  : >"${WORK}/state/actions.log"
  WATCHDOG_MIN_SHED_RSS_SAVED=$MIN_SHED_RSS
  MIN_SHED_RSS=999999999999
  shed_load L2 1000
  MIN_SHED_RSS=$WATCHDOG_MIN_SHED_RSS_SAVED
  if [[ "$(cat "${WORK}/state/actions.log")" == *"no-worthwhile-candidate tier=L2"* ]]; then
    ok "declining to shed something too small is logged, not skipped quietly"
  else
    bad "a tier declined to act and said nothing"
  fi
}

# --------------------------------------------------------------------------- #
# 4. the tier ladder
# --------------------------------------------------------------------------- #

# step_tier <H> <psi-centi> <refault/s> <projected-H> <now>
#
# Called in the current shell on purpose. The debounce counters are state carried
# between samples, and running decide_tier in a command substitution would throw
# them away - which is exactly the bug this ladder had before it was tested.
step_tier() {
  decide_tier "$1" "$2" "$3" "$4" "$5"
}

# assert_tier <want> <H> <psi> <refault> <projected-H> <now> <description>
assert_tier() {
  step_tier "$2" "$3" "$4" "$5" "$6"
  assert_eq "$1" "$TIER" "$7"
}

test_tiers() {
  printf 'tier ladder\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  load_watchdog "${WORK}/cg" "${WORK}/proc2"

  local big=6594088184 mid=2500000000 low=1800000000 crit=1000000000 dead=700000000

  reset_tier_state
  assert_tier L0 "$big" 0 0 "$big" 1000 "idle at 6 GiB headroom is L0"
  # This is the case a naive memory.current > 85% trigger gets wrong: the real
  # pod sits here permanently.
  assert_tier L0 "$big" 0 0 "$big" 1000 "and stays L0 while nothing changes"

  reset_tier_state
  assert_tier L0 "$mid" 0 0 "$mid" 1000 "first sample below L1 does not act"
  assert_tier L0 "$mid" 0 0 "$mid" 1000 "second sample below L1 does not act"
  assert_tier L1 "$mid" 0 0 "$mid" 1000 "third consecutive sample is L1"
  assert_tier L0 "$big" 0 0 "$big" 1000 "recovery resets the debounce"

  reset_tier_state
  step_tier "$low" 0 0 "$low" 1000
  step_tier "$low" 0 0 "$low" 1000
  assert_tier L1 "$low" 0 0 "$low" 1000 \
    "below L2 without PSI or refault corroboration stays at L1"

  reset_tier_state
  step_tier "$low" 1500 0 "$low" 1000
  step_tier "$low" 1500 0 "$low" 1000
  assert_tier L2 "$low" 1500 0 "$low" 1000 "below L2 with PSI >= 10 is L2"

  reset_tier_state
  step_tier "$low" 0 50000 "$low" 1000
  step_tier "$low" 0 50000 "$low" 1000
  assert_tier L2 "$low" 0 50000 "$low" 1000 "or with a high refault rate"

  reset_tier_state
  step_tier "$crit" 0 0 "$crit" 1000
  assert_tier L3 "$crit" 0 0 "$crit" 1000 "L3 needs two samples and no corroboration"

  reset_tier_state
  assert_tier L4 "$dead" 0 0 "$dead" 1000 "L4 acts on the first sample"

  # Projection: headroom is fine-ish but falling fast enough to hit L4 inside the
  # horizon. Only armed once the ladder has already left L0.
  reset_tier_state
  step_tier "$mid" 0 0 "$mid" 1000
  step_tier "$mid" 0 0 "$mid" 1000
  assert_tier L3 "$mid" 0 0 100000000 1000 "a 60s projection into L4 escalates to L3"

  reset_tier_state
  assert_tier L0 "$big" 0 0 100000000 1000 \
    "but a spike from idle does not - the projection is disarmed at L0"

  # Cooldown holds the acting tiers back; L4 is exempt.
  reset_tier_state 1000
  step_tier "$crit" 0 0 "$crit" 1010
  assert_tier L1 "$crit" 0 0 "$crit" 1010 "L3 is suppressed inside the cooldown"
  reset_tier_state 1000
  assert_tier L4 "$dead" 0 0 "$dead" 1010 "L4 ignores the cooldown"
}

# --------------------------------------------------------------------------- #
# 4b. the ladder is derived from the pod, and stays sane at every pod size
#
# The thresholds used to be absolute bytes chosen for an 8 GiB pod, which made
# the 4 GiB workspace sit permanently on the first rung - the watchdog detected
# that itself and declined to be useful. What is asserted here is not that the
# arithmetic is what it is, but that the properties that make the ladder usable
# hold across every size the workspace is offered at, and past both ends of it.
# --------------------------------------------------------------------------- #

# ladder_at <memory.max> -> "L4 L3 L2 L1"
ladder_at() {
  T_L1="" T_L2="" T_L3="" T_L4=""
  CEILING=()
  derive_limits "$1"
  printf '%s %s %s %s' "$T_L4" "$T_L3" "$T_L2" "$T_L1"
}

test_derivation() {
  printf 'the ladder is derived from the pod\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  load_watchdog "${WORK}/cg" "${WORK}/proc2"

  # 8 GiB is the only size the original absolute numbers were ever reasoned
  # about, so the derivation has to land near them or it has thrown away the one
  # piece of thinking that existed. 0.80/1.20/2.00/3.20 against 0.75/1.25/2.00/3.00.
  assert_eq "858993459 1288490188 2147483647 3435973836" "$(ladder_at 8589934592)" \
    "8 GiB reproduces the hand-tuned ladder it replaces"
  # 4 GiB: the case that forced this change. Resting headroom on the live 4 GiB
  # workspace was 3.36 GiB, which has to be comfortably clear of L1.
  assert_eq "429496729 644245093 1073741822 1717986916" "$(ladder_at 4294967296)" \
    "4 GiB scales the whole ladder down rather than sitting on it"
  # 16 GiB: the objection that made the thresholds absolute in the first place -
  # a plain percentage would reserve 1.6 GiB and shed with real headroom left.
  assert_eq "1073741824 1610612736 2684354560 4294967296" "$(ladder_at 17179869184)" \
    "16 GiB is capped rather than scaled into absurdity"
  # 1 GiB: far below anything offered. The floor holds, and the ladder stays
  # ordered - the failure to design out is a rung that overtakes another.
  local small
  small="$(ladder_at 1073741824)"
  assert_eq "402653184 603979776 1006632960 1610612736" "$small" \
    "a pod below the floor gets the floor, not a ladder of noise"

  local max l4 l3 l2 l1
  for max in 1073741824 2147483648 4294967296 8589934592 17179869184 34359738368; do
    # Not via a command substitution: TOO_SMALL is state the derivation sets, and
    # a subshell would discard exactly the answer being asserted on.
    T_L1="" T_L2="" T_L3="" T_L4=""
    CEILING=()
    derive_limits "$max"
    l4=$T_L4 l3=$T_L3 l2=$T_L2 l1=$T_L1
    if ((l4 < l3 && l3 < l2 && l2 < l1)); then
      ok "memory.max=${max}: the rungs stay strictly ordered"
    else
      bad "memory.max=${max}: rungs out of order (${l4} ${l3} ${l2} ${l1})"
    fi
    # Either the pod has room above its own first rung, or the watchdog has
    # declared the pod too small to act on. What must never happen is a pod that
    # boots inside the shedding tiers while still believing it may shed - that is
    # the "kills the editor every fifteen minutes" failure, reached by arithmetic
    # rather than by bad luck.
    if ((l1 * 2 <= max)); then
      ok "memory.max=${max}: the pod has room above L1"
    elif ((TOO_SMALL == 1)); then
      ok "memory.max=${max}: too small for the ladder, and says so"
    else
      bad "memory.max=${max}: L1 (${l1}) crowds the limit and enforce is not refused"
    fi
  done

  T_L1="" T_L2="" T_L3="" T_L4=""
  CEILING=()
  derive_limits 1073741824
  assert_eq 1 "$TOO_SMALL" "a 1 GiB pod is marked too small for the ladder"
  T_L1="" T_L2="" T_L3="" T_L4=""
  CEILING=()
  derive_limits 4294967296
  assert_eq 0 "$TOO_SMALL" "a 4 GiB pod is not"

  # Ceilings scale for the same reason and with the same failure modes: a 3 GiB
  # extension-host ceiling on a 4 GiB pod is not cautious, it is unreachable.
  T_L1="" T_L2="" T_L3="" T_L4=""
  CEILING=()
  derive_limits 8589934592
  assert_eq 1610612736 "${CEILING[serverMain]}" "8 GiB keeps the reasoned serverMain ceiling"
  assert_eq 3221225472 "${CEILING[extensionHost]}" "and the extension-host one"
  assert_eq 3758096384 "${CEILING[tsserver]}" "and tsserver's"
  T_L1="" T_L2="" T_L3="" T_L4=""
  CEILING=()
  derive_limits 4294967296
  assert_eq 1610612736 "${CEILING[extensionHost]}" "4 GiB halves the extension-host ceiling"
  assert_eq 536870912 "${CEILING[fileWatcher]}" "and floors the small ones rather than shrinking them to nothing"
  local role
  for role in serverMain extensionHost tsserver languageServer fileWatcher; do
    if ((${CEILING[$role]} < 4294967296)); then
      ok "4 GiB pod: the ${role} ceiling is inside the pod"
    else
      bad "4 GiB pod: the ${role} ceiling (${CEILING[$role]}) is the whole pod - inert"
    fi
  done

  # An explicit environment value must win, or the live demonstration cannot
  # force a ceiling to bite without editing the script under test.
  T_L1="" T_L2="" T_L3="" T_L4=""
  CEILING=()
  WATCHDOG_CEILING_extensionHost=268435456 derive_limits 8589934592
  assert_eq 268435456 "${CEILING[extensionHost]}" "an explicit ceiling overrides the derivation"
  T_L1="" T_L2="" T_L3=""
  T_L4=123456789 # as WATCHDOG_T_L4 would have left it at startup
  CEILING=()
  derive_limits 8589934592
  assert_eq 123456789 "$T_L4" "and an explicit rung overrides its share of the ladder"
  assert_eq 3435973836 "$T_L1" "while the rest of the ladder is still derived"
}

# --------------------------------------------------------------------------- #
# 4c. how often it acts
#
# Shedding the editor is the right trade against an oom.group kill. Shedding it
# every fifteen minutes is not, because the operator switches the watchdog off
# and then it protects nothing. Correctness and frequency are both requirements.
# --------------------------------------------------------------------------- #

# LAST_ACTION_AT and RUNG_FIRED are globals of the sourced watchdog, standing in
# here for the bookkeeping shed_load would have done after a real signal.
# shellcheck disable=SC2034
test_shedding_is_rate_limited() {
  printf 'shedding is rate limited\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  load_watchdog "${WORK}/cg" "${WORK}/proc2"

  local mid=2500000000 low=1800000000 crit=1000000000 big=6594088184
  local t=1000

  reset_tier_state
  # Reach L2 and let it fire.
  step_tier "$low" 1500 0 "$low" $t
  step_tier "$low" 1500 0 "$low" $t
  assert_tier L2 "$low" 1500 0 "$low" $t "the first L2 of an excursion acts"
  RUNG_FIRED[L2]=1
  LAST_ACTION_AT=$t

  # Still bad, well past the settle window: the old cooldown would have let L2
  # fire again every 180s for as long as the pressure lasted.
  t=$((t + 600))
  assert_tier L1 "$low" 1500 0 "$low" $t \
    "and no later sample in the same excursion sheds again at L2"

  # Escalation is untouched - this is what the fixed cooldown got wrong, by
  # demoting L3 to L1 for three minutes after an L2 shed.
  step_tier "$crit" 0 0 "$crit" $t
  assert_tier L3 "$crit" 0 0 "$crit" $t "but a worse rung still fires during the same excursion"
  RUNG_FIRED[L3]=1
  LAST_ACTION_AT=$t

  # Recovery above L1 is what re-arms, not the clock.
  t=$((t + 60))
  assert_tier L0 "$big" 0 0 "$big" $t "recovery above L1 ends the excursion"
  step_tier "$low" 1500 0 "$low" $t
  step_tier "$low" 1500 0 "$low" $t
  assert_tier L2 "$low" 1500 0 "$low" $((t + 100)) "and the next excursion may shed again"

  # The settle window still separates two actions inside one excursion, so the
  # ladder sees the effect of a kill before deciding it was not enough.
  reset_tier_state
  step_tier "$crit" 0 0 "$crit" 2000
  assert_tier L3 "$crit" 0 0 "$crit" 2000 "L3 acts"
  LAST_ACTION_AT=2000
  RUNG_FIRED=()
  assert_tier L1 "$crit" 0 0 "$crit" 2005 "another action 5s later is held back by the settle window"

  # L4 is exempt from all of it: by then the alternative is the whole pod.
  reset_tier_state 2000
  RUNG_FIRED[L4]=1
  assert_tier L4 700000000 0 0 700000000 2001 "L4 ignores both the settle window and the rung flag"

  # An excursion is one continuous dip, not one sample below the line.
  reset_tier_state
  step_tier "$mid" 0 0 "$mid" 3000
  assert_eq 1 "$EXCURSIONS" "a dip below L1 opens exactly one excursion"
  step_tier "$mid" 0 0 "$mid" 3010
  assert_eq 1 "$EXCURSIONS" "and staying down does not open another"
  step_tier "$big" 0 0 "$big" 3020
  step_tier "$mid" 0 0 "$mid" 3030
  assert_eq 2 "$EXCURSIONS" "recovering and falling again does"
}

# --------------------------------------------------------------------------- #
# 4d. a ceiling is never a kill order for a healthy process
#
# This is a regression test for a defect found by running the derivation against
# a live 4 GiB workspace rather than against these fixtures. RLIMIT_DATA accounts
# data_vm, not RSS, and on a V8 process the two differ by roughly an order of
# magnitude: the live file watcher held 622 MB of data while resident in 66 MB.
# The derived file-watcher ceiling for that pod was 512 MB - below what the
# process already had - so enforcing it would have killed a perfectly healthy
# file watcher on its next allocation, and again on every restart.
#
# The numbers below are that measurement, not an invention.
# --------------------------------------------------------------------------- #

# CEILING_LOGGED is a memo global of the sourced watchdog, cleared here so the
# second half of the test can observe a fresh proposal.
# shellcheck disable=SC2034
test_ceiling_is_never_below_observed_usage() {
  printf 'a ceiling is never below what the process already holds\n'
  write_cgroup "${WORK}/cg" 4294967296 0.00
  local pdir="${WORK}/proc4d"
  build_tree "$pdir"
  # Live 4 GiB workspace, at rest, VS Code 1.132: pid 918 fileWatcher and pid
  # 907 extensionHost.
  set_proc_data "$pdir" 42 67000000 637184000
  set_proc_data "$pdir" 41 509220000 1028004000
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir"
  scan_fixture

  # The case is real only if the derived ceiling really is below observed usage.
  # Without this the assertion below would pass on a pod where nothing was wrong.
  if ((CEILING[fileWatcher] < P_DATA[42])); then
    ok "the derived file-watcher ceiling really is below observed usage on a 4 GiB pod"
  else
    bad "the fixture does not reproduce the condition - the test proves nothing"
  fi

  apply_ceilings
  local log
  log="$(cat "${WORK}/state/actions.log")"
  local line want
  for pid in 42 41; do
    line=$(printf '%s\n' "$log" | grep "pid=${pid} " | head -1)
    want=${line##*rlimit_data=}
    want=${want%% *}
    if [[ -n $want ]] && ((want > ${P_DATA[$pid]:-0})); then
      ok "pid ${pid}: proposed ceiling ${want} is above its observed ${P_DATA[$pid]:-0} bytes of data"
    else
      bad "pid ${pid}: proposed ceiling '${want}' would kill it at once (data=${P_DATA[$pid]:-0})"
    fi
  done

  # And the growth allowance is the reserve, so the ceiling means "may grow by
  # this much", not "may be this big".
  line=$(printf '%s\n' "$log" | grep "pid=42 " | head -1)
  want=${line##*rlimit_data=}
  want=${want%% *}
  assert_eq "$((P_DATA[42] + 2 * C_RESERVE))" "$want" \
    "the ceiling is observed usage plus two critical reserves"

  # A ceiling that could only be set above memory.max bounds nothing. Saying so
  # is better than setting it and looking protected.
  set_proc_data "$pdir" 42 67000000 4000000000
  read_rss 42
  : >"${WORK}/state/actions.log"
  CEILING_LOGGED=()
  apply_ceilings
  if [[ "$(cat "${WORK}/state/actions.log")" == *"no-ceiling pid=42"* ]]; then
    ok "a process already too large to cap is reported, not silently capped"
  else
    bad "a process too large to cap was handled silently"
  fi
}

# --------------------------------------------------------------------------- #
# 4e. the sample interval is chosen by rate, not by tier
#
# Measured, not supposed. A runaway at the rate seen in production took the test
# workspace from idle to OOMKilled in 43 seconds while the watchdog ran in
# enforce mode, never left L0 and logged nothing: at a 10-second idle interval it
# had four samples in which to satisfy a three-sample debounce and climb three
# rungs. Tier cannot be the input to the interval, because tier is the lagging
# indicator of the very thing being raced.
# --------------------------------------------------------------------------- #

# shellcheck disable=SC2034  # TIME_TO_LIMIT and PREV_TIER are the sourced globals
test_interval_is_chosen_by_rate() {
  printf 'the sample interval is chosen by rate\n'
  write_cgroup "${WORK}/cg" 4294967296 0.00
  load_watchdog "${WORK}/cg" "${WORK}/proc2"

  TIME_TO_LIMIT=0
  PREV_TIER=L0
  assert_eq 10 "$(next_interval)" "an idle pod that is not growing polls slowly"

  PREV_TIER=L1
  assert_eq 2 "$(next_interval)" "a pod already on the ladder polls faster"

  # 3.96 GiB of headroom disappearing at 91 MB/s - the reproduced production
  # rate - is 43 seconds from the limit while still reading L0.
  TIME_TO_LIMIT=43
  PREV_TIER=L0
  assert_eq 1 "$(next_interval)" \
    "but a rate that reaches the limit inside the horizon overrides L0 entirely"

  # The case that must not become chatty: growth so slow it will never matter.
  TIME_TO_LIMIT=3600
  PREV_TIER=L0
  assert_eq 10 "$(next_interval)" "slow growth does not spin the loop up"

  # With a 1-second interval the debounce that could not complete in the live run
  # completes with time to spare: three samples is three seconds, against the 43
  # the event took.
  if ((DEBOUNCE_L1 * 1 < 43 && DEBOUNCE_L3 * 1 < 43)); then
    ok "at the fast interval the debounces fit inside the observed event"
  else
    bad "the debounces still cannot complete inside a 43-second event"
  fi
}

# --------------------------------------------------------------------------- #
# 4f. a stale pidfile does not disarm the watchdog forever
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
  local pdir="${WORK}/proc4f"
  build_tree "$pdir"
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir"

  # A pid from the previous container that no longer exists at all.
  printf '99999\n' >"${WORK}/state/watchdog.pid"
  if acquire_singleton; then
    ok "a pidfile naming a dead process is taken over"
  else
    bad "a dead process's pidfile locks the watchdog out"
  fi

  # A pid that does exist in this container but is something else entirely -
  # the recycled-pid case, which is the normal case after a restart.
  printf '44\n' >"${WORK}/state/watchdog.pid"
  if acquire_singleton; then
    ok "a pidfile naming an unrelated live process is taken over"
  else
    bad "an unrelated process holding a recycled pid locks the watchdog out"
  fi

  # An empty pidfile - what a truncated or half-written file looks like.
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
  printf '4242 (bash) S 1 0 0 0 -1 4194560 0 0 0 0 0 0 0 0 20 0 1 0 0\n' >"${d}/stat"
  printf '/bin/bash\0%s\0' "${SELF_DIR}/script-memory-watchdog.sh" >"${d}/cmdline"
  printf '4242\n' >"${WORK}/state/watchdog.pid"
  if acquire_singleton; then
    bad "a genuinely running watchdog did not stop a second one"
  else
    ok "a live process running this same script does hold the lock"
  fi

  # Releasing must not steal a pidfile owned by someone else.
  printf '4242\n' >"${WORK}/state/watchdog.pid"
  release_singleton
  if [[ -s "${WORK}/state/watchdog.pid" ]]; then
    ok "releasing leaves another instance's pidfile alone"
  else
    bad "releasing removed a pidfile this instance did not own"
  fi
}

# --------------------------------------------------------------------------- #
# 5. observe mode really is inert
# --------------------------------------------------------------------------- #

test_observe_mode_is_inert() {
  printf 'observe mode\n'
  write_cgroup "${WORK}/cg" 8589934592 0.00
  local pdir="${WORK}/proc4"
  build_tree "$pdir"
  rm -rf "${WORK}/state"
  load_watchdog "${WORK}/cg" "$pdir"
  scan_fixture

  apply_ceilings
  local limits_now
  limits_now="$(cat "${pdir}/41/limits")"
  if [[ $limits_now == *"unlimited            unlimited"* ]]; then
    ok "observe mode changed no RLIMIT_DATA"
  else
    bad "observe mode wrote a limit"
  fi
  if [[ -s "${WORK}/state/actions.log" ]] &&
    [[ "$(cat "${WORK}/state/actions.log")" == *"[observe] ceiling"* ]]; then
    ok "observe mode logged the ceilings it would have set"
  else
    bad "observe mode logged nothing"
  fi

  # ptyHost must never appear in the ceiling log, at any tier, in any mode: a
  # soft RLIMIT_DATA there is inherited by every terminal the operator opens.
  if [[ "$(cat "${WORK}/state/actions.log")" == *"pid=43"* ]]; then
    bad "a ceiling was proposed for the ptyHost fork"
  else
    ok "no ceiling is ever proposed for the ptyHost fork"
  fi
}

# --------------------------------------------------------------------------- #

main() {
  test_measurement
  test_selection
  test_operator_runtime_is_never_a_helper
  test_selection_is_falsifiable
  test_guards_are_precise
  test_acting_tier_never_acts_silently
  test_comm_is_not_a_criterion
  test_two_servers
  test_tiers
  test_derivation
  test_shedding_is_rate_limited
  test_ceiling_is_never_below_observed_usage
  test_interval_is_chosen_by_rate
  test_singleton_survives_a_hard_kill
  test_observe_mode_is_inert
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  ((FAIL == 0))
}

main "$@"
