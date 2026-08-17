#!/bin/bash
#
# Memory watchdog for the workspace pod.
#
# Why this exists: the pod's cgroup has memory.oom.group=1, so a cgroup OOM kills
# every process in the container together - the IDE, every tmux session and every
# long-running agent. /sys/fs/cgroup is mounted read-only with an empty
# cgroup.subtree_control under a private cgroup namespace, and the workspace runs
# as uid 10001 with no capabilities, so neither memory.high nor a child cgroup is
# reachable without privileged:true. See DESIGN.md. The only remaining strategy
# is to never reach memory.max, which is what this does from userspace.
#
# Dependencies are deliberately tiny: bash 4.4+, /proc, /sys/fs/cgroup,
# /usr/bin/sleep, coreutils mv/rm/mkdir, and - in enforce mode only -
# /usr/bin/prlimit. Measurement and process enumeration use bash builtins, so a
# scan forks nothing at all; at a 2-second interval under pressure that matters.
#
# awk, flock, python3, ps and pgrep do all exist in the base image - an earlier
# version of this comment claimed otherwise and was wrong. Not using them is a
# choice (no forks per scan, one language to review), not a constraint. The one
# real constraint is that the operator's PATH is shadowed by brew, so anything
# invoked here is called by absolute /usr/bin/... path and never by name.
#
# Modes:
#   observe (default) - measure, publish headroom, log what it *would* have done.
#                       Sets no limits and sends no signals.
#   enforce           - additionally refresh RLIMIT_DATA ceilings and shed load.
#
# Test seams, exercised by script-memory-watchdog-test.sh:
#   WATCHDOG_CGROUP_DIR  WATCHDOG_PROC_DIR  WATCHDOG_STATE_DIR
#   WATCHDOG_MODE  WATCHDOG_ONESHOT  WATCHDOG_NOW  WATCHDOG_SOURCE_ONLY
#
# Deliberately NOT using `set -e`: this is a supervisor with no supervisor of its
# own. A read that fails because a /proc entry vanished mid-scan must skip that
# entry, not take the watchdog down and leave the pod unprotected.
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
PAGE_SIZE=4096

# Sampling. The interval shortens under pressure so the ladder can outrun a
# process that allocates a gigabyte in a few seconds.
INTERVAL_IDLE="${WATCHDOG_INTERVAL_IDLE:-10}"
INTERVAL_BUSY="${WATCHDOG_INTERVAL_BUSY:-2}"
CALIBRATION_EVERY="${WATCHDOG_CALIBRATION_EVERY:-6}" # cycles between CSV rows

# Tier thresholds, in absolute bytes of headroom H, derived from the pod's own
# memory.max by derive_limits() below. Set any of these in the environment to
# override the derivation entirely; empty means "derive it".
T_L1="${WATCHDOG_T_L1:-}"
T_L2="${WATCHDOG_T_L2:-}"
T_L3="${WATCHDOG_T_L3:-}"
T_L4="${WATCHDOG_T_L4:-}"

# The one number the ladder is derived from: the critical reserve C, the amount
# of headroom below which the next allocation burst can reach memory.max before
# the next sample can react. T_L4 is C, and the rungs above it are fixed
# multiples of it.
#
# Why this is a clamped fraction rather than an absolute constant, having been an
# absolute constant first. The original argument for absolute bytes was that the
# page cache a workload needs for forward progress is a property of the workload,
# not of the container's limit - and that is true, but it only settles what the
# thresholds *mean*, not what values are available. Headroom is bounded above by
# memory.max, so on a pod small enough that the fixed floor exceeds the range the
# pod ever has, an absolute ladder does not become conservative, it becomes
# permanently tripped and therefore inert: the 4 GiB workspace rests at H = 3.4
# GiB against a 3.0 GiB L1, which is one editor window away from sitting at L1
# for the rest of the pod's life. So the fraction scales the ladder to the pod,
# while:
#
#   - the FLOOR expresses reaction time, which really is size-independent. It is
#     what the sample interval times a plausible allocation rate costs, and no
#     pod is too small to need it.
#   - the CAP stops a percentage from scaling into absurdity on a large pod,
#     which was the correct half of the original objection: a fraction that gave
#     16 GiB a 4 GiB "critical" reserve would shed with plenty of genuine
#     headroom left.
#
# At 8 GiB this reproduces the hand-tuned ladder it replaces (0.80/1.20/2.00/3.20
# against 0.75/1.25/2.00/3.00), which is the only calibration point that ever
# existed; at 4 GiB it gives 0.41/0.61/1.02/1.64, leaving the measured 3.4 GiB
# resting headroom two thirds of the pod clear of the first rung.
C_FRACTION_NUM="${WATCHDOG_C_NUM:-1}"
C_FRACTION_DEN="${WATCHDOG_C_DEN:-10}"
C_FLOOR="${WATCHDOG_C_FLOOR:-402653184}" # 384 MiB
C_CAP="${WATCHDOG_C_CAP:-1073741824}"    # 1.00 GiB

# Corroboration is required at L2 only. At L2 we are "at the limit"; PSI and the
# refault rate are what separate "at the limit and fine" - the normal resting
# state of this pod - from "at the limit and dying". By L3/L4 there is no time
# left to wait for a second opinion.
T_PSI_CENTI="${WATCHDOG_T_PSI_CENTI:-1000}" # memory.pressure full avg10 >= 10.00
T_REFAULT_RATE="${WATCHDOG_T_REFAULT_RATE:-20000}"

