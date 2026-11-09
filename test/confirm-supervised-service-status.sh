#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_NAME="$1"
# Expand the positional parameter inside the runner-owned polling shell.
# shellcheck disable=SC2016
if ! timeout 2m bash -c \
  'until count="$(coder ssh "$1" -- stat --format=%s /tmp/service-restarts 2>/dev/null)" &&
  [ "$count" -ge 2 ]; do sleep 2; done' \
  _ "${WORKSPACE_NAME}.main"; then
  echo "::error::Supervised services restarted at least twice within 2 minutes, indicating a failure to start properly. See supervisorctl status and service logs below."
  echo
  coder ssh "${WORKSPACE_NAME}.main" -- supervisorctl --configuration /scripts/supervisord.conf status || true
  echo
  coder ssh "${WORKSPACE_NAME}.main" -- ls -la /home/coder/.local/state/supervisor /tmp/service-* || true
  echo
  coder ssh "${WORKSPACE_NAME}.main" -- tail -n 100 /home/coder/.local/state/supervisor/service-0.log || true
  echo
  coder ssh "${WORKSPACE_NAME}.main" -- tail -n 100 /home/coder/.local/state/supervisor/service-1.log || true
  echo
  exit 1
fi

coder ssh "${WORKSPACE_NAME}.main" -- test ! -e /tmp/service-started-too-early
echo
coder ssh "${WORKSPACE_NAME}.main" -- test -e /tmp/service-steady
echo
coder ssh "${WORKSPACE_NAME}.main" -- supervisorctl --configuration /scripts/supervisord.conf status service:service-0
echo
coder ssh "${WORKSPACE_NAME}.main" -- supervisorctl --configuration /scripts/supervisord.conf status service:service-1
echo
