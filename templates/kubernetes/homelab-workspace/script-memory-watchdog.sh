#!/bin/bash
#
# Memory watchdog for the workspace pod: it bounds the *standing population* of
# restartable helper processes.
#
# What it is for, and what it deliberately is not for.
#
# It is not an OOM preventer. The earlier version of this script was, and the
# premise did not survive measurement. Every memcg OOM recorded for this
# workspace was a spike - 70 to 220 MB/s, idle to dead inside a minute - and the
# victims named in the kernel log were agent sessions and node, never a VS Code
# process. A poll loop cannot win that race: a generic biggest-RSS killer only
# beats the kernel at a 0.3s interval, loses at 0.5s, and while
# memory.oom.group=1 it is killed by the very event it lost to. The graded
# shedding ladder that used to live here climbed correctly during a live spike
# and then logged `no-candidates`, because the runaway was not in the tree it
# managed. That ladder has been removed rather than tuned.
#
# What a poll loop is genuinely good at is growth measured in MB per *minute*:
# the slow drift of long-lived helpers - the extension host, language servers,
# the file watcher, and the MCP servers and other helpers an agent session
# spawns. That drift is real and was being policed by hand (repeatedly killing
# VS Code to save agent sessions); a python MCP server holding 1.66 GB was
# observed during one of the kills. Every process this script may signal is
# restarted by its own supervisor - VS Code respawns its forks and language
# servers, an agent session respawns its MCP servers - so a wrong kill costs a
# reload, not a session. That asymmetry is what licenses being aggressive.
#
# The goal is therefore runway, not rescue: keep the resting population small so
# that when a spike does arrive it starts from as much free memory as possible,
# and stop the operator having to do it by hand.
#
# Dependencies are deliberately tiny: bash 4.4+, /proc, /sys/fs/cgroup,
# /usr/bin/sleep, coreutils mv/rm/mkdir. Measurement and process enumeration use
# bash builtins, so a sweep forks nothing at all. The operator's PATH is shadowed
# by brew, so anything invoked here is called by absolute /usr/bin/... path and
# never by name.
#
# Modes (the memory_watchdog_mode template parameter; the script itself falls
# back to observe when the value is anything else):
#   observe     - measure, publish, and log the kill it *would* have made.
#                 Signals nothing.
#   enforce     - additionally kill drifted *helpers*: language servers, the
#                 file watcher, native extension helpers, and helpers spawned by
#                 an agent session (MCP servers). This is the template default,
#                 because every one of them restarts without the operator
#                 noticing.
#   enforce-all - additionally kill the extension host and the server main
#                 process. These are user-visible when they restart, and they
#                 are the two roles a wrong budget would put in a kill loop, so
#                 they are armed separately and on purpose.
#
# Test seams, exercised by script-memory-watchdog-test.sh:
#   WATCHDOG_CGROUP_DIR  WATCHDOG_PROC_DIR  WATCHDOG_STATE_DIR
#   WATCHDOG_MODE  WATCHDOG_ONESHOT  WATCHDOG_NOW  WATCHDOG_SOURCE_ONLY
#
# Deliberately NOT using `set -e`: this is a supervisor with no supervisor of its
# own. A read that fails because a /proc entry vanished mid-sweep must skip that
# entry, not take the watchdog down and leave the pod unpoliced.
set -uo pipefail

# --------------------------------------------------------------------------- #
# configuration
# --------------------------------------------------------------------------- #

CGROUP_DIR="${WATCHDOG_CGROUP_DIR:-/sys/fs/cgroup}"
PROC_DIR="${WATCHDOG_PROC_DIR:-/proc}"
STATE_DIR="${WATCHDOG_STATE_DIR:-${HOME:-/home/coder}/.local/state/vscode-memory-watchdog}"
MODE="${WATCHDOG_MODE:-observe}"
ONESHOT="${WATCHDOG_ONESHOT:-0}"

GIB=1073741824
MIB=1048576
PAGE_SIZE=4096
USER_HZ=100

# Two cadences, one loop. The cgroup sample is a handful of file reads and is
# what keeps the telemetry legible across a fast event; the sweep walks every
# process and reads smaps_rollup, and drives every decision. Drift is measured in
# MB per minute, so a decision cadence of a minute is not a compromise - it is
# the correct resolution for the thing being policed.
SAMPLE_INTERVAL="${WATCHDOG_SAMPLE_INTERVAL:-10}"
SWEEP_EVERY="${WATCHDOG_SWEEP_EVERY:-6}" # samples per sweep => 60s

# A process must be over its budget continuously for this long before anything
# happens to it. This is the single most important number in the file, and it is
# what separates drift policing from the spike chasing that did not work: a
# language server that balloons while indexing and then hands the memory back is
# load, not drift, and must survive. Expressed in seconds so that changing the
# sweep cadence cannot silently change the policy.
DWELL_SECONDS="${WATCHDOG_DWELL_SECONDS:-600}"

# Never signal something that has not been alive long enough to have finished
# starting up. A process that is over budget within seconds of its own start is
# a spike, which is the kernel's problem, not this one's.
MIN_AGE="${WATCHDOG_MIN_AGE:-300}"

# SIGTERM, then SIGKILL on a later sweep if it is still there and still over.
# There is no in-loop sleep: the grace period is measured across sweeps, so a
# process that is shutting down politely is never hurried.
KILL_GRACE="${WATCHDOG_KILL_GRACE:-30}"

# The circuit breaker. This is the counterweight to being aggressive, and it
# exists because the failure mode of drift policing is not a wrong kill - it is a
# kill *loop*: kill the extension host, VS Code restarts it, it reloads every
# extension, it exceeds again, kill. That loop arrives looking exactly like the
# watchdog working, and it is the thing that gets a watchdog switched off.
#
# So a role that has to be killed LOOP_KILLS times inside LOOP_WINDOW is not a
# drifting role, it is a role whose budget is wrong for this workload. The
# watchdog disarms itself for that role, says so, and leaves the number to a
# human. It never widens its own budget: a mechanism that quietly raises the
# limit it is enforcing is a mechanism that stops enforcing anything.
LOOP_WINDOW="${WATCHDOG_LOOP_WINDOW:-3600}"
LOOP_KILLS="${WATCHDOG_LOOP_KILLS:-3}"
# And the same idea across all roles at once, in case a budget is wrong in a way
# that spreads: too many kills in one window disarms everything.
GLOBAL_LOOP_KILLS="${WATCHDOG_GLOBAL_LOOP_KILLS:-8}"

# Budgets, in bytes of PSS, by role.
#
# Why PSS and not VmData. RLIMIT_DATA accounts VmData, which is why the previous
# design measured it; that mechanism is gone, and for deciding "is this process
# holding too much memory" VmData is the wrong quantity by roughly an order of
# magnitude on a V8 process (measured: file watcher 66 MB resident against 622 MB
# of data). PSS is what the pod actually pays: it counts shared pages once,
# divided among the processes sharing them, which matters here because a dozen
# node processes share one binary's file-backed pages. RSS would charge each of
# them the full share and make every helper look bigger than it is.
#
# Why not one uniform number. The operator's instinct - "none of these should
# ever exceed 512 MB, maybe 256" - is right about the helpers and wrong about the
# extension host, and the difference is measured, not argued: on a *fresh* tree
# the extension host is already 471 MB PSS, serverMain 160 MB, ptyHost 36 MB and
# the file watcher 34 MB. A uniform 512 MB budget puts the extension host 40 MB
# from its resting size before it has done any work, and 256 MB is below its
# floor outright - which is the same defect as the ceiling this file used to
# derive that sat below what an idle file watcher already held. So each role gets
# the operator's number where it is right, and a number anchored on its own
# measured resting size where it is not.
#
# The reference column is that measurement. It is not a budget; it is the floor
# below which a budget is a kill order rather than a limit.
declare -gA BUDGET_ROLE=(
  [extensionHost]=1073741824  # 1024 MiB, against 471 MB resting
  [serverMain]=536870912      #  512 MiB, against 160 MB resting
  [tsserver]=805306368        #  768 MiB - legitimately large on a big project
  [languageServer]=268435456  #  256 MiB - yaml/json/terraform LS rest near 100
  [fileWatcher]=268435456     #  256 MiB, against 34 MB resting
  [extensionHelper]=536870912 #  512 MiB - terraform-ls, gopls and the like
  [claudeHelper]=536870912    #  512 MiB - MCP servers. The operator's number,
  #                              applied exactly where his instinct is right: a
  #                              helper that holds 1.66 GB is not doing its job
  #                              better than one that holds 300 MB.
)
declare -gA RESTING_ROLE=(
  [extensionHost]=493879296 # 471 MB
  [serverMain]=167772160    # 160 MB
  [fileWatcher]=35651584    #  34 MB
)
# A budget is never allowed below the role's measured resting size times this,
# whatever the pod arithmetic says. This is the guard against the class of error
# that has already bitten this design twice.
RESTING_FACTOR_NUM="${WATCHDOG_RESTING_NUM:-3}"
RESTING_FACTOR_DEN="${WATCHDOG_RESTING_DEN:-2}"
# No single helper may be budgeted more than this share of the pod. The workspace
# is offered at 4 and 8 GiB; without it, a budget reasoned about for the larger
# pod lets one helper own a quarter of the smaller one.
POD_SHARE_DEN="${WATCHDOG_POD_SHARE_DEN:-8}"