DEBOUNCE_L1="${WATCHDOG_DEBOUNCE_L1:-3}"
DEBOUNCE_L2="${WATCHDOG_DEBOUNCE_L2:-3}"
DEBOUNCE_L3="${WATCHDOG_DEBOUNCE_L3:-2}"
PROJECTION_HORIZON="${WATCHDOG_PROJECTION_HORIZON:-60}" # seconds

# How rarely it acts is part of what "working" means here, not a refinement of
# it. Shedding the editor is the right trade against an oom.group kill that takes
# every tmux session and every agent with it - but an editor that dies every
# fifteen minutes gets the watchdog switched off, and a watchdog that is switched
# off protects nothing. So the ladder is rate-limited by construction rather than
# by a timer alone:
#
#   - SETTLE is the minimum gap between any two actions. It exists so the ladder
#     can see the effect of a kill before deciding it was not enough. It does NOT
#     hold back a higher rung indefinitely, which the fixed 180s cooldown it
#     replaces did: that cooldown demoted L3 to L1 for three minutes after an L2
#     shed, so a fast-growing extension host could not be stopped during exactly
#     the window when it most needed stopping.
#
#   - Each rung then fires at most once per excursion, and an excursion only ends
#     when headroom recovers above L1. Escalation is unaffected - L2, then L3,
#     then L4 all remain available as things get worse - but a pod that is simply
#     too small for its workload sheds one helper and one extension host and then
#     stops, instead of shedding one every SETTLE seconds forever. If that is not
#     enough, the answer is a bigger pod, and repeatedly killing the editor is a
#     worse way of finding that out than the log line that says so.
SETTLE="${WATCHDOG_SETTLE:-30}"

# A shed has to be worth its disruption. Killing a 40 MiB file watcher frees
# nothing, restarts a component the operator can notice, and burns the rung that
# would otherwise have been available later in the same excursion.
MIN_SHED_RSS="${WATCHDOG_MIN_SHED_RSS:-134217728}" # 128 MiB

# Soft RLIMIT_DATA ceilings by role, as sixteenths of memory.max. Hard limits are
# never touched, so an inheriting shell restores itself with `ulimit -d
# unlimited`.
#
# These scale for the same reason the ladder does, and it matters more here: a
# 3 GiB extension-host ceiling on a 4 GiB pod is not conservative, it is inert -
# the pod dies first. The numerators are the hand-picked 8 GiB values expressed
# against that pod's limit (1.5, 3.0, 3.5, 1.0, 1.0 GiB), so an 8 GiB workspace
# gets exactly the ceilings that were reasoned about, and every other size gets
# the same shape.
#
# The floor is what keeps the scaling from turning into a different failure: a
# ceiling below what a role legitimately needs makes it die doing ordinary work,
# which is worse than no ceiling because it is constant rather than occasional.
# The cap keeps a large pod from being handed a ceiling so high that nothing
# could ever reach it.
#
# Every role here is a V8 process, and that is what makes a ceiling a reasonable
# thing to set: hitting it makes mmap return ENOMEM, V8 raises its own fatal heap
# OOM, and the editor offers "Restart Extension Host" or silently respawns the
# language server. `extensionHelper` is deliberately absent - see role_of().
declare -gA CEILING_SIXTEENTHS=(
  [serverMain]=3
  [extensionHost]=6
  [tsserver]=7
  [languageServer]=2
  [fileWatcher]=2
)
CEILING_FLOOR="${WATCHDOG_CEILING_FLOOR:-536870912}" # 512 MiB
CEILING_CAP="${WATCHDOG_CEILING_CAP:-4294967296}"    # 4.00 GiB

# Filled by derive_limits(). A role may also be pinned outright from the
# environment - WATCHDOG_CEILING_extensionHost=... - which is how the live
# demonstration forces a ceiling to bite without editing the script.
declare -gA CEILING=()

# Roles L2 is allowed to shed. Each is restarted transparently or on demand by
# the editor, and none of them holds unsaved user state.
L2_ROLES=" tsserver languageServer fileWatcher extensionHelper "

MAX_LOG_LINES="${WATCHDOG_MAX_LOG_LINES:-20000}"
MAX_CSV_LINES="${WATCHDOG_MAX_CSV_LINES:-50000}"

# Scan state. Declared at file scope, not inside main(), so that sourcing the
# script with WATCHDOG_SOURCE_ONLY=1 gives the test harness correctly-typed
# globals without having to restate them.
declare -gA P_COMM=() P_CMD=() P_ARGV0=() P_PPID=() P_RSS=() CHILDREN=()
declare -gA SERVER_TREE=() PROTECTED=() PROTECT_REASON=() WATCHDOG_KIN=()
declare -ga PIDS=() CANDIDATES=() SERVER_ROOTS=()
SERVER_PID=""
TIER=L0
ROLE=other
GUARD=""
PREV_TIER=L0
PREV_AT=0
PREV_U=0
PREV_REFAULT=0
PREV_PGSCAN=0
CYCLE=0
H_MAX_SEEN=0
H_MIN_SEEN=0
CALIBRATION_WARNED=0
C_RESERVE=0
TOO_SMALL=0
M_MAX=0
STARTED_AT=${WATCHDOG_NOW:-$EPOCHSECONDS}

