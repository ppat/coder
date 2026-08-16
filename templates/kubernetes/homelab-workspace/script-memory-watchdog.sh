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
# Dependencies are deliberately tiny, because this runs before (and without) the
# operator's dotfiles: bash 4.4+, /proc, /sys/fs/cgroup, /usr/bin/sleep, coreutils
# mv/rm/mkdir, and - in enforce mode only - /usr/bin/prlimit. No brew, no mise, no
# python3, no flock, no awk. Measurement and process enumeration use bash builtins
# so a scan forks nothing.
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

# Tier thresholds, in absolute bytes of headroom H. Absolute rather than a
# percentage of memory.max, because the page cache a workload needs to make
# forward progress is a property of the workload, not of the limit.
#
# NOTE: unvalidated starting points, derived from role and an 8 GiB budget rather
# than from measurement. Replacing them with numbers taken from calibration.csv
# is the entire reason this ships in observe mode first.
T_L1="${WATCHDOG_T_L1:-3221225472}" # 3.00 GiB
T_L2="${WATCHDOG_T_L2:-2147483648}" # 2.00 GiB
T_L3="${WATCHDOG_T_L3:-1342177280}" # 1.25 GiB
T_L4="${WATCHDOG_T_L4:-805306368}"  # 0.75 GiB

# Corroboration is required at L2 only. At L2 we are "at the limit"; PSI and the
# refault rate are what separate "at the limit and fine" - the normal resting
# state of this pod - from "at the limit and dying". By L3/L4 there is no time
# left to wait for a second opinion.
T_PSI_CENTI="${WATCHDOG_T_PSI_CENTI:-1000}" # memory.pressure full avg10 >= 10.00
T_REFAULT_RATE="${WATCHDOG_T_REFAULT_RATE:-20000}"

DEBOUNCE_L1="${WATCHDOG_DEBOUNCE_L1:-3}"
DEBOUNCE_L2="${WATCHDOG_DEBOUNCE_L2:-3}"
DEBOUNCE_L3="${WATCHDOG_DEBOUNCE_L3:-2}"
COOLDOWN="${WATCHDOG_COOLDOWN:-180}"
PROJECTION_HORIZON="${WATCHDOG_PROJECTION_HORIZON:-60}" # seconds

# Soft RLIMIT_DATA ceilings by role, in bytes. Hard limits are never touched, so
# an inheriting shell restores itself with `ulimit -d unlimited`.
#
# NOT AGREED. Enforce mode must not be turned on until these are set from
# calibration data: too low kills a healthy extension host mid-edit, too high
# makes the mechanism inert.
declare -gA CEILING=(
  [serverMain]=1610612736     # 1.50 GiB
  [extensionHost]=3221225472  # 3.00 GiB
  [tsserver]=3758096384       # 3.50 GiB
  [languageServer]=1073741824 # 1.00 GiB
  [fileWatcher]=1073741824    # 1.00 GiB
)

# Roles L2 is allowed to shed. Each is restarted transparently or on demand by
# the editor, and none of them holds unsaved user state.
L2_ROLES=" tsserver languageServer fileWatcher "

MAX_LOG_LINES="${WATCHDOG_MAX_LOG_LINES:-20000}"
MAX_CSV_LINES="${WATCHDOG_MAX_CSV_LINES:-50000}"

# Scan state. Declared at file scope, not inside main(), so that sourcing the
# script with WATCHDOG_SOURCE_ONLY=1 gives the test harness correctly-typed
# globals without having to restate them.
declare -gA P_COMM=() P_CMD=() P_RSS=() CHILDREN=()
declare -gA SERVER_TREE=() PROTECTED=()
declare -ga PIDS=() CANDIDATES=()
SERVER_PID=""
TIER=L0
ROLE=other
PREV_TIER=L0
PREV_AT=0
PREV_U=0
PREV_REFAULT=0
PREV_PGSCAN=0
CYCLE=0

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