# Which roles each mode may signal. The split is by blast radius, not by size:
# nothing in the helper set is visible to the operator when it restarts, and both
# members of the editor set are.
HELPER_ROLES=" tsserver languageServer fileWatcher extensionHelper claudeHelper "
EDITOR_ROLES=" extensionHost serverMain "

# Filled by derive_budgets().
declare -gA BUDGET=()

# Only processes at or above this are written to the sweep log, plus every
# process the watchdog is policing regardless of size. The floor keeps a sweep
# from being a hundred rows of 2 MB shells while still recording anything that
# could plausibly matter later.
SWEEP_LOG_FLOOR="${WATCHDOG_SWEEP_LOG_FLOOR:-33554432}" # 32 MiB

MAX_LOG_LINES="${WATCHDOG_MAX_LOG_LINES:-20000}"
MAX_CSV_LINES="${WATCHDOG_MAX_CSV_LINES:-50000}"
MAX_SWEEP_LINES="${WATCHDOG_MAX_SWEEP_LINES:-200000}"

# Pressure labels. These drive nothing at all - no action is keyed on them - and
# exist so the telemetry says whether the pod was comfortable at the time. The
# ladder that used to act on these numbers is gone; the numbers were the half of
# it worth keeping.
PRESSURE_LOW_DEN="${WATCHDOG_PRESSURE_LOW_DEN:-4}"  # H < max/4  => low
PRESSURE_CRIT_DEN="${WATCHDOG_PRESSURE_CRIT_DEN:-8}" # H < max/8  => critical

# Sweep state. Declared at file scope, not inside main(), so that sourcing with
# WATCHDOG_SOURCE_ONLY=1 gives the test harness correctly-typed globals.
declare -gA P_COMM=() P_CMD=() P_ARGV0=() P_PPID=() P_RSS=() P_PSS=() P_START=() P_AGE=() P_SID=()
declare -gA CHILDREN=() SERVER_TREE=() PROTECTED=() NOT_EDITOR=() PROTECT_REASON=() WATCHDOG_KIN=()
declare -gA POLICED=() CLAUDE_ROOTS=()
declare -ga PIDS=() SERVER_ROOTS=()
declare -gA OVER_SINCE=() KILLED_AT=() KILL_TIMES=() DISARMED=() KILLS=()
SERVER_PID=""
ROLE=other
GUARD=""
PRESSURE=ok
PREV_AT=0
PREV_REFAULT=0
PREV_PGSCAN=0
PREV_U=0
CYCLE=0
SWEEPS=0
UPTIME=0
H_MAX_SEEN=0
H_MIN_SEEN=0
M_MAX=0
POLICED_MAX_SEEN=0
KILLS_TOTAL=0
KILL_TIMES_ALL=""
LAST_KILL_AT=0
PSS_UNAVAILABLE=0
VISIBILITY_WARNED=0
STARTED_AT=${WATCHDOG_NOW:-$EPOCHSECONDS}

# --------------------------------------------------------------------------- #
# derivation - one pure function of memory.max; no state, no I/O
# --------------------------------------------------------------------------- #

# Sets BUDGET from memory.max. An explicit WATCHDOG_BUDGET_<role> wins outright,
# which is how a budget is pinned for an experiment without editing the script.
#
# The two clamps pull in opposite directions and the order matters. The pod share
# is applied first because it expresses what the pod can afford; the resting
# floor is applied second because it expresses what the process demonstrably
# needs, and when those disagree the process wins. A budget below resting usage
# is not a conservative budget, it is a kill loop written down.
derive_budgets() {
  local max=$1 role want share floor var
  share=$((max / POD_SHARE_DEN))
  BUDGET=()
  for role in "${!BUDGET_ROLE[@]}"; do
    var="WATCHDOG_BUDGET_${role}"
    if [[ -n ${!var:-} ]]; then
      BUDGET[$role]=${!var}
      continue
    fi
    want=${BUDGET_ROLE[$role]}
    ((want > share)) && want=$share
    floor=$(((${RESTING_ROLE[$role]:-0} * RESTING_FACTOR_NUM) / RESTING_FACTOR_DEN))
    ((want < floor)) && want=$floor
    BUDGET[$role]=$want
  done
  return 0
}

# True when the mode may signal this role at all.
role_is_armed() {
  local role=$1
  [[ -n ${DISARMED[$role]:-} ]] && return 1
  case "$MODE" in
  enforce) [[ $HELPER_ROLES == *" $role "* ]] ;;
  enforce-all) [[ $HELPER_ROLES == *" $role "* || $EDITOR_ROLES == *" $role "* ]] ;;
  *) return 1 ;;
  esac
}

# --------------------------------------------------------------------------- #
# measurement - reads only, sets M_*/P_* globals, decides nothing
# --------------------------------------------------------------------------- #

# Unreclaimable memory U. With memory.swap.max=0, all anon is unreclaimable.
#
# The `kernel` roll-up in memory.stat must NOT be used: it is dominated by
# slab_reclaimable (dentry/inode cache - 1.9 GiB on the real pod), which the
# kernel hands back under pressure. Counting it makes an idle container look like
# it is about to die. memory.current has the same defect plus the page cache,
# which is why it reads 96% here while U is 28%.
#
# Nothing acts on this any more; it is the pod-level context every per-process
# row is read against, and the only record of what the container was doing at the
# time. Returns 0 on success, 1 on read failure, 2 if the cgroup has no limit.
read_cgroup_memory() {
  local key val
  local anon=0 shmem=0 unevictable=0 slab_unreclaimable=0 kernel_stack=0
  local pagetables=0 sec_pagetables=0 percpu=0 sock=0

  M_FILE=0
  M_SLAB_RECLAIMABLE=0
  M_REFAULT_FILE=0
  M_PGSCAN_DIRECT=0

  while read -r key val; do
    case "$key" in
    anon) anon=$val ;;
    shmem) shmem=$val ;;
    unevictable) unevictable=$val ;;
    slab_unreclaimable) slab_unreclaimable=$val ;;
    kernel_stack) kernel_stack=$val ;;
    pagetables) pagetables=$val ;;
    sec_pagetables) sec_pagetables=$val ;;
    percpu) percpu=$val ;;
    sock) sock=$val ;;
    file) M_FILE=$val ;;
    slab_reclaimable) M_SLAB_RECLAIMABLE=$val ;;
    workingset_refault_file) M_REFAULT_FILE=$val ;;
    pgscan_direct) M_PGSCAN_DIRECT=$val ;;
    esac
  done <"${CGROUP_DIR}/memory.stat" || return 1

  M_ANON=$anon
  M_SHMEM=$shmem
  M_UNEVICTABLE=$unevictable
  M_SLAB_UNRECLAIMABLE=$slab_unreclaimable
  M_KERNEL_STACK=$kernel_stack
  M_PAGETABLES=$pagetables
  M_SEC_PAGETABLES=$sec_pagetables
  M_PERCPU=$percpu
  M_SOCK=$sock

  # sec_pagetables is zero outside nested virtualisation but is genuinely
  # unreclaimable when present, so it is counted rather than assumed away.
  M_U=$((anon + shmem + unevictable + slab_unreclaimable +
    kernel_stack + pagetables + sec_pagetables + percpu + sock))

  local raw=""
  read -r raw <"${CGROUP_DIR}/memory.max" || return 1
  [[ $raw == "max" ]] && return 2
  [[ $raw =~ ^[0-9]+$ ]] || return 1
  M_MAX=$raw

  M_CURRENT=0
  read -r M_CURRENT <"${CGROUP_DIR}/memory.current" 2>/dev/null

  M_H=$((M_MAX - M_U))

  PRESSURE=ok
  ((M_H < M_MAX / PRESSURE_LOW_DEN)) && PRESSURE=low
  ((M_H < M_MAX / PRESSURE_CRIT_DEN)) && PRESSURE=critical
  return 0
}

