#!/bin/bash
set -euo pipefail

if (( SUPERVISOR_SERVICE_COUNT == 0 )); then
  echo "no supervised service commands configured"
  exit 0
fi

dotfiles_state_file="${HOME}/.local/state/dotfiles/applied"
timeout 180s bash -c "until [ -e '$dotfiles_state_file' ]; do sleep 5; done"
if [ $? -eq 124 ]; then
  echo "Timed out waiting for dotfiles to be applied. Please check the logs for errors."
  exit 1
else
  echo "Dotfiles applied successfully. Proceeding to start supervised services."
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