# Sets SERVER_PID to the pid of the remote server entrypoint, or "".
#
# Matching is on a whole argv element, not on a substring of the joined command
# line. Anything that merely mentions the path - a grep over the server's log, an
# editor, a shell running a script that names it - would otherwise be mistaken
# for the root, and the root is what scopes every subsequent decision. A match
# whose comm is `node` wins outright; anything else is only a fallback.
find_server_root() {
  local pid arg fallback=""
  local -a argv
  SERVER_PID=""
  for pid in "${PIDS[@]}"; do
    [[ ${P_CMD[$pid]} == *"/.vscode-server/"*"out/server-main.js"* ]] || continue
    argv=()
    mapfile -d '' -t argv <"${PROC_DIR}/${pid}/cmdline" 2>/dev/null
    for arg in "${argv[@]}"; do
      [[ $arg == *"/.vscode-server/"*"out/server-main.js" ]] || continue
      if [[ ${P_COMM[$pid]:-} == "node" ]]; then
        SERVER_PID=$pid
        return 0
      fi
      [[ -n $fallback ]] || fallback=$pid
      break
    done
  done
  [[ -n $fallback ]] || return 1
  SERVER_PID=$fallback
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

# The never-signal list. Every action consults this directly, so a defect in
# tree-walking still cannot route around it.
#
# Tree membership is NOT a safe kill criterion: tmux sessions and long-running
# agents started from a VS Code integrated terminal are descendants of the server
# tree via ptyHost. Errors here are one-directional by design - refusing to
# signal something that could safely have been signalled costs nothing.
is_never_signal() {
  local pid=$1
  ((pid <= 1)) && return 0
  ((pid == $$)) && return 0
  ((pid == BASHPID)) && return 0
  ((pid == PPID)) && return 0
  case "${P_COMM[$pid]:-}" in
  coder | claude | chezmoi | sshd | init | systemd) return 0 ;;
  tmux*) return 0 ;;
  esac
  case "${P_CMD[$pid]:-}" in
  *"coder agent"*) return 0 ;;
  *"/claude"* | "claude" | "claude "*) return 0 ;;
  *chezmoi*) return 0 ;;
  *memory-watchdog*) return 0 ;;
  esac
  return 1
}

# Everything the watchdog must never touch: the never-signal names anywhere in
# the pod, plus every ptyHost fork inside the server tree and all its descendants.
compute_protected() {
  PROTECTED=()
  local pid p
  local -A pty=()

  for pid in "${PIDS[@]}"; do
    is_never_signal "$pid" && PROTECTED[$pid]=1
  done

  for pid in "${!SERVER_TREE[@]}"; do
    if [[ ${P_CMD[$pid]:-} == *"--type=ptyHost"* ]]; then
      subtree_of "$pid" pty
      for p in "${!pty[@]}"; do
        PROTECTED[$p]=1
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
  *) ROLE=other ;;
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