# How often each rung has acted since the watchdog started, and when it last did.
# Published in the summary file every cycle - in observe mode too, where it is
# the count of sheds enforce mode *would* have performed. That number is what
# says whether enforce mode is tolerable on a live workspace, and it can be had
# without ever signalling anything.
declare -gA ACTIONS=([L2]=0 [L3]=0 [L4]=0)
declare -gA RUNG_FIRED=()
EXCURSIONS=0
IN_EXCURSION=0

# --------------------------------------------------------------------------- #
# derivation - one pure function of memory.max; no state, no I/O
# --------------------------------------------------------------------------- #

clamp() {
  local v=$1 lo=$2 hi=$3
  ((v < lo)) && v=$lo
  ((v > hi)) && v=$hi
  printf '%s' "$v"
}

# Sets T_L1..T_L4 and CEILING from memory.max. Anything already set from the
# environment is left alone, so a single role or a single rung can be pinned for
# an experiment without replacing the derivation.
derive_limits() {
  local max=$1 role c

  c=$(clamp $((max * C_FRACTION_NUM / C_FRACTION_DEN)) "$C_FLOOR" "$C_CAP")
  C_RESERVE=$c
  : "${T_L4:=$c}"
  : "${T_L3:=$((c * 3 / 2))}"
  : "${T_L2:=$((c * 5 / 2))}"
  : "${T_L1:=$((c * 4))}"

  # Inversion: what pod size makes this formula harmful rather than imprecise?
  # A small enough one. The floor is a reaction-time budget and cannot shrink
  # with the pod, so below roughly 3 GiB the top of the ladder approaches
  # memory.max and the pod is inside the shedding tiers from the moment it boots
  # - which would mean killing the editor continuously, the one outcome that
  # reliably gets a watchdog switched off for good. There is no threshold that
  # fixes this, because the pod genuinely has no runway; the honest response is
  # to say so and refuse to act. The workspace offers 4 and 8 GiB, both of which
  # clear this comfortably, so this is a guard against a future option rather
  # than a live case.
  TOO_SMALL=0
  ((T_L1 * 2 > max)) && TOO_SMALL=1

  local var
  for role in "${!CEILING_SIXTEENTHS[@]}"; do
    # An explicit WATCHDOG_CEILING_<role> wins over the derivation.
    var="WATCHDOG_CEILING_${role}"
    if [[ -n ${!var:-} ]]; then
      CEILING[$role]=${!var}
      continue
    fi
    CEILING[$role]=$(clamp \
      $((max * CEILING_SIXTEENTHS[$role] / 16)) "$CEILING_FLOOR" "$CEILING_CAP")
  done
  return 0
}

# --------------------------------------------------------------------------- #
# measurement - reads only, sets M_*/P_* globals, decides nothing
# --------------------------------------------------------------------------- #

# Unreclaimable memory U. With memory.swap.max=0, all anon is unreclaimable.
#
# The `kernel` roll-up in memory.stat must NOT be used: it is dominated by
# slab_reclaimable (dentry/inode cache - 1.6 GiB on the real pod), which the
# kernel hands back under pressure. Counting it makes an idle container look like
# it is about to die. memory.current has the same defect plus the page cache,
# which is why it reads 97% here while U is 23%.
#
# Returns 0 on success, 1 on read failure, 2 if the cgroup has no memory limit.
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

