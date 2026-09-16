#!/bin/bash
set -u

state_dir="${HOME}/.local/state/vscode-memory-watchdog"
mkdir -p "${state_dir}"
/usr/bin/setsid --fork /bin/bash /scripts/script-memory-watchdog.sh \
  </dev/null >>"${state_dir}/boot.log" 2>&1
echo "memory watchdog started in ${WATCHDOG_MODE:-observe} mode; state in ${state_dir}"
