#!/bin/bash
set -eo pipefail

ENV_VARS_FILE="/home/coder/.env.pod"


record_env_vars() {
  if [[ -f "${ENV_VARS_FILE}" ]]; then
    rm -f "${ENV_VARS_FILE}"
  fi
  touch "${ENV_VARS_FILE}"
  for key in $(env | cut -d= -f1 | grep '^CODER_VAR_'); do
    value=$(printenv "$key")
    k=$(echo "$key" | sed 's/^CODER_VAR_//')
    echo "$k=\"$value\"" >> "${ENV_VARS_FILE}"
  done
}

main() {
  record_env_vars

  # Hand off to Coder's generated agent bootstrap, replacing this process rather
  # than spawning it: the agent has to stay PID 1, both because it reaps orphans
  # in this container and because the Deployment's liveness probe pgreps for it.
  echo "Starting Coder agent..."
  exec /bin/bash /scripts/workspace-init.sh
}

main
