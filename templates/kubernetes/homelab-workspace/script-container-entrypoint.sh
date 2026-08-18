#!/bin/bash
set -eo pipefail


# Where wipe_tmp records its outcome for script-agent-startup.sh to assert on.
# Kept in /tmp on purpose: it is written after the wipe, so its presence is also
# evidence that this script ran at all this boot.
TMP_WIPE_STATUS_FILE="/tmp/.tmp-wipe-status"


# Restore the "a fresh container gets a fresh /tmp" property that /tmp lost when
# it moved off the container's writable overlay layer onto a per-Pod volume (see
# the "tmp" volume in deployment.tf). A Pod recreate still gets an empty volume
# for free; a container-only restart within a live Pod - an OOM kill, a liveness
# probe failure - does not, and would otherwise inherit whatever the previous
# container left behind.
#
# This has to run in the container entrypoint, before the Coder agent exists,
# and not in the agent startup script. Coder's own bootstrap (the generated
# /workspace-init.sh) unpacks the agent CLI into a per-boot mktemp directory
# under /tmp, chdirs into it, appends it to the PATH of every session and script
# the agent runs, and only then runs the startup script - so a wipe from the
# startup script deletes the CLI the agent installed moments earlier, which is
# exactly how every "coder stat" metadata panel came to report "coder: command
# not found".
#
# Excluding the agent's paths from the wipe instead is not a fix. The set is
# version-dependent and not even consistently named: on the deployed agent it is
# a random-suffixed coder.XXXXXX directory, coder-agent.sock, coder-agent*.log,
# coder-script-data/, coder-screen/ - and also boundary-audit.sock, which does
# not carry the "coder" prefix at all. An allowlist that silently stops matching
# after a Coder upgrade reintroduces this same failure just as invisibly. There
# is nothing to exclude here, because nothing of the agent's exists yet.
#
# The wipe is deliberately best-effort rather than fatal: this script is the
# only path to a running agent, so aborting here turns a stale-scratch-space
# problem into a CrashLoopBackOff with no way to shell in and look. Visibility
# is preserved instead by recording the outcome for the startup script, which
# can fail loudly in the workspace UI without taking the workspace down.
wipe_tmp() {
  echo "Wiping /tmp..."
  local errors
  errors="$(find /tmp -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>&1)" || true
  if [[ -n "${errors}" ]]; then
    echo "ERROR: failed to fully wipe /tmp:" >&2
    echo "${errors}" >&2
    printf 'failed\n%s\n' "${errors}" > "${TMP_WIPE_STATUS_FILE}"
    return 0
  fi
  printf 'ok\n' > "${TMP_WIPE_STATUS_FILE}"
}


main() {
  wipe_tmp
  # Hand off to Coder's generated agent bootstrap, replacing this process rather
  # than spawning it: the agent has to stay PID 1, both because it reaps orphans
  # in this container and because the Deployment's liveness probe pgreps for it.
  echo "Starting Coder agent..."
  exec /bin/bash /workspace-init.sh
}

main
