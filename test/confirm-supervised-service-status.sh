#!/usr/bin/env bash
set -euo pipefail

wait_for_service_restarts() {
  workspace_name="$1"
  until count="$(coder ssh "${workspace_name}.main" -- stat --format=%s /tmp/service-restarts 2>/dev/null)" && [ "$count" -ge 2 ]; do
    sleep 2;
  done
}

WORKSPACE_NAME="$1"
if ! timeout 2m wait_for_service_restarts "${WORKSPACE_NAME}"; then
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
