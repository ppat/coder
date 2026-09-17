#!/bin/bash
set -eo pipefail

# Coder's bootstrap unpacks the agent CLI into a per-boot directory under /tmp
# and the agent appends that directory to the PATH of everything it runs, so
# resolving "coder" here goes through exactly the same lookup a metadata script
# does. errexit above plus startup_script_behavior = "blocking" turn a failure
# into a visibly failed startup script in the workspace UI, while the agent
# process itself keeps running so the workspace stays reachable to debug.
assert_agent_cli() {
  local cli
  if ! cli="$(command -v coder)"; then
    echo "ERROR: the Coder agent CLI is not on PATH." >&2
    echo "       Nothing may remove the agent's own files from /tmp - see" >&2
    echo "       script-container-entrypoint.sh for why the wipe runs there." >&2
    echo "       PATH=${PATH}" >&2
    return 1
  fi
  if ! "${cli}" version > /dev/null; then
    echo "ERROR: the Coder agent CLI at ${cli} is present but not usable." >&2
    return 1
  fi
  echo "Coder agent CLI: ${cli}"
}

main() {
  assert_agent_cli
  if [[ ! -s ~/.bashrc ]]; then
    echo "Setting up starter bash rc scripts from /etc/skel..."
    cp /etc/skel/.bashrc ~/.bashrc
    cp /etc/skel/.profile ~/.profile
    echo 'set -o allexport; source /etc/environment; set +o allexport' >> ~/.bashrc
    echo '------------------------------------------------------------'
  fi
  echo 'Done'
}

main
