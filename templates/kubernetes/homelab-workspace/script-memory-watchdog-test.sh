#!/bin/bash
#
# Fixture tests for script-memory-watchdog.sh.
#
# Run it directly; it needs nothing but bash and a writable TMPDIR:
#
#   ./script-memory-watchdog-test.sh
#
# CI does not run this - there is no test stage in this repo (see TESTING.md).
# It exists so that the two things in the watchdog that can actually hurt the
# operator - the unreclaimable-memory arithmetic and the process-selection rules
# - can be changed with evidence rather than hope.
#
# The important cases here are the negative ones. A test that asserts "the
# watchdog did not signal the memory hog" proves nothing unless the same fixture,
# with the ptyHost marker removed, produces the opposite result - so each
# exclusion is paired with the mutation that must flip it.
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
  printf '0 %s 0 0 0 0 0\n' "$((rss / 4096))" >"${d}/statm"
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

# A representative tree. The hog is three levels below ptyHost, exactly like a
# tmux session or an agent started from a VS Code integrated terminal.
#
#   1  coder agent
#   +- 40   server-main.js
#   |   +- 41  extensionHost
#   |   |   +- 44  tsserver.js
#   |   |   +- 45  yaml-language-server
#   |   +- 42  fileWatcher
#   |   +- 43  ptyHost                 <- excised, with its whole subtree
#   |       +- 50  bash
#   |           +- 51  tmux: server
#   |               +- 52  claude
#   |               +- 53  node (the hog)
#   +- 60   claude (outside the tree)
build_tree() {
  local dir=$1 ptyhost_arg=${2:---type=ptyHost}
  local srv="/home/coder/.vscode-server/cli/servers/Stable-abc/server/out/server-main.js"
  mkdir -p "$dir"
  add_proc "$dir" 1 0 coder 14208 ./coder agent
  # A decoy with a lower pid that merely *mentions* both marker strings, and a
  # ptyHost flag inside a larger argument. Naive substring matching would elect
  # it as the server root and mis-scope every decision that follows.
  add_proc "$dir" 3 1 bash 3000000 bash -c \
    "tail -f ${srv}.log --type=extensionHost-ish"
  add_proc "$dir" 40 1 node 300000000 /usr/bin/node "$srv" --host localhost
  add_proc "$dir" 41 40 node 1500000000 /usr/bin/node "$srv" bootstrap-fork --type=extensionHost
  add_proc "$dir" 44 41 node 2000000000 /usr/bin/node /home/coder/.vscode-server/extensions/ms-ts/tsserver.js
  add_proc "$dir" 45 41 node 400000000 /usr/bin/node /home/coder/.vscode-server/extensions/redhat/yaml-language-server
  add_proc "$dir" 42 40 node 250000000 /usr/bin/node "$srv" bootstrap-fork --type=fileWatcher
  add_proc "$dir" 43 40 node 100000000 /usr/bin/node "$srv" bootstrap-fork "$ptyhost_arg"
  add_proc "$dir" 50 43 bash 20000000 /bin/bash -l
  add_proc "$dir" 51 50 "tmux: server" 5000000 tmux new -s work
  add_proc "$dir" 52 51 claude 900000000 claude
  add_proc "$dir" 53 51 node 3000000000 node -e "const a=[];setInterval(()=>a.push(Buffer.alloc(1)),1)"
  add_proc "$dir" 60 1 claude 700000000 claude
}

load_watchdog() {
  WATCHDOG_SOURCE_ONLY=1 \
    WATCHDOG_CGROUP_DIR="$1" \
    WATCHDOG_PROC_DIR="$2" \
    WATCHDOG_STATE_DIR="${WORK}/state" \
    WATCHDOG_MODE=observe \
    . "${SELF_DIR}/script-memory-watchdog.sh"
  mkdir -p "${WORK}/state"
}

scan_fixture() {
  read_cgroup_memory
  read_cgroup_pressure
  read_process_table
  SERVER_TREE=()
  if find_server_root; then
    subtree_of "$SERVER_PID" SERVER_TREE
    read_rss "${!SERVER_TREE[@]}"
  fi
  compute_protected
}

candidate_pids() {
  select_candidates "$1"
  local row pid out=""
  for row in "${CANDIDATES[@]}"; do
    pid=${row#* }
    out+="${pid%% *} "
  done
  printf '%s' "${out% }"
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

  assert_eq 40 "$SERVER_PID" "server root found by argv element, not by substring"
  assert_eq 10 "${#SERVER_TREE[@]}" "server tree spans every descendant, ptyHost included"
  if [[ -n ${SERVER_TREE[3]:-} ]]; then
    bad "a process that merely mentions the server path joined the tree"
  else
    ok "a process that merely mentions the server path stays out of the tree"
  fi
  role_of 3
  assert_eq other "$ROLE" "a --type=extensionHost-ish argument is not read as a role flag"
  role_of 43
  assert_eq ptyHost "$ROLE" "the real --type=ptyHost argument is"

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

  assert_eq "44 45 42" "$(candidate_pids L2)" \
    "L2 offers only kill-safe helpers, heaviest first"
  assert_eq "41" "$(candidate_pids L3)" "L3 offers only the extension host"
  # Ordered by RSS, so serverMain (300M) precedes fileWatcher (250M).
  assert_eq "44 41 45 40 42" "$(candidate_pids L4)" \
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
  test_selection_is_falsifiable
  test_tiers
  test_observe_mode_is_inert
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  ((FAIL == 0))
}

main "$@"