# Fills PIDS / P_COMM / P_CMD / CHILDREN for one scan.
read_process_table() {
  PIDS=()
  P_COMM=()
  P_CMD=()
  P_ARGV0=()
  P_PPID=()
  P_RSS=()
  CHILDREN=()

  local entry pid line rest comm ppid
  local -a argv

  for entry in "${PROC_DIR}"/[0-9]*; do
    pid=${entry##*/}
    read -r line <"$entry/stat" 2>/dev/null || continue

    # /proc/<pid>/stat is "pid (comm) state ppid ...", and comm may contain
    # spaces and parentheses, so split on the *last* ") " rather than tokenise.
    rest=${line##*') '}
    [[ $rest == "$line" ]] && continue
    comm=${line#*'('}
    comm=${comm%%') '*}
    rest=${rest#* } # drop state
    ppid=${rest%% *}
    [[ $ppid =~ ^[0-9]+$ ]] || continue

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
    CHILDREN[$ppid]+=" $pid"
  done
  return 0
}

read_rss() {
  local pid res
  for pid in "$@"; do
    read -r _ res _ <"${PROC_DIR}/${pid}/statm" 2>/dev/null || continue
    P_RSS[$pid]=$((res * PAGE_SIZE))
  done
  return 0
}

# --------------------------------------------------------------------------- #
# selection - pure over the tables above; produces sets, takes no action
# --------------------------------------------------------------------------- #

# Fills SERVER_ROOTS with every remote-server entrypoint, and sets SERVER_PID to
# the first of them (used only for logging and the calibration CSV).
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
#  - there can be more than one. `--reconnection-grace-time 28800` keeps a
#    disconnected server alive for eight hours, and a window on a different commit
#    gets its own server. Electing one and scoping to it would leave the other
#    tree not merely unmanaged but unprotected, because the ptyHost excision only
#    runs inside the tree that was discovered. So every root counts and the
#    managed tree is the union of their subtrees.
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
  SERVER_PID=${SERVER_ROOTS[0]}
  return 0
}

# Sets SERVER_TREE to the union of every root's descendants, and reads their RSS.
# Returns 1 when no server is running, leaving SERVER_TREE empty.
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
  read_rss "${!SERVER_TREE[@]}"
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
# inside the tree", and it is the primary safety rule of the whole watchdog.
#
# A fully provisioned workspace has two unrelated node installations: VS Code's
# bundled one at ~/.vscode-server/cli/servers/Stable-<commit>/server/node, which
# arrives with the server download, and mise's on PATH, which is what the
# operator's repo tooling and Claude Code sessions run on. There is no
# /usr/bin/node and no node on PATH at all without dotfiles. Every process VS
# Code spawns - server-main.js, every bootstrap-fork, every node language server,
# and native helpers like terraform-ls - runs a binary under ~/.vscode-server;
# nothing the operator runs does.
#
# So keying detection on "is this node" by comm, by basename, or by a loose
# cmdline match would make an agent session indistinguishable from an editor
# helper, and the watchdog would stamp RLIMIT_DATA on it and shed it at L2/L3 -
# the exact outcome this design exists to prevent, arriving one layer earlier
# than the action rules that are meant to prevent it. Path, and only path.
is_vscode_binary() {
  [[ ${P_ARGV0[$1]:-} == *"/.vscode-server/"* ]]
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
# the program and does not match. The cost of being wrong is asymmetric but not
# free in either direction - over-matching protects something that could have
# been shed, which quietly turns the mechanism off, and that is exactly how the
# harness bug hid.
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
#
# Tree membership is NOT a safe kill criterion: tmux sessions and long-running
# agents started from a VS Code integrated terminal are descendants of the server
# tree via ptyHost. The rules below are ordered cheapest and most certain first;
# each of them is asserted, and asserted to be individually reachable, by
# script-memory-watchdog-test.sh.
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
# descendants. PROTECT_REASON records which rule claimed each pid, which is what
# makes an over-broad guard visible instead of silently inert.
compute_protected() {
  PROTECTED=()
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

  # Everything in the tree that is not running a VS Code binary, whatever its
  # position in it. A Claude Code session spawned by an extension is a child of
  # the extension host and not of ptyHost, so neither the subtree excision nor
  # tree membership would save it; its executable path does.
  for pid in "${!SERVER_TREE[@]}"; do
    if ! is_vscode_binary "$pid"; then
      PROTECTED[$pid]=1
      PROTECT_REASON[$pid]=${PROTECT_REASON[$pid]:-foreign-binary}
    fi
  done

  for pid in "${!SERVER_TREE[@]}"; do
    if [[ ${P_CMD[$pid]:-} == *"--type=ptyHost"* ]]; then
      subtree_of "$pid" pty
      for p in "${!pty[@]}"; do
        PROTECTED[$p]=1
        PROTECT_REASON[$p]=${PROTECT_REASON[$p]:-ptyhost}
      done
    fi
  done
  return 0
}

# Sets ROLE.
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
    # never on the joined command line: a Claude Code session launched by an
    # extension has the extension's directory all over its arguments while its
    # executable is mise's node, and matching the arguments would classify it as
    # a sheddable helper. Checked last, so a node language server - which also
    # lives under extensions/ but runs VS Code's own node - keeps its role above.
    #
    # It gets no RLIMIT_DATA ceiling, on purpose. The argument for a ceiling is
    # that V8 turns ENOMEM into its own fatal heap OOM and the editor offers a
    # restart; a Go or Rust runtime turns the same ENOMEM into an abrupt abort
    # with no editor-side affordance, and there is no measured relationship
    # between its working set and a number we could pick. It is still restartable
    # and holds no unsaved state, so it is shed at L2 - a corroborated, debounced
    # decision to kill a helper - rather than pre-emptively capped on a guess.
    if [[ $argv0 == *"/.vscode-server/extensions/"* ]]; then
      ROLE=extensionHelper
    else
      ROLE=other
    fi
    ;;
  esac
  return 0
}

# Fills CANDIDATES with "<rss> <pid> <role>" rows the given tier may signal,
# heaviest resident set first.
select_candidates() {
  local tier=$1
  local pid i bi
  local -a sorted=()
  CANDIDATES=()

  for pid in "${!SERVER_TREE[@]}"; do
    [[ -n ${PROTECTED[$pid]:-} ]] && continue
    role_of "$pid"
    [[ $ROLE == "ptyHost" ]] && continue
    case "$tier" in
    L2) [[ $L2_ROLES == *" $ROLE "* ]] || continue ;;
    L3) [[ $ROLE == "extensionHost" ]] || continue ;;
    L4) ;;
    *) continue ;;
    esac
    CANDIDATES+=("${P_RSS[$pid]:-0} $pid $ROLE")
  done

  # Selection sort. The server tree is a few dozen processes at most, and this
  # avoids a fork to sort(1) on every cycle.
  while ((${#CANDIDATES[@]})); do
    bi=0
    for ((i = 1; i < ${#CANDIDATES[@]}; i++)); do
      [[ ${CANDIDATES[i]%% *} -gt ${CANDIDATES[bi]%% *} ]] && bi=$i
    done
    sorted+=("${CANDIDATES[bi]}")
    unset 'CANDIDATES[bi]'
    CANDIDATES=("${CANDIDATES[@]}")
  done
  CANDIDATES=("${sorted[@]}")
  return 0
}

# --------------------------------------------------------------------------- #
# decision - a function of the numbers and the debounce counters only
# --------------------------------------------------------------------------- #

C_L1=0
C_L2=0
C_L3=0
LAST_ACTION_AT=0
SUPPRESSED=""

# Sets TIER. Called in the current shell, never in a command substitution - the
# debounce counters are state and a subshell would silently discard them.
#
# SUPPRESSED records why an acting tier was demoted, so that "the ladder reached
# L3 and nothing happened" is always accompanied by the reason. It is not
# decoration: the one class of bug this watchdog has repeatedly produced is a
# state that looks correct because the evidence of its being wrong is absent.
decide_tier() {
  local h=$1 psi=$2 refault=$3 proj=$4 now=$5
  local want
  SUPPRESSED=""

  if ((h < T_L1)); then ((C_L1 += 1)); else C_L1=0; fi
  if ((h < T_L2)); then ((C_L2 += 1)); else C_L2=0; fi
  if ((h < T_L3)); then ((C_L3 += 1)); else C_L3=0; fi

  # Excursion tracking. An excursion opens the first time headroom falls below
  # L1 and closes when it comes back above it; the rung-fired flags live for
  # exactly that long. Recovery is what re-arms the ladder, not the passage of
  # time, because time passing does not mean the pressure went away.
  if ((h < T_L1)); then
    if ((IN_EXCURSION == 0)); then
      IN_EXCURSION=1
      ((EXCURSIONS += 1))
      RUNG_FIRED=()
    fi
  elif ((IN_EXCURSION == 1)); then
    IN_EXCURSION=0
    RUNG_FIRED=()
  fi

  if ((h < T_L4)); then
    TIER=L4
    return 0
  fi

  want=L0
  if ((C_L3 >= DEBOUNCE_L3)); then
    want=L3
  elif ((C_L2 >= DEBOUNCE_L2)) &&
    { ((psi >= T_PSI_CENTI)) || ((refault >= T_REFAULT_RATE)); }; then
    want=L2
  elif ((C_L1 >= DEBOUNCE_L1)); then
    want=L1
  fi

  # Projection. Armed only once headroom is already below L1, so a momentary
  # allocation spike from an idle state cannot vault the ladder.
  if [[ $want != "L0" ]] && ((proj < T_L4)); then
    want=L3
  fi

  # Rate limiting, in two independent parts - see SETTLE above for why the
  # single 180s cooldown they replace was worse than either.
  if [[ $want == "L2" || $want == "L3" ]]; then
    if ((LAST_ACTION_AT > 0)) && ((now - LAST_ACTION_AT < SETTLE)); then
      SUPPRESSED="settling(${want})"
      want=L1
    elif [[ -n ${RUNG_FIRED[$want]:-} ]]; then
      SUPPRESSED="already-fired-this-excursion(${want})"
      want=L1
    fi
  fi

  TIER=$want
  return 0
}

# --------------------------------------------------------------------------- #
# action - the only place that writes state or signals anything
# --------------------------------------------------------------------------- #

LOG_LINES=0
CSV_LINES=0

log_action() {
  local msg="$*" stamp
  printf -v stamp '%(%Y-%m-%dT%H:%M:%S%z)T' -1
  [[ $MODE == "enforce" ]] || msg="[observe] ${msg}"
  printf '%s %s\n' "$stamp" "$msg" >>"${STATE_DIR}/actions.log"
  ((LOG_LINES += 1))
  if ((LOG_LINES > MAX_LOG_LINES)); then
    mv -f "${STATE_DIR}/actions.log" "${STATE_DIR}/actions.log.1" 2>/dev/null
    LOG_LINES=0
  fi
  return 0
}

# The projected-headroom term goes negative whenever dU/dt is steep enough to
# exhaust the cgroup inside the horizon - a normal reading, and the one the log
# most needs to be legible for. Bash division truncates toward zero, so both
# halves of a negative value come out negative and print as "-27.-79 GiB"; the
# sign is taken off the front and applied once.
fmt_gib() {
  local v=$1 sign=""
  if ((v < 0)); then
    sign="-"
    v=$((-v))
  fi
  printf '%s%d.%02d GiB' "$sign" "$((v / GIB))" "$((v % GIB * 100 / GIB))"
}

publish_headroom() {
  printf '%s free (%s)\n' "$(fmt_gib "$1")" "$2" >"${STATE_DIR}/headroom.tmp" &&
    mv -f "${STATE_DIR}/headroom.tmp" "${STATE_DIR}/headroom"
  return 0
}

# How many processes the current scan found, how many of them the guards claimed,
# and - the number that matters - how many remain eligible to be signalled at
# all. A managed tree with zero eligible processes is the signature of a guard
# that has swallowed everything, and it is worth more than any assertion about a
# particular pid because it does not depend on knowing which pid to ask about.
census_line() {
  local pid role protected=0 eligible=0 pty_n=0
  for pid in "${!SERVER_TREE[@]}"; do
    if [[ -n ${PROTECTED[$pid]:-} ]]; then
      ((protected += 1))
      [[ ${PROTECT_REASON[$pid]:-} == "ptyhost" ]] && ((pty_n += 1))
      continue
    fi
    role_of "$pid"
    [[ $ROLE == "ptyHost" ]] && continue
    ((eligible += 1))
  done
  printf 'tree=%d protected=%d ptyhost=%d eligible=%d' \
    "${#SERVER_TREE[@]}" "$protected" "$pty_n" "$eligible"
}

# The question "would enforce mode have been tolerable to live with?" answered
# from observe mode, where it costs nothing to ask. Sheds per hour of uptime is
# the number that decides whether the operator turns this on and leaves it on -
# a watchdog that is switched off protects nothing, however correct each of its
# individual decisions was.
publish_summary() {
  local now=$1 h=$2 tier=$3
  local up=$((now - STARTED_AT))
  ((up > 0)) || up=1
  local total=$((${ACTIONS[L2]:-0} + ${ACTIONS[L3]:-0} + ${ACTIONS[L4]:-0}))
  {
    printf 'mode=%s uptime_s=%d tier=%s\n' "$MODE" "$up" "$tier"
    printf 'h=%s h_min=%s h_max=%s\n' \
      "$(fmt_gib "$h")" "$(fmt_gib "$H_MIN_SEEN")" "$(fmt_gib "$H_MAX_SEEN")"
    printf 'thresholds l1=%s l2=%s l3=%s l4=%s (reserve=%s of memory.max=%s)\n' \
      "$(fmt_gib "$T_L1")" "$(fmt_gib "$T_L2")" "$(fmt_gib "$T_L3")" \
      "$(fmt_gib "$T_L4")" "$(fmt_gib "$C_RESERVE")" "$(fmt_gib "$M_MAX")"
    printf 'excursions=%d sheds l2=%d l3=%d l4=%d total=%d\n' \
      "$EXCURSIONS" "${ACTIONS[L2]:-0}" "${ACTIONS[L3]:-0}" "${ACTIONS[L4]:-0}" "$total"
    # Per day rather than per hour: the operator's question is "not every 15
    # minutes", and an hourly rate computed over a few minutes of uptime reads
    # as a huge number for one event.
    printf 'shed_rate_per_day=%d.%02d\n' \
      "$((total * 86400 / up))" "$((total * 86400 * 100 / up % 100))"
    printf '%s\n' "$(census_line)"
  } >"${STATE_DIR}/summary.tmp" &&
    mv -f "${STATE_DIR}/summary.tmp" "${STATE_DIR}/summary"
  return 0
}

CSV_HEADER="ts,mem_max,mem_current,u,h,anon,shmem,unevictable,slab_unreclaimable,slab_reclaimable,kernel_stack,pagetables,sec_pagetables,percpu,sock,file,psi_full_avg10_centi,refault_file_per_s,pgscan_direct_per_s,tier,server_pid,tree_procs,tree_rss,protected,eligible,t_l1,t_l4"

append_calibration() {
  local csv="${STATE_DIR}/calibration.csv" first=""
  if [[ -s $csv ]]; then
    # A file written by an earlier version has fewer columns, and appending to it
    # would produce one CSV that is silently two different schemas. Rotate it.
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

# Proposals already written to the log, keyed by pid and value. In enforce mode a
# ceiling is set once and the process then fails the "needs lowering" test on
# every later cycle, so it is logged once. In observe mode nothing is ever set,
# so without this the same handful of lines is appended every cycle - which at a
# 10-second interval buries the tier transitions the log exists to record.
declare -gA CEILING_LOGGED=()

# Idempotent: reads the current soft limit and only lowers what is unlimited or
# above the ceiling. Runs every cycle regardless of tier, because this is the
# proactive mechanism and it must also cover processes spawned while the pod is
# already under pressure - not only while it is idle.
apply_ceilings() {
  local pid want cur
  local -a f
  for pid in "${!SERVER_TREE[@]}"; do
    role_of "$pid"
    [[ $ROLE == "ptyHost" ]] && continue
    [[ -n ${PROTECTED[$pid]:-} ]] && continue
    want=${CEILING[$ROLE]:-}
    [[ -n $want ]] || continue

    cur=""
    while read -r -a f; do
      [[ ${f[0]:-} == "Max" && ${f[1]:-} == "data" && ${f[2]:-} == "size" ]] || continue
      cur=${f[3]:-}
      break
    done <"${PROC_DIR}/${pid}/limits" 2>/dev/null
    [[ -n $cur ]] || continue
    if [[ $cur != "unlimited" ]]; then
      [[ $cur =~ ^[0-9]+$ ]] || continue
      ((cur <= want)) && continue
    fi

    if [[ $MODE == "enforce" ]]; then
      /usr/bin/prlimit --pid "$pid" --data="${want}:" 2>/dev/null || continue
    fi
    [[ -n ${CEILING_LOGGED[${pid}:${want}]:-} ]] && continue
    CEILING_LOGGED[${pid}:${want}]=1
    log_action "ceiling pid=${pid} role=${ROLE} rlimit_data=${want} was=${cur}"
  done
  # Pids are recycled, so the memo has to be pruned or it grows without bound and
  # eventually suppresses a proposal for a genuinely new process.
  if ((${#CEILING_LOGGED[@]} > 512)); then
    CEILING_LOGGED=()
  fi
  return 0
}

signal_pid() {
  local sig=$1 pid=$2 why=$3
  # Second, independent guard. Selection already excluded these; this exists so
  # that a defect in tree-walking still cannot reach a protected process.
  if [[ -n ${PROTECTED[$pid]:-} ]] || is_never_signal "$pid"; then
    log_action "REFUSED sig=${sig} pid=${pid} reason=protected (${why})"
    return 1
  fi
  [[ $MODE == "enforce" ]] && kill "-${sig}" "$pid" 2>/dev/null
  role_of "$pid"
  log_action "signal sig=${sig} pid=${pid} rss=${P_RSS[$pid]:-0} role=${ROLE} (${why})"
  return 0
}

shed_load() {
  local tier=$1 now=$2
  local row rss pid role acted=0
  local -a targets=()

  select_candidates "$tier"

  # An acting tier that signals nothing is the exact shape of the bug that hid a
  # broken guard through two clean-looking test runs: enforce mode logged
  # tier=L3 with no signal and no REFUSED line, a state the code is otherwise
  # supposed to make impossible. It is now impossible for a different reason -
  # every path out of here says something.
  if ((${#CANDIDATES[@]} == 0)); then
    log_action "no-candidates tier=${tier} $(census_line)"
    return 0
  fi

  for row in "${CANDIDATES[@]}"; do
    rss=${row%% *}
    pid=${row#* }
    role=${pid#* }
    pid=${pid%% *}
    # Below L4, a shed has to pay for itself. Killing something small does not
    # move headroom, and it spends the rung as surely as killing something big
    # would - see MIN_SHED_RSS. At L4 the tree is going down regardless.
    if [[ $tier != "L4" ]] && ((rss < MIN_SHED_RSS)); then
      log_action "no-worthwhile-candidate tier=${tier} best=${pid} role=${role} rss=${rss} min=${MIN_SHED_RSS}"
      break
    fi
    if signal_pid TERM "$pid" "${tier} ${role} rss=${rss}"; then
      acted=1
      targets+=("$pid")
      [[ $tier == "L4" ]] || break
    fi
  done

  # L4 only: give the tree two seconds to exit, then SIGKILL whatever of it is
  # still there. Re-verify identity from /proc rather than trusting the tables
  # captured before the SIGTERM, because a pid can be recycled in between.
  if [[ $tier == "L4" ]] && ((acted)); then
    /usr/bin/sleep 2
    local -a argv
    for pid in "${targets[@]}"; do
      [[ -r ${PROC_DIR}/${pid}/cmdline ]] || continue
      argv=()
      mapfile -d '' -t argv <"${PROC_DIR}/${pid}/cmdline" 2>/dev/null
      [[ "${argv[*]}" == *"/.vscode-server/"* ]] || continue
      signal_pid KILL "$pid" "L4 escalation"
    done
  fi

  if ((acted)); then
    LAST_ACTION_AT=$now
    RUNG_FIRED[$tier]=1
    ACTIONS[$tier]=$((${ACTIONS[$tier]:-0} + 1))
  fi
  return 0
}

# --------------------------------------------------------------------------- #
# lifecycle
# --------------------------------------------------------------------------- #

# A coder_script re-runs when the agent restarts without the pod restarting, so
# two watchdogs are otherwise entirely possible. `set -o noclobber` gives an
# atomic O_EXCL create, which is all that is needed here: /usr/bin/flock does
# exist in the image, but it would only add a fork and a held descriptor to get
# the same guarantee.
acquire_singleton() {
  local pidfile="${STATE_DIR}/watchdog.pid"
  local other=""
  local -a argv=()

  if (
    set -o noclobber
    printf '%s\n' "$$" >"$pidfile"
  ) 2>/dev/null; then
    return 0
  fi

  read -r other <"$pidfile" 2>/dev/null
  if [[ $other =~ ^[0-9]+$ ]] && [[ -r ${PROC_DIR}/${other}/cmdline ]]; then
    mapfile -d '' -t argv <"${PROC_DIR}/${other}/cmdline" 2>/dev/null
    [[ "${argv[*]}" == *memory-watchdog* ]] && return 1
  fi

  rm -f "$pidfile"
  (
    set -o noclobber
    printf '%s\n' "$$" >"$pidfile"
  ) 2>/dev/null
}

release_singleton() {
  rm -f "${STATE_DIR}/watchdog.pid"
}

# Returns 2 when the cgroup has no memory limit and there is nothing to protect.
scan_once() {
  local now=$1 rc

  read_cgroup_memory
  rc=$?
  if ((rc == 2)); then
    log_action "memory.max is unlimited - nothing to protect, exiting"
    return 2
  fi
  ((rc == 0)) || return 1
  # Derived once, from the pod's own limit, on the first successful read.
  if [[ -z $T_L4 ]]; then
    derive_limits "$M_MAX"
    log_action "derived memory.max=$(fmt_gib "$M_MAX") reserve=$(fmt_gib "$C_RESERVE") ladder L1=$(fmt_gib "$T_L1") L2=$(fmt_gib "$T_L2") L3=$(fmt_gib "$T_L3") L4=$(fmt_gib "$T_L4")"
    local r
    for r in serverMain extensionHost tsserver languageServer fileWatcher; do
      log_action "derived ceiling role=${r} rlimit_data=$(fmt_gib "${CEILING[$r]}")"
    done
    if ((TOO_SMALL)) && [[ $MODE == "enforce" ]]; then
      MODE=observe
      log_action "WARNING memory.max=$(fmt_gib "$M_MAX") leaves no room above L1=$(fmt_gib "$T_L1"); a pod this size would sit in the shedding tiers permanently, so enforce mode is refused and this run is observe-only"
    fi
  fi
  read_cgroup_pressure
  read_process_table

  ((M_H > H_MAX_SEEN)) && H_MAX_SEEN=$M_H
  ((H_MIN_SEEN == 0 || M_H < H_MIN_SEEN)) && H_MIN_SEEN=$M_H

  # Rates. Elapsed time is tracked explicitly because the sample interval is
  # adaptive, so a fixed denominator would be wrong exactly when it matters.
  local dt=$((now - PREV_AT))
  ((dt > 0)) || dt=1
  local refault_rate=0 pgscan_rate=0 du_rate=0
  if ((PREV_AT > 0)); then
    refault_rate=$(((M_REFAULT_FILE - PREV_REFAULT) / dt))
    pgscan_rate=$(((M_PGSCAN_DIRECT - PREV_PGSCAN) / dt))
    du_rate=$(((M_U - PREV_U) / dt))
  fi
  local projected=$((M_H - du_rate * PROJECTION_HORIZON))

  build_server_tree
  compute_protected

  decide_tier "$M_H" "$M_PSI_CENTI" "$refault_rate" "$projected" "$now"
  publish_headroom "$M_H" "$TIER"

  local tree_rss=0 pid
  for pid in "${!SERVER_TREE[@]}"; do
    tree_rss=$((tree_rss + ${P_RSS[$pid]:-0}))
  done

  local census
  census="$(census_line)"
  local n_protected=${census#*protected=}
  n_protected=${n_protected%% *}
  local n_eligible=${census##*eligible=}

  if ((CYCLE % CALIBRATION_EVERY == 0)); then
    append_calibration "${now},${M_MAX},${M_CURRENT},${M_U},${M_H},${M_ANON},${M_SHMEM},${M_UNEVICTABLE},${M_SLAB_UNRECLAIMABLE},${M_SLAB_RECLAIMABLE},${M_KERNEL_STACK},${M_PAGETABLES},${M_SEC_PAGETABLES},${M_PERCPU},${M_SOCK},${M_FILE},${M_PSI_CENTI},${refault_rate},${pgscan_rate},${TIER},${SERVER_PID:--},${#SERVER_TREE[@]},${tree_rss},${n_protected},${n_eligible},${T_L1},${T_L4}"
  fi

  [[ -n $SERVER_PID ]] && apply_ceilings
  publish_summary "$now" "$M_H" "$TIER"
  check_calibration

  if [[ $TIER != "L0" && $TIER != "$PREV_TIER" ]]; then
    log_action "tier=${TIER} h=$(fmt_gib "$M_H") u=$(fmt_gib "$M_U") psi_full10=${M_PSI_CENTI} refault/s=${refault_rate} dU/s=${du_rate} projected=$(fmt_gib "$projected") ${census}${SUPPRESSED:+ suppressed=${SUPPRESSED}}"
  fi

  case "$TIER" in
  L2 | L3 | L4) shed_load "$TIER" "$now" ;;
  esac

  PREV_AT=$now
  PREV_U=$M_U
  PREV_REFAULT=$M_REFAULT_FILE
  PREV_PGSCAN=$M_PGSCAN_DIRECT
  PREV_TIER=$TIER
  return 0
}

# The previous version of this check compared T_L1 against memory.max and warned
# when the ratio looked wrong - a hardcoded rule about hardcoded numbers, which
# could only ever restate the assumption it was meant to test. Now that the
# ladder is derived, the honest check is the observation itself: has this pod, in
# its own life, ever had enough headroom to sit above the first rung? If not, the
# derivation is wrong for this workload whatever the arithmetic says, and the
# operator should see that before switching enforce on rather than after.
CALIBRATION_WARMUP="${WATCHDOG_CALIBRATION_WARMUP:-30}" # cycles

check_calibration() {
  ((CALIBRATION_WARNED)) && return 0
  ((CYCLE >= CALIBRATION_WARMUP)) || return 0
  CALIBRATION_WARNED=1
  if ((H_MAX_SEEN < T_L1)); then
    log_action "WARNING best headroom seen since start is $(fmt_gib "$H_MAX_SEEN"), below L1=$(fmt_gib "$T_L1") on memory.max=$(fmt_gib "$M_MAX") - this pod never leaves the ladder, so recalibrate or resize before enabling enforce mode"
  fi
  return 0
}

main() {
  mkdir -p "$STATE_DIR" || exit 1

  if ! acquire_singleton; then
    printf 'memory-watchdog: another instance is already running\n' >&2
    exit 0
  fi
  trap 'release_singleton; exit 0' HUP INT TERM
  trap release_singleton EXIT

  local now interval
  STARTED_AT=${WATCHDOG_NOW:-$EPOCHSECONDS}
  log_action "started mode=${MODE} pid=$$ cgroup=${CGROUP_DIR}"

  while :; do
    now=${WATCHDOG_NOW:-$EPOCHSECONDS}
    scan_once "$now"
    (($? == 2)) && break
    ((CYCLE += 1))

    [[ $ONESHOT == "1" ]] && break

    interval=$INTERVAL_IDLE
    [[ $PREV_TIER == "L0" ]] || interval=$INTERVAL_BUSY
    /usr/bin/sleep "$interval"
  done
  return 0
}

# Sourcing with WATCHDOG_SOURCE_ONLY=1 exposes the functions to the test harness
# without starting the loop.
if [[ ${WATCHDOG_SOURCE_ONLY:-0} != "1" ]]; then
  main "$@"
fi
