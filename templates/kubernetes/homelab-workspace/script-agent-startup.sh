#!/bin/bash
set -eo pipefail


# Written by script-container-entrypoint.sh, which wipes /tmp before the agent
# starts.
TMP_WIPE_STATUS_FILE="/tmp/.tmp-wipe-status"


# The check that would have caught the regression where wiping /tmp deleted the
# agent's own CLI: every "coder stat" metadata panel reported "coder: command
# not found" for a released template version, and nothing else noticed.
#
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


# The /tmp wipe cannot abort the container entrypoint without risking a
# CrashLoopBackOff, so it reports here instead. This keeps a partial wipe a
# loud failure rather than a silent leak on a fixed-size volume.
assert_tmp_wiped() {
  if [[ ! -f "${TMP_WIPE_STATUS_FILE}" ]]; then
    echo "ERROR: ${TMP_WIPE_STATUS_FILE} is missing - the container entrypoint" >&2
    echo "       did not run. Check the workspace container's command in" >&2
    echo "       deployment.tf; /tmp is no longer being cleared on restart." >&2
    return 1
  fi
  if [[ "$(head -n 1 "${TMP_WIPE_STATUS_FILE}")" != "ok" ]]; then
    echo "ERROR: /tmp was not fully wiped on container start:" >&2
    cat "${TMP_WIPE_STATUS_FILE}" >&2
    return 1
  fi
  echo "/tmp wiped on container start"
}


main() {
  assert_tmp_wiped
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