# memory.pressure "full avg10", scaled by 100 so it compares as an integer.
read_cgroup_pressure() {
  local kind field
  M_PSI_CENTI=0
  while read -r kind field _; do
    [[ $kind == "full" ]] || continue
    field=${field#avg10=}
    [[ $field == *.* ]] || field="${field}.00"
    [[ ${field%%.*} =~ ^[0-9]+$ && ${field##*.} =~ ^[0-9]+$ ]] || continue
    M_PSI_CENTI=$((10#${field%%.*} * 100 + 10#${field##*.}))
  done <"${CGROUP_DIR}/memory.pressure" 2>/dev/null
  return 0
}

read_uptime() {
  local raw=""
  read -r raw _ <"${PROC_DIR}/uptime" 2>/dev/null
  UPTIME=${raw%%.*}
  [[ $UPTIME =~ ^[0-9]+$ ]] || UPTIME=0
  return 0
}

# Fills PIDS / P_COMM / P_CMD / P_ARGV0 / P_PPID / P_START / P_AGE / CHILDREN.
#
# starttime (stat field 22) is read for a reason that is not cosmetic: pids are
# recycled, and every piece of state this watchdog carries between sweeps - how
# long something has been over budget, whether it has already been sent a
# SIGTERM - is keyed on pid *and* starttime. Without that, a recycled pid
# inherits another process's history and can be killed for it.
read_process_table() {
  PIDS=()
  P_COMM=()
  P_CMD=()
  P_ARGV0=()
  P_PPID=()
  P_START=()
  P_AGE=()
  P_SID=()
  P_RSS=()
  P_PSS=()
  CHILDREN=()

  local entry pid line rest comm ppid start sid
  local -a argv f

  for entry in "${PROC_DIR}"/[0-9]*; do
    pid=${entry##*/}
    read -r line <"$entry/stat" 2>/dev/null || continue

    # /proc/<pid>/stat is "pid (comm) state ppid ...", and comm may contain
    # spaces and parentheses, so split on the *last* ") " rather than tokenise.
    rest=${line##*') '}
    [[ $rest == "$line" ]] && continue
    comm=${line#*'('}
    comm=${comm%%') '*}
    read -r -a f <<<"$rest"
    ppid=${f[1]:-}
    [[ $ppid =~ ^[0-9]+$ ]] || continue
    # f[0] is state, so f[19] is stat field 22, starttime, in USER_HZ ticks, and
    # f[3] is field 6, the session id.
    start=${f[19]:-0}
    [[ $start =~ ^[0-9]+$ ]] || start=0
    sid=${f[3]:-0}
    [[ $sid =~ ^[0-9]+$ ]] || sid=0

    argv=()
    mapfile -d '' -t argv <"$entry/cmdline" 2>/dev/null
    PIDS+=("$pid")
    P_COMM[$pid]=$comm
    P_CMD[$pid]="${argv[*]}"
    # argv[0] is kept as its own field rather than recovered later by cutting
    # P_CMD at the first space, which is wrong for any executable path
    # containing one, and which is precisely the kind of "close enough" string
    # handling this script has already been bitten by.
    P_ARGV0[$pid]="${argv[0]:-}"
    P_PPID[$pid]=$ppid
    P_START[$pid]=$start
    P_SID[$pid]=$sid
    P_AGE[$pid]=$((UPTIME - start / USER_HZ))
    # Written with an explicit $: inside (( )) an associative-array subscript is
    # a string, so `P_AGE[pid]` would look up the key "pid" and quietly read 0.
    ((${P_AGE[$pid]} < 0)) && P_AGE[$pid]=0
    CHILDREN[$ppid]+=" $pid"
  done
  return 0
}

# PSS from smaps_rollup, falling back to RSS from statm.
#
# smaps_rollup walks the page tables, so it is the expensive read in this script;
# it is done once a minute for a few dozen processes and never in the cgroup
# sample. The fallback exists because smaps_rollup is absent on some kernels and
# unreadable for a process that exits mid-sweep - and when it is used, the row
# says so, because silently substituting a number that is 30% larger would make
# every budget look tighter than it is.
read_usage() {
  local pid res key val got
  for pid in "$@"; do
    read -r _ res _ <"${PROC_DIR}/${pid}/statm" 2>/dev/null || continue
    P_RSS[$pid]=$((res * PAGE_SIZE))
    got=""
    if [[ -r "${PROC_DIR}/${pid}/smaps_rollup" ]]; then
      while read -r key val _; do
        if [[ $key == "Pss:" ]]; then
          got=$val
          break
        fi
      done <"${PROC_DIR}/${pid}/smaps_rollup"
    fi
    if [[ $got =~ ^[0-9]+$ ]]; then
      P_PSS[$pid]=$((got * 1024))
    else
      P_PSS[$pid]=${P_RSS[$pid]}
      PSS_UNAVAILABLE=1
    fi
  done
  return 0
}

# --------------------------------------------------------------------------- #
# selection - pure over the tables above; produces sets, takes no action
# --------------------------------------------------------------------------- #

# Fills SERVER_ROOTS with every remote-server entrypoint, and sets SERVER_PID to
# the first of them (used only for logging).
#
# Three things about a real server tree that a plausible-looking implementation
# gets wrong, all three confirmed against a live workspace:
#
#  - comm is NOT "node". Every node process in the server tree - server-main.js,
#    ptyHost, extensionHost, fileWatcher, node-based language servers - reports
#    comm=MainThread, because V8 renames its main thread with prctl(PR_SET_NAME).
#    Anything that keys off comm=="node" is keying off a state that never occurs.
#
#  - argv[0] is the signal that does hold. VS Code launches the server as
#    `<server-dir>/node <server-dir>/out/server-main.js ...`, and argv[0] keeps
#    the interpreter's real path. Requiring it to live under /.vscode-server/ (or,
#    for a future launcher outside that tree, to be named node) is what keeps a
#    `cat`, `tail -f` or `grep` over the same path from being elected as the root
#    of everything the watchdog then decides.
#
#  - there can be more than one. `--reconnection-grace-time` keeps a disconnected
#    server alive for hours, and a window on a different commit gets its own
#    server. Electing one and scoping to it would leave the other tree not merely
#    unmanaged but unprotected, because the ptyHost excision only runs inside the
#    tree that was discovered. So every root counts and the managed tree is the
#    union of their subtrees.
#
# Matching is always on a whole argv element, never on a substring of the joined
# command line.
find_server_roots() {
  local pid arg exe
  local -a argv
  SERVER_ROOTS=()
  SERVER_PID=""

  for pid in "${PIDS[@]}"; do
    [[ ${P_CMD[$pid]} == *"/.vscode-server/"*"out/server-main.js"* ]] || continue
    argv=()
    mapfile -d '' -t argv <"${PROC_DIR}/${pid}/cmdline" 2>/dev/null
    ((${#argv[@]} > 1)) || continue
    exe=${argv[0]##*/}
    [[ ${argv[0]} == *"/.vscode-server/"* || $exe == node || $exe == node[0-9]* ]] || continue
    # From argv[1]: the server path appearing as argv[0] would mean the .js file
    # is itself being executed as the program, which is not how it is launched.
    for arg in "${argv[@]:1}"; do
      [[ $arg == *"/.vscode-server/"*"out/server-main.js" ]] || continue
      SERVER_ROOTS+=("$pid")
      break
    done
  done

  ((${#SERVER_ROOTS[@]})) || return 1
  # shellcheck disable=SC2034
  # Read by script-memory-watchdog-test.sh, which asserts which process is
  # elected as the root - the one selection defect a fixture can catch early.
  SERVER_PID=${SERVER_ROOTS[0]}
  return 0
}

# Sets SERVER_TREE to the union of every root's descendants. Returns 1 when no
# server is running, leaving SERVER_TREE empty.
build_server_tree() {
  local root pid
  local -A one=()
  SERVER_TREE=()
  find_server_roots || return 1
  for root in "${SERVER_ROOTS[@]}"; do
    subtree_of "$root" one
    for pid in "${!one[@]}"; do
      SERVER_TREE[$pid]=1
    done
  done
  return 0
}

# subtree_of <root-pid> <name-of-output-associative-array>
subtree_of() {
  local root=$1
  local -n out=$2
  local queue=("$root") cur kids k
  out=()
  # shellcheck disable=SC2004
  # `out` is a nameref to an associative array, so the subscript is a string
  # key. Dropping the $ would make bash key it on the literal name.
  out[$root]=1
  while ((${#queue[@]})); do
    cur=${queue[0]}
    queue=("${queue[@]:1}")
    kids=${CHILDREN[$cur]:-}
    # shellcheck disable=SC2086
    # kids is a space-joined list of integers this script built itself.
    for k in $kids; do
      [[ -n ${out[$k]:-} ]] && continue
      # shellcheck disable=SC2004
      out[$k]=1
      queue+=("$k")
    done
  done
  return 0
}

# True when the process is running a binary that VS Code itself shipped, i.e. one
# under ~/.vscode-server. This is the structural boundary between "a process VS
# Code started with its own runtime" and "a process that merely happens to sit
# inside the tree", and it is one of the two primary safety rules here.
#
# A fully provisioned workspace has two unrelated node installations: VS Code's
# bundled one at ~/.vscode-server/cli/servers/Stable-<commit>/server/node, which
# arrives with the server download, and mise's on PATH, which is what the
# operator's repo tooling and agent sessions run on. There is no /usr/bin/node
# and no node on PATH at all without dotfiles. Every process VS Code spawns runs
# a binary under ~/.vscode-server; nothing the operator runs does.
#
# So keying detection on "is this node" by comm, by basename, or by a loose
# cmdline match would make an agent session indistinguishable from an editor
# helper. Path, and only path.
is_vscode_binary() {
  [[ ${P_ARGV0[$1]:-} == *"/.vscode-server/"* ]]
}

# True for the root process of an agent session. Structural: the program being
# executed is named claude, by comm (a compiled launcher) or by argv[0]'s
# basename (a shebang script, where comm is the interpreter). Never a substring
# of the joined command line - `*/claude*` once protected an unrelated process
# whose scratchpad path contained /claude-10001.
is_claude_root() {
  local pid=$1
  [[ ${P_COMM[$pid]:-} == "claude" ]] && return 0
  local exe=${P_ARGV0[$pid]:-}
  [[ ${exe##*/} == "claude" ]]
}

# True for an interactive shell or a terminal multiplexer, i.e. a boundary the
# helper walk must not cross. Everything below one of these inside an agent
# session is the agent's *tool calls* - builds, test runs, `gh run watch` - which
# are in-flight work with no supervisor to restart them. They are excluded from
# policing on purpose, and that exclusion is the difference between "anything a
# session invokes is fair game" as a principle and as a foot-gun.
is_shell_like() {
  local pid=$1
  local exe=${P_ARGV0[$pid]:-}
  case "${P_COMM[$pid]:-}" in
  bash | sh | dash | zsh | fish | ksh | tmux* | screen | sshd | ssh) return 0 ;;
  esac
  case "${exe##*/}" in
  bash | sh | dash | zsh | fish | ksh | tmux | screen | sshd | ssh) return 0 ;;
  esac
  return 1
}

# The watchdog's own process, everything that started it, and everything it
# started. Structural, by pid: this replaces a `*memory-watchdog*` cmdline match
# that once protected every process in a test harness because the harness lived
# in a directory whose path contained that string. Two full runs of that harness
# looked clean while exercising nothing. Identity is a thing you know about
# yourself, not a thing you pattern-match out of other processes' arguments.
compute_watchdog_kin() {
  WATCHDOG_KIN=()
  local cur=$$ hops=0 p
  local -A mine=()
  subtree_of "$$" mine
  for p in "${!mine[@]}"; do
    WATCHDOG_KIN[$p]=self
  done
  # Ancestors. Bounded, because a corrupt or racing ppid chain must not spin.
  while ((cur > 1 && hops < 64)); do
    cur=${P_PPID[$cur]:-0}
    ((cur > 1)) || break
    WATCHDOG_KIN[$cur]=ancestor
    ((hops += 1))
  done
  return 0
}

# True when an argv element names one of the operator's own programs. This is
# the one guard that has to look at arguments rather than at argv[0], because the
# case it exists for is a payload run by somebody else's interpreter: an agent
# session that an extension spawned as `<vscode>/node .../claude-code/cli.js`
# has VS Code's binary at argv[0] and is not under ptyHost, so neither of the
# structural rules reaches it.
#
# Matching is on whole path segments, never on a raw substring. Substrings are
# what made `*/claude*` protect an unrelated process whose scratchpad path
# happened to contain /claude: the segment there was `claude-10001`, which is not
# the program and does not match.
is_operator_payload() {
  local tok seg
  for tok in ${P_CMD[$1]:-}; do
    tok=${tok%/}
    seg=${tok##*/}
    case "$seg" in
    claude | tmux | chezmoi) return 0 ;;
    esac
    case "/${tok}/" in
    */claude-code/* | */claude-code-*/*) return 0 ;;
    esac
  done
  return 1
}

# The never-signal list. Every action consults this directly, so a defect in
# tree-walking still cannot route around it. Sets GUARD to the rule that fired,
# so that a protection can be reported rather than merely happening.
is_never_signal() {
  local pid=$1
  GUARD=""
  ((pid <= 1)) && GUARD=pid1 && return 0
  ((pid == $$)) && GUARD=self && return 0
  ((pid == BASHPID)) && GUARD=self && return 0
  ((pid == PPID)) && GUARD=self && return 0
  if [[ -n ${WATCHDOG_KIN[$pid]:-} ]]; then
    GUARD=watchdog-${WATCHDOG_KIN[$pid]}
    return 0
  fi
  case "${P_COMM[$pid]:-}" in
  coder | claude | chezmoi | sshd | screen | init | systemd)
    GUARD="comm"
    return 0
    ;;
  tmux*)
    GUARD="comm"
    return 0
    ;;
  esac
  # argv[0]'s basename, i.e. the program actually being executed - the same
  # question is_vscode_binary asks, asked of the other side. `/home/coder/...`
  # appears in nearly every command line in this pod, so a rule that looked
  # anywhere but argv[0] for the name `coder` would protect the entire pod.
  case "${P_ARGV0[$pid]:-}" in
  */coder | coder | */chezmoi | chezmoi | */tmux | tmux | */claude | claude)
    GUARD=argv0
    return 0
    ;;
  esac
  if is_operator_payload "$pid"; then
    GUARD=payload
    return 0
  fi
  return 1
}

# Everything the watchdog must never touch: the never-signal rules anywhere in
# the pod, plus every ptyHost fork inside the server tree and all its
# descendants, plus anything in the tree not running a VS Code binary.
# PROTECT_REASON records which rule claimed each pid, which is what makes an
# over-broad guard visible instead of silently inert.
compute_protected() {
  PROTECTED=()
  NOT_EDITOR=()
  PROTECT_REASON=()
  local pid p
  local -A pty=()

  compute_watchdog_kin

  for pid in "${PIDS[@]}"; do
    if is_never_signal "$pid"; then
      PROTECTED[$pid]=1
      PROTECT_REASON[$pid]=$GUARD
    fi
  done

  # Two rules about *position* rather than identity, kept in their own set. The
  # distinction is load-bearing and was learned the hard way: everything in
  # PROTECTED is protected by what it is and may never be signalled by anything,
  # whereas these two say only "this is not one of the editor's own helpers" -
  # which is the correct rule for the editor walk and the wrong one for the
  # second population. An MCP server belonging to a session that happens to be
  # running in a VS Code terminal is inside the tree and does not run VS Code's
  # binary, and it is exactly what this watchdog is meant to bound.
  #
  # First: anything in the tree not running a binary VS Code shipped. An agent
  # session spawned by an extension is a child of the extension host and not of
  # ptyHost, so tree position would not save it; its executable path does - and
  # it is *also* claimed by the payload rule above, which is identity and is
  # absolute. That overlap is deliberate belt-and-braces, not redundancy.
  for pid in "${!SERVER_TREE[@]}"; do
    if ! is_vscode_binary "$pid"; then
      NOT_EDITOR[$pid]=1
      PROTECT_REASON[$pid]=${PROTECT_REASON[$pid]:-foreign-binary}
    fi
  done

  # Terminals, and everything started in one. Tree membership is NOT a safe kill
  # criterion: tmux sessions and long-running agent runs started from a VS Code
  # integrated terminal are descendants of the server tree via ptyHost.
  #
  # Second: the ptyHost subtree. Shells, multiplexers and everything started in
  # one are absolutely protected anyway - by comm, by argv[0], by the payload
  # rule, and by the walk in compute_policed stopping at shells - so what this
  # adds is the position, not the only line of defence.
  for pid in "${!SERVER_TREE[@]}"; do
    if [[ ${P_CMD[$pid]:-} == *"--type=ptyHost"* ]]; then
      subtree_of "$pid" pty
      for p in "${!pty[@]}"; do
        NOT_EDITOR[$p]=1
        PROTECT_REASON[$p]=${PROTECT_REASON[$p]:-ptyhost}
      done
    fi
  done
  return 0
}

# Sets ROLE for a process inside the VS Code server tree.
#
# `--type=` flags are matched as whole argv elements (P_CMD is argv joined with
# spaces, so the surrounding spaces make the match exact). ptyHost is tested
# first, and additionally as a loose substring: over-matching ptyHost only ever
# means protecting something that could have been touched, which is the safe
# direction, whereas over-matching any other role means mis-classifying it.
role_of() {
  local cmd=" ${P_CMD[$1]:-} "
  local argv0=${P_ARGV0[$1]:-}
  case "$cmd" in
  *" --type=ptyHost "* | *"--type=ptyHost"*) ROLE=ptyHost ;;
  *" --type=extensionHost "*) ROLE=extensionHost ;;
  *" --type=fileWatcher "*) ROLE=fileWatcher ;;
  *"tsserver.js "* | *"/typescript/lib/tsserver"*) ROLE=tsserver ;;
  # Looser than the rest: language servers have no common launch convention, so
  # these are prefix/suffix guesses. They are only ever consulted for processes
  # already inside the server tree and outside the ptyHost subtree, which is what
  # keeps the blast radius of a wrong guess to one restartable helper.
  *yaml-language-server* | *jsonServerMain* | *-language-server* | *languageserver*) ROLE=languageServer ;;
  *"out/server-main.js "*) ROLE=serverMain ;;
  *)
    # Native helpers shipped inside an extension - terraform-ls on the live tree,
    # and gopls / rust-analyzer / clangd on the same pattern. Keyed on argv[0],
    # never on the joined command line: an agent session launched by an extension
    # has the extension's directory all over its arguments while its executable
    # is mise's node, and matching the arguments would classify it as a sheddable
    # helper. Checked last, so a node language server - which also lives under
    # extensions/ but runs VS Code's own node - keeps its role above.
    if [[ $argv0 == *"/.vscode-server/extensions/"* ]]; then
      ROLE=extensionHelper
    else
      ROLE=other
    fi
    ;;
  esac
  return 0
}

# Fills POLICED with pid -> role: every process this watchdog is willing to have
# an opinion about. Two disjoint populations, found two different ways.
#
# 1. The VS Code server tree, minus the guards. Unchanged from the version that
#    only knew about VS Code.
#
# 2. Helpers spawned by an agent session - the MCP servers and other long-lived
#    children that the tree-scoped selection could not see at all, and where the
#    largest single offender ever measured (1.66 GB of python) lived. The walk
#    starts at each session root and descends, but never through a shell or a
#    multiplexer: below one of those is the session's *tool calls*, which are
#    in-flight work that nothing will restart. The session root itself is
#    protected by name; this is only about what it spawned.
#
# The positional exclusions - the ptyHost subtree, and "does not run a binary VS
# Code shipped" - are permeable to the second walk, and that is the one
# deliberate hole in the rules; it is worth stating plainly. A session started
# with `coder ssh` sits under the agent and a session started in a VS Code
# terminal sits under ptyHost, running the operator's python or node rather than
# VS Code's; they are the same thing to the operator, and sparing one set of MCP
# servers because of which terminal its session came from would make the
# mechanism miss half its cases silently. What those rules are actually for -
# shells, multiplexers, the session itself, agent payloads, and every command run
# in a terminal - is still absolutely protected, by identity, because the walk
# stops at shells and every guard in is_never_signal still applies.
compute_policed() {
  POLICED=()
  CLAUDE_ROOTS=()
  local pid root cur kids k

  for pid in "${!SERVER_TREE[@]}"; do
    [[ -n ${PROTECTED[$pid]:-} || -n ${NOT_EDITOR[$pid]:-} ]] && continue
    role_of "$pid"
    [[ $ROLE == "ptyHost" || $ROLE == "other" ]] && continue
    POLICED[$pid]=$ROLE
  done

  for pid in "${PIDS[@]}"; do
    is_claude_root "$pid" || continue
    CLAUDE_ROOTS[$pid]=1
  done

  local -a queue=()
  local sid
  for root in "${!CLAUDE_ROOTS[@]}"; do
    kids=${CHILDREN[$root]:-}
    # shellcheck disable=SC2086
    for k in $kids; do queue+=("${k}:${P_SID[$root]:-0}"); done
  done
  while ((${#queue[@]})); do
    cur=${queue[0]%%:*}
    sid=${queue[0]#*:}
    queue=("${queue[@]:1}")
    # Two independent boundaries, either of which ends the walk.
    #
    # The session id is the stronger of the two and it is measured, not assumed:
    # on the live workspace an agent session root has pgid == its own pid and
    # sid == the login shell's session, while every tool call it runs has pgid
    # == sid == its own pid - i.e. Claude Code detaches each Bash tool call into
    # a new session so that it can kill the whole tree later. A stdio MCP server
    # is spawned to talk over pipes and stays in the session it was started
    # from. So "same session as the root" separates the servers from the work
    # even when the tool call's shell has exec'd itself away, which the shell
    # test alone would miss.
    #
    # If that ever stops being true, this walk polices nothing rather than
    # policing the wrong thing, and check_visibility says so in the log.
    [[ ${P_SID[$cur]:-0} == "$sid" ]] || continue
    # And a shell is a boundary in its own right: neither it nor anything under
    # it is policed, whatever session it is in.
    is_shell_like "$cur" && continue
    kids=${CHILDREN[$cur]:-}
    # shellcheck disable=SC2086
    for k in $kids; do queue+=("${k}:${sid}"); done
    # Protected by identity: not a candidate. Excluded only positionally - in
    # the ptyHost subtree, or not running VS Code's own binary: still a
    # candidate, for the reason given above.
    [[ -n ${PROTECTED[$cur]:-} ]] && continue
    is_claude_root "$cur" && continue
    [[ -n ${POLICED[$cur]:-} ]] && continue
    POLICED[$cur]=claudeHelper
  done
  return 0
}

# A short, stable identity for a policed process - what it *is*, as opposed to
# which pid it happens to have this time. This is the breadcrumb that makes the
# sweep log answerable after the fact ("which MCP server was that?"), and the
# label a metrics exporter would bucket on.
#
# Secrets are redacted here rather than at read time, because this is the only
# place a command line is written to a file that might later be shipped
# somewhere: VS Code puts --connection-token= on its own argv, and an MCP server
# can be launched with an API key in an argument.
identity_of() {
  local pid=$1 role=$2 tok seg fallback
  # For a helper, the interpreter is never the interesting part of the name: a
  # dozen unrelated MCP servers are all `node` or `python3`, and what
  # distinguishes them is the first argument that is not the interpreter and not
  # a flag. For everything else argv[0] is the name, because that is the thing
  # the role was decided from.
  if [[ $role == "claudeHelper" || $role == "extensionHelper" ]]; then
    for tok in ${P_CMD[$pid]:-}; do
      seg=${tok##*/}
      [[ -z $seg ]] && continue
      case "$seg" in
      -* | node | node[0-9]* | python | python[0-9] | python[0-9].[0-9]* | uv | uvx | npx | bun | deno) continue ;;
      esac
      printf '%s' "${seg%.js}"
      return 0
    done
  fi
  fallback=${P_ARGV0[$pid]:-}
  [[ -n $fallback ]] || fallback=${P_COMM[$pid]:-unknown}
  printf '%s' "${fallback##*/}"
  return 0
}

redact() {
  local acc="" tok
  for tok in $1; do
    case "$tok" in
    *token=* | *TOKEN=* | *key=* | *KEY=* | *secret=* | *SECRET=* | *password=* | *PASSWORD=*)
      acc+=" ${tok%%=*}=<redacted>"
      ;;
    *) acc+=" ${tok}" ;;
    esac
  done
  printf '%s' "${acc# }"
}

# --------------------------------------------------------------------------- #
# action - the only place that writes state or signals anything
# --------------------------------------------------------------------------- #

LOG_LINES=0
CSV_LINES=0
SWEEP_LINES=0

log_action() {
  local msg="$*" stamp
  printf -v stamp '%(%Y-%m-%dT%H:%M:%S%z)T' -1
  [[ $MODE == "observe" ]] && msg="[observe] ${msg}"
  printf '%s %s\n' "$stamp" "$msg" >>"${STATE_DIR}/actions.log"
  ((LOG_LINES += 1))
  if ((LOG_LINES > MAX_LOG_LINES)); then
    mv -f "${STATE_DIR}/actions.log" "${STATE_DIR}/actions.log.1" 2>/dev/null
    LOG_LINES=0
  fi
  return 0
}

fmt_gib() {
  local v=$1 sign=""
  if ((v < 0)); then
    sign="-"
    v=$((-v))
  fi
  printf '%s%d.%02d GiB' "$sign" "$((v / GIB))" "$((v % GIB * 100 / GIB))"
}

fmt_mib() {
  printf '%d MiB' "$(($1 / MIB))"
}

publish_headroom() {
  printf '%s free (%s)\n' "$(fmt_gib "$1")" "$2" >"${STATE_DIR}/headroom.tmp" &&
    mv -f "${STATE_DIR}/headroom.tmp" "${STATE_DIR}/headroom"
  return 0
}

# The workspace UI tile: the largest policed process as a share of its budget.
# This is the number the operator used to obtain by running ps himself, which is
# the habit this whole change exists to end.
publish_top() {
  local best="none" line
  if [[ -n ${TOP_ROLE:-} ]]; then
    printf -v line '%s %s (%d%% of %s)' \
      "$TOP_ID" "$(fmt_mib "$TOP_PSS")" "$TOP_PCT" "$(fmt_mib "$TOP_BUDGET")"
    best=$line
  fi
  printf '%s\n' "$best" >"${STATE_DIR}/top.tmp" &&
    mv -f "${STATE_DIR}/top.tmp" "${STATE_DIR}/top"
  return 0
}

CSV_HEADER="ts,mem_max,mem_current,u,h,anon,shmem,unevictable,slab_unreclaimable,slab_reclaimable,kernel_stack,pagetables,sec_pagetables,percpu,sock,file,psi_full_avg10_centi,refault_file_per_s,pgscan_direct_per_s,pressure,du_bytes_per_s"

append_calibration() {
  local csv="${STATE_DIR}/calibration.csv" first=""
  if [[ -s $csv ]]; then
    # A file written by an earlier version has different columns, and appending
    # to it would produce one CSV that is silently two schemas. Rotate it.
    read -r first <"$csv" 2>/dev/null
    if [[ $first != "$CSV_HEADER" ]]; then
      mv -f "$csv" "${csv}.1" 2>/dev/null
    fi
  fi
  if [[ ! -s $csv ]]; then
    printf '%s\n' "$CSV_HEADER" >"$csv"
  fi
  printf '%s\n' "$*" >>"$csv"
  ((CSV_LINES += 1))
  if ((CSV_LINES > MAX_CSV_LINES)); then
    mv -f "$csv" "${csv}.1" 2>/dev/null
    CSV_LINES=0
  fi
  return 0
}

SWEEP_HEADER=$'#ts\tsweep\tpid\tstart\trole\tstate\tpss_kb\trss_kb\tage_s\tbudget_kb\tover_s\tguard\tidentity\tcmd'

# The per-process record. It is the point of this version of the script as much
# as the killing is: every post-mortem in this investigation was unanswerable
# because the watchdog computed exactly this table on every cycle and then threw
# it away, so "what was holding the memory ten minutes before the kill" had no
# source. It is a local file first - Prometheus and Loki can be added later and
# cannot be backfilled - and it is written whatever the mode, because observe
# mode is where the budgets get their evidence.
append_sweep() {
  local dst="${STATE_DIR}/sweep.log" first=""
  if [[ -s $dst ]]; then
    read -r first <"$dst" 2>/dev/null
    [[ $first != "$SWEEP_HEADER" ]] && mv -f "$dst" "${dst}.1" 2>/dev/null
  fi
  [[ -s $dst ]] || printf '%s\n' "$SWEEP_HEADER" >"$dst"
  printf '%s\n' "$@" >>"$dst"
  SWEEP_LINES=$((SWEEP_LINES + $#))
  if ((SWEEP_LINES > MAX_SWEEP_LINES)); then
    mv -f "$dst" "${dst}.1" 2>/dev/null
    SWEEP_LINES=0
  fi
  return 0
}

signal_pid() {
  local sig=$1 pid=$2 role=$3 why=$4
  # Second, independent guard. Selection already excluded these; this exists so
  # that a defect in tree-walking still cannot reach a protected process.
  if [[ -n ${PROTECTED[$pid]:-} ]] || is_never_signal "$pid"; then
    log_action "REFUSED sig=${sig} pid=${pid} reason=protected (${why})"
    return 1
  fi
  # And the positional rules, restated independently of selection: inside the
  # server tree, the only thing that may be signalled without being one of the
  # editor's own helpers is a helper a session spawned directly.
  if [[ -n ${NOT_EDITOR[$pid]:-} && $role != "claudeHelper" ]]; then
    log_action "REFUSED sig=${sig} pid=${pid} reason=${PROTECT_REASON[$pid]:-not-editor} role=${role} (${why})"
    return 1
  fi
  [[ $MODE == "observe" ]] || kill "-${sig}" "$pid" 2>/dev/null
  return 0
}

# The circuit breaker. Called after a kill; decides whether this role has stopped
# being a drifting role and started being a loop.
record_kill() {
  local role=$1 now=$2
  local t keep="" n=0 all="" na=0

  KILLS[$role]=$((${KILLS[$role]:-0} + 1))
  KILLS_TOTAL=$((KILLS_TOTAL + 1))
  LAST_KILL_AT=$now

  for t in ${KILL_TIMES[$role]:-}; do
    ((now - t < LOOP_WINDOW)) || continue
    keep+="${t} "
    ((n += 1))
  done
  keep+="${now}"
  ((n += 1))
  KILL_TIMES[$role]=$keep

  for t in ${KILL_TIMES_ALL:-}; do
    ((now - t < LOOP_WINDOW)) || continue
    all+="${t} "
    ((na += 1))
  done
  all+="${now}"
  ((na += 1))
  KILL_TIMES_ALL=$all

  if ((n >= LOOP_KILLS)); then
    DISARMED[$role]=1
    log_action "DISARMED role=${role} reason=kill-loop kills=${n} window=${LOOP_WINDOW}s budget=$(fmt_mib "${BUDGET[$role]:-0}") - a role that has to be killed this often does not have a drift problem, it has a wrong budget; raise WATCHDOG_BUDGET_${role} or accept the size, but this watchdog will not keep restarting it"
  fi
  if ((na >= GLOBAL_LOOP_KILLS)); then
    local r
    for r in "${!BUDGET[@]}"; do DISARMED[$r]=1; done
    log_action "DISARMED role=all reason=global-kill-loop kills=${na} window=${LOOP_WINDOW}s - too many kills across roles for the budgets to be right; enforcement is off until the watchdog restarts"
  fi
  return 0
}

# --------------------------------------------------------------------------- #
# the sweep - measure every process, decide, act, record
# --------------------------------------------------------------------------- #

# Prunes dwell and kill bookkeeping for keys whose process is gone. Without this
# the maps grow for the life of the pod, and - worse - a recycled pid could
# inherit an entry. Keys are pid:starttime, so recycling changes the key.
prune_state() {
  local key pid start
  local -A live=()
  for pid in "${PIDS[@]}"; do
    live["${pid}:${P_START[$pid]:-0}"]=1
  done
  for key in "${!OVER_SINCE[@]}"; do
    [[ -n ${live[$key]:-} ]] || unset 'OVER_SINCE[$key]'
  done
  for key in "${!KILLED_AT[@]}"; do
    [[ -n ${live[$key]:-} ]] || unset 'KILLED_AT[$key]'
  done
  return 0
}

sweep_once() {
  local now=$1
  local pid role budget pss key over_since over_s state guard id cmd age
  local -a rows=()
  local policed_n=0 over_n=0 killed_n=0 total_pss=0

  read_uptime
  read_process_table
  build_server_tree
  compute_protected
  compute_policed
  read_usage "${PIDS[@]}"
  prune_state

  TOP_ROLE=""
  TOP_ID=""
  TOP_PSS=0
  TOP_BUDGET=0
  TOP_PCT=0

  for pid in "${!POLICED[@]}"; do
    role=${POLICED[$pid]}
    budget=${BUDGET[$role]:-0}
    pss=${P_PSS[$pid]:-0}
    age=${P_AGE[$pid]:-0}
    key="${pid}:${P_START[$pid]:-0}"
    ((policed_n += 1))
    total_pss=$((total_pss + pss))

    id="$(identity_of "$pid" "$role")"
    if ((budget > 0)) && ((pss * 100 / budget > TOP_PCT)); then
      TOP_ROLE=$role
      TOP_PSS=$pss
      TOP_BUDGET=$budget
      TOP_PCT=$((pss * 100 / budget))
      TOP_ID=$id
    fi

    state=ok
    over_s=0
    if ((budget > 0 && pss > budget)); then
      ((over_n += 1))
      : "${OVER_SINCE[$key]:=$now}"
      over_since=${OVER_SINCE[$key]}
      over_s=$((now - over_since))
      state=over
      if ((over_s >= DWELL_SECONDS)) && ((age >= MIN_AGE)); then
        state=over-dwell
        if [[ -n ${DISARMED[$role]:-} ]]; then
          state=disarmed
        elif ! role_is_armed "$role"; then
          # Observe mode, or a role this mode does not arm. Report the kill that
          # would have happened, then restart the dwell clock so the same process
          # is reported once per dwell period rather than on every sweep for the
          # rest of its life.
          state=would-kill
          log_action "would-kill pid=${pid} role=${role} id=${id} pss=${pss} budget=${budget} over_s=${over_s} age=${age} mode=${MODE} armed=no"
          OVER_SINCE[$key]=$now
        elif [[ -n ${KILLED_AT[$key]:-} ]]; then
          # Already asked politely. Escalate once the grace has elapsed.
          if ((now - KILLED_AT[$key] >= KILL_GRACE)); then
            if signal_pid KILL "$pid" "$role" "drift ${role}"; then
              state=killed-9
              log_action "kill sig=KILL pid=${pid} role=${role} id=${id} pss=${pss} budget=${budget} over_s=${over_s} (still over budget ${KILL_GRACE}s after SIGTERM)"
            fi
          else
            state=terminating
          fi
        else
          if signal_pid TERM "$pid" "$role" "drift ${role}"; then
            KILLED_AT[$key]=$now
            state=killed
            ((killed_n += 1))
            log_action "kill sig=TERM pid=${pid} role=${role} id=${id} pss=${pss} budget=${budget} over_s=${over_s} age=${age} mode=${MODE}"
            record_kill "$role" "$now"
          fi
        fi
      fi
    else
      unset 'OVER_SINCE[$key]'
      unset 'KILLED_AT[$key]'
    fi

    guard=${PROTECT_REASON[$pid]:-'-'}
    cmd="$(redact "${P_CMD[$pid]:-}")"
    rows+=("${now}"$'\t'"${SWEEPS}"$'\t'"${pid}"$'\t'"${P_START[$pid]:-0}"$'\t'"${role}"$'\t'"${state}"$'\t'"$((pss / 1024))"$'\t'"$((${P_RSS[$pid]:-0} / 1024))"$'\t'"${age}"$'\t'"$((budget / 1024))"$'\t'"${over_s}"$'\t'"${guard}"$'\t'"${id}"$'\t'"${cmd:0:160}")
  done

  # Everything else that is large enough to matter, policed or not. This is what
  # makes the log answerable about the processes the watchdog does *not* manage -
  # which, on the evidence of every OOM recorded for this workspace, is where the
  # memory actually was.
  for pid in "${PIDS[@]}"; do
    [[ -n ${POLICED[$pid]:-} ]] && continue
    pss=${P_PSS[$pid]:-0}
    ((pss >= SWEEP_LOG_FLOOR)) || continue
    guard=${PROTECT_REASON[$pid]:-'-'}
    cmd="$(redact "${P_CMD[$pid]:-}")"
    rows+=("${now}"$'\t'"${SWEEPS}"$'\t'"${pid}"$'\t'"${P_START[$pid]:-0}"$'\t'"unmanaged"$'\t'"seen"$'\t'"$((pss / 1024))"$'\t'"$((${P_RSS[$pid]:-0} / 1024))"$'\t'"${P_AGE[$pid]:-0}"$'\t'"0"$'\t'"0"$'\t'"${guard}"$'\t'"${P_COMM[$pid]:-unknown}"$'\t'"${cmd:0:160}")
  done

  ((policed_n > POLICED_MAX_SEEN)) && POLICED_MAX_SEEN=$policed_n

  rows+=("${now}"$'\t'"${SWEEPS}"$'\t'"0"$'\t'"0"$'\t'"TOTAL"$'\t'"${PRESSURE}"$'\t'"$((total_pss / 1024))"$'\t'"0"$'\t'"0"$'\t'"0"$'\t'"0"$'\t'"-"$'\t'"policed=${policed_n},over=${over_n},killed=${killed_n},procs=${#PIDS[@]},tree=${#SERVER_TREE[@]},sessions=${#CLAUDE_ROOTS[@]}"$'\t'"h=${M_H},u=${M_U},psi=${M_PSI_CENTI},mode=${MODE}")
  append_sweep "${rows[@]}"
  printf '%s\n' "$SWEEP_HEADER" "${rows[@]}" >"${STATE_DIR}/sweep.latest.tmp" &&
    mv -f "${STATE_DIR}/sweep.latest.tmp" "${STATE_DIR}/sweep.latest"

  POLICED_N=$policed_n
  OVER_N=$over_n
  publish_top
  return 0
}

# The falsification the census used to provide, generalised. A watchdog that
# manages nothing looks exactly like a watchdog with nothing to do, and the only
# difference is whether anything was ever there to manage. Nothing is *wrong*
# with a workspace where VS Code is closed and no session is running - but it is
# worth one line in the log, because the alternative reading is that selection is
# broken, and that reading has been correct before.
VISIBILITY_WARMUP="${WATCHDOG_VISIBILITY_WARMUP:-30}" # sweeps

check_visibility() {
  ((VISIBILITY_WARNED)) && return 0
  ((SWEEPS >= VISIBILITY_WARMUP)) || return 0
  VISIBILITY_WARNED=1
  if ((POLICED_MAX_SEEN == 0)); then
    log_action "WARNING no process has been policed in ${SWEEPS} sweeps - either nothing this watchdog manages has run, or selection is finding nothing; sweep.latest shows what was there"
  fi
  return 0
}

publish_summary() {
  local now=$1
  local up=$((now - STARTED_AT))
  ((up > 0)) || up=1
  local role line=""
  {
    printf 'mode=%s uptime_s=%d sweeps=%d\n' "$MODE" "$up" "$SWEEPS"
    printf 'h=%s h_min=%s h_max=%s pressure=%s\n' \
      "$(fmt_gib "$M_H")" "$(fmt_gib "$H_MIN_SEEN")" "$(fmt_gib "$H_MAX_SEEN")" "$PRESSURE"
    printf 'policed=%d over_budget=%d sessions=%d tree=%d\n' \
      "${POLICED_N:-0}" "${OVER_N:-0}" "${#CLAUDE_ROOTS[@]}" "${#SERVER_TREE[@]}"
    for role in "${!BUDGET[@]}"; do
      line+="${role}=$((${BUDGET[$role]} / MIB))M"
      [[ -n ${DISARMED[$role]:-} ]] && line+="(disarmed)"
      line+=" "
    done
    printf 'budgets %s\n' "$line"
    line=""
    for role in "${!KILLS[@]}"; do line+="${role}:${KILLS[$role]} "; done
    printf 'kills total=%d by_role=%s last=%s\n' \
      "$KILLS_TOTAL" "${line:-none}" "${LAST_KILL_AT:-0}"
    # Per day rather than per hour: the operator's question is "not every
    # fifteen minutes", and an hourly rate over a short uptime reads as a huge
    # number for one event.
    printf 'kill_rate_per_day=%d.%02d\n' \
      "$((KILLS_TOTAL * 86400 / up))" "$((KILLS_TOTAL * 86400 * 100 / up % 100))"
    printf 'dwell_s=%d min_age_s=%d loop_window_s=%d loop_kills=%d pss=%s\n' \
      "$DWELL_SECONDS" "$MIN_AGE" "$LOOP_WINDOW" "$LOOP_KILLS" \
      "$((PSS_UNAVAILABLE ? 0 : 1))"
  } >"${STATE_DIR}/summary.tmp" &&
    mv -f "${STATE_DIR}/summary.tmp" "${STATE_DIR}/summary"
  return 0
}

# --------------------------------------------------------------------------- #
# lifecycle
# --------------------------------------------------------------------------- #

# A coder_script re-runs when the agent restarts without the pod restarting, so
# two watchdogs are otherwise entirely possible.
#
# Liveness decides, not the existence of a file. The previous version treated a
# failed O_EXCL create as evidence that another watchdog held the lock, and only
# then looked at whether the recorded pid was alive. That inverts the reliable
# test and the unreliable one, and it failed in exactly the situation this daemon
# exists for: the pod was OOM-killed, the watchdog died by SIGKILL without
# running its EXIT trap, and the pidfile survived on the NFS-backed home
# directory. Every restart afterwards logged "another instance is already
# running" and exited - observed on the test workspace, not theorised.
acquire_singleton() {
  local pidfile="${STATE_DIR}/watchdog.pid"
  local self="${BASH_SOURCE[0]}"
  local other="" a
  local -a argv=()

  if [[ -s $pidfile ]]; then
    read -r other <"$pidfile" 2>/dev/null
    if [[ $other =~ ^[0-9]+$ ]] && ((other != $$)) &&
      [[ -r ${PROC_DIR}/${other}/cmdline ]]; then
      mapfile -d '' -t argv <"${PROC_DIR}/${other}/cmdline" 2>/dev/null
      for a in "${argv[@]}"; do
        [[ $a == "$self" ]] && return 1
      done
    fi
  fi

  printf '%s\n' "$$" >"$pidfile" 2>/dev/null || return 1
  # Two watchdogs started at the same instant would both get this far. Settle it
  # by reading back who actually owns the file rather than by trusting the write.
  /usr/bin/sleep 1
  read -r other <"$pidfile" 2>/dev/null
  [[ $other == "$$" ]]
}

release_singleton() {
  local pidfile="${STATE_DIR}/watchdog.pid" owner=""
  # Both traps can fire, so the second one finds no file. A redirection that
  # fails is reported by the shell before `2>/dev/null` on the same command has
  # taken effect, so the test is done here rather than swallowed there.
  [[ -r $pidfile ]] || return 0
  read -r owner <"$pidfile" 2>/dev/null
  # Never remove a pidfile another instance owns - that would hand the lock to a
  # third one while the second is still running.
  [[ $owner == "$$" ]] && rm -f "$pidfile"
  return 0
}

# Returns 2 when the cgroup has no memory limit and there is nothing to measure
# against.
cycle_once() {
  local now=$1 rc

  read_cgroup_memory
  rc=$?
  if ((rc == 2)); then
    log_action "memory.max is unlimited - nothing to budget against, exiting"
    return 2
  fi
  ((rc == 0)) || return 1

  if ((${#BUDGET[@]} == 0)); then
    derive_budgets "$M_MAX"
    local role
    for role in extensionHost serverMain tsserver languageServer fileWatcher extensionHelper claudeHelper; do
      log_action "budget role=${role} pss=$(fmt_mib "${BUDGET[$role]}") (pod share $(fmt_mib "$((M_MAX / POD_SHARE_DEN))"), resting reference $(fmt_mib "${RESTING_ROLE[$role]:-0}"))"
    done
    log_action "armed roles: $(
      for role in "${!BUDGET[@]}"; do role_is_armed "$role" && printf '%s ' "$role"; done
      printf '(mode=%s)' "$MODE"
    )"
  fi

  read_cgroup_pressure
  ((M_H > H_MAX_SEEN)) && H_MAX_SEEN=$M_H
  ((H_MIN_SEEN == 0 || M_H < H_MIN_SEEN)) && H_MIN_SEEN=$M_H

  local dt=$((now - PREV_AT))
  ((dt > 0)) || dt=1
  local refault_rate=0 pgscan_rate=0 du_rate=0
  if ((PREV_AT > 0)); then
    refault_rate=$(((M_REFAULT_FILE - PREV_REFAULT) / dt))
    pgscan_rate=$(((M_PGSCAN_DIRECT - PREV_PGSCAN) / dt))
    du_rate=$(((M_U - PREV_U) / dt))
  fi

  append_calibration "${now},${M_MAX},${M_CURRENT},${M_U},${M_H},${M_ANON},${M_SHMEM},${M_UNEVICTABLE},${M_SLAB_UNRECLAIMABLE},${M_SLAB_RECLAIMABLE},${M_KERNEL_STACK},${M_PAGETABLES},${M_SEC_PAGETABLES},${M_PERCPU},${M_SOCK},${M_FILE},${M_PSI_CENTI},${refault_rate},${pgscan_rate},${PRESSURE},${du_rate}"
  publish_headroom "$M_H" "$PRESSURE"

  if ((CYCLE % SWEEP_EVERY == 0)); then
    sweep_once "$now"
    ((SWEEPS += 1))
    check_visibility
    publish_summary "$now"
  fi

  PREV_AT=$now
  PREV_U=$M_U
  PREV_REFAULT=$M_REFAULT_FILE
  PREV_PGSCAN=$M_PGSCAN_DIRECT
  return 0
}

# Rotation counts lines written by *this* process, so a daemon that restarts
# every few hours would append to a file it believes is empty and the cap would
# never be reached. One fork each at startup fixes that; there is no way to ask
# bash for a file's size.
count_lines() {
  local n=0
  [[ -r $1 ]] || {
    printf '0'
    return 0
  }
  n=$(/usr/bin/wc -l <"$1" 2>/dev/null)
  printf '%s' "${n:-0}"
}

main() {
  mkdir -p "$STATE_DIR" || exit 1
  LOG_LINES=$(count_lines "${STATE_DIR}/actions.log")
  CSV_LINES=$(count_lines "${STATE_DIR}/calibration.csv")
  SWEEP_LINES=$(count_lines "${STATE_DIR}/sweep.log")

  case "$MODE" in
  observe | enforce | enforce-all) ;;
  *)
    MODE=observe
    ;;
  esac

  if ! acquire_singleton; then
    printf 'memory-watchdog: another instance is already running\n' >&2
    exit 0
  fi
  trap 'release_singleton; exit 0' HUP INT TERM
  trap release_singleton EXIT

  local now
  STARTED_AT=${WATCHDOG_NOW:-$EPOCHSECONDS}
  log_action "started mode=${MODE} pid=$$ cgroup=${CGROUP_DIR} sweep_every=$((SAMPLE_INTERVAL * SWEEP_EVERY))s dwell=${DWELL_SECONDS}s"

  while :; do
    now=${WATCHDOG_NOW:-$EPOCHSECONDS}
    cycle_once "$now"
    (($? == 2)) && break
    ((CYCLE += 1))

    [[ $ONESHOT == "1" ]] && break
    /usr/bin/sleep "$SAMPLE_INTERVAL"
  done
  return 0
}

# Sourcing with WATCHDOG_SOURCE_ONLY=1 exposes the functions to the test harness
# without starting the loop.
if [[ ${WATCHDOG_SOURCE_ONLY:-0} != "1" ]]; then
  main "$@"
fi
