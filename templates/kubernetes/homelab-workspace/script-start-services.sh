#!/bin/bash
set -euo pipefail

if (( SUPERVISOR_SERVICE_COUNT == 0 )); then
  echo "no supervised service commands configured"
  exit 0
fi

state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/supervisor"
mkdir -p "${state_dir}"

if [[ -s "${state_dir}/supervisord.pid" ]]; then
  supervisor_pid="$(<"${state_dir}/supervisord.pid")"
  if [[ "${supervisor_pid}" =~ ^[0-9]+$ ]] && kill -0 "${supervisor_pid}" 2>/dev/null; then
    echo "supervisor already running as pid ${supervisor_pid}; state in ${state_dir}"
    exit 0
  fi
  rm -f "${state_dir}/supervisord.pid" "${state_dir}/supervisor.sock"
fi

/usr/bin/supervisord --configuration /scripts/supervisord.conf
echo "started ${SUPERVISOR_SERVICE_COUNT} supervised service command(s); state in ${state_dir}"