# Sets TIER. Called in the current shell, never in a command substitution - the
# debounce counters are state and a subshell would silently discard them.
decide_tier() {
  local h=$1 psi=$2 refault=$3 proj=$4 now=$5

  if ((h < T_L1)); then ((C_L1 += 1)); else C_L1=0; fi
  if ((h < T_L2)); then ((C_L2 += 1)); else C_L2=0; fi
  if ((h < T_L3)); then ((C_L3 += 1)); else C_L3=0; fi

  if ((h < T_L4)); then
    TIER=L4
    return 0
  fi

  TIER=L0
  if ((C_L3 >= DEBOUNCE_L3)); then
    TIER=L3
  elif ((C_L2 >= DEBOUNCE_L2)) &&
    { ((psi >= T_PSI_CENTI)) || ((refault >= T_REFAULT_RATE)); }; then
    TIER=L2
  elif ((C_L1 >= DEBOUNCE_L1)); then
    TIER=L1
  fi

  # Projection. Armed only once headroom is already below L1, so a momentary
  # allocation spike from an idle state cannot vault the ladder.
  if [[ $TIER != "L0" ]] && ((proj < T_L4)); then
    TIER=L3
  fi

  # Cooldown applies to the acting tiers only. L4 is exempt because by then the
  # alternative to acting is an oom.group kill of everything in the pod.
  if [[ $TIER == "L2" || $TIER == "L3" ]] && ((now - LAST_ACTION_AT < COOLDOWN)); then
    TIER=L1
  fi
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

fmt_gib() {
  printf '%d.%02d GiB' "$(($1 / GIB))" "$(($1 % GIB * 100 / GIB))"
}

publish_headroom() {
  printf '%s free (%s)\n' "$(fmt_gib "$1")" "$2" >"${STATE_DIR}/headroom.tmp" &&
    mv -f "${STATE_DIR}/headroom.tmp" "${STATE_DIR}/headroom"
  return 0
}

append_calibration() {
  local csv="${STATE_DIR}/calibration.csv"
  if [[ ! -s $csv ]]; then
    printf '%s\n' \
      "ts,mem_max,mem_current,u,h,anon,shmem,unevictable,slab_unreclaimable,slab_reclaimable,kernel_stack,pagetables,sec_pagetables,percpu,sock,file,psi_full_avg10_centi,refault_file_per_s,pgscan_direct_per_s,tier,server_pid,tree_procs,tree_rss" \
      >"$csv"
  fi
  printf '%s\n' "$*" >>"$csv"
  ((CSV_LINES += 1))
  if ((CSV_LINES > MAX_CSV_LINES)); then
    mv -f "$csv" "${csv}.1" 2>/dev/null
    CSV_LINES=0
  fi
  return 0
}

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
    log_action "ceiling pid=${pid} role=${ROLE} rlimit_data=${want} was=${cur}"
  done
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
  ((${#CANDIDATES[@]})) || return 0

  for row in "${CANDIDATES[@]}"; do
    rss=${row%% *}
    pid=${row#* }
    role=${pid#* }
    pid=${pid%% *}
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

  ((acted)) && LAST_ACTION_AT=$now
  return 0
}

# --------------------------------------------------------------------------- #
# lifecycle
# --------------------------------------------------------------------------- #

# A coder_script re-runs when the agent restarts without the pod restarting, so
# two watchdogs are otherwise entirely possible. noclobber gives an atomic O_EXCL
# create without flock, which is brew-only here.
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
  read_cgroup_pressure
  read_process_table

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

  SERVER_TREE=()
  if find_server_root; then
    subtree_of "$SERVER_PID" SERVER_TREE
    read_rss "${!SERVER_TREE[@]}"
  fi
  compute_protected

  decide_tier "$M_H" "$M_PSI_CENTI" "$refault_rate" "$projected" "$now"
  publish_headroom "$M_H" "$TIER"

  local tree_rss=0 pid
  for pid in "${!SERVER_TREE[@]}"; do
    tree_rss=$((tree_rss + ${P_RSS[$pid]:-0}))
  done

  if ((CYCLE % CALIBRATION_EVERY == 0)); then
    append_calibration "${now},${M_MAX},${M_CURRENT},${M_U},${M_H},${M_ANON},${M_SHMEM},${M_UNEVICTABLE},${M_SLAB_UNRECLAIMABLE},${M_SLAB_RECLAIMABLE},${M_KERNEL_STACK},${M_PAGETABLES},${M_SEC_PAGETABLES},${M_PERCPU},${M_SOCK},${M_FILE},${M_PSI_CENTI},${refault_rate},${pgscan_rate},${TIER},${SERVER_PID:--},${#SERVER_TREE[@]},${tree_rss}"
  fi

  [[ -n $SERVER_PID ]] && apply_ceilings

  if [[ $TIER != "L0" && $TIER != "$PREV_TIER" ]]; then
    log_action "tier=${TIER} h=$(fmt_gib "$M_H") u=$(fmt_gib "$M_U") psi_full10=${M_PSI_CENTI} refault/s=${refault_rate} dU/s=${du_rate} projected=$(fmt_gib "$projected") tree=${#SERVER_TREE[@]}"
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

warn_if_thresholds_oversized() {
  local raw=""
  read -r raw <"${CGROUP_DIR}/memory.max" 2>/dev/null
  [[ $raw =~ ^[0-9]+$ ]] || return 0
  # An 8 GiB pod rests at U ~1.9 GiB and so has ~6 GiB of headroom. A 4 GiB pod
  # has ~2 GiB and would sit permanently at L1/L2 against these absolute
  # thresholds. That is a calibration problem, not something to paper over with a
  # clamp, so say it once, loudly, in the log the operator will actually read.
  ((T_L1 * 2 > raw)) &&
    log_action "WARNING memory.max=${raw} is small relative to T_L1=${T_L1}; the ladder will sit low permanently - recalibrate before enabling enforce mode"
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

  log_action "started mode=${MODE} pid=$$ cgroup=${CGROUP_DIR} thresholds L1=${T_L1} L2=${T_L2} L3=${T_L3} L4=${T_L4}"
  warn_if_thresholds_oversized

  local now interval
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
