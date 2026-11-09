#!/usr/bin/env bash
set -euo pipefail

place_lifecycle_markers() {
  workspace_name="$1"
  coder ssh "${workspace_name}.main" -- touch /home/coder/.home-pvc-lifecycle
  coder ssh "${workspace_name}.main" -- touch /tmp/.tmp-pvc-lifecycle
}

restart_workspace() {
  workspace_name="$1"
  tmp_pvc_name="$(kubectl get -n coder pvc -l com.coder.workspace.name=${WORKSPACE_NAME},storage-type=tmp -o name)"
  pod_name="$(kubectl get -n coder pod -l com.coder.workspace.name=${WORKSPACE_NAME} -o name)"

  echo "Stopping workspace..."
  coder stop "${workspace_name}" --yes | sed 's/^/  /'
  echo "Waiting for pod to be deleted..."
  kubectl --namespace coder wait --for=delete "${pod_name}" --timeout=5m | sed 's/^/  /'
  echo "Waiting for tmp PVC to be deleted..."
  kubectl --namespace coder wait --for=delete "${tmp_pvc_name}" --timeout=5m | sed 's/^/  /'
  echo "Show resources after stop:"
  kubectl --namespace coder get pods,pvc | sed 's/^/  /'
  echo "Starting workspace..."
  coder start "${workspace_name}" --no-wait --yes | sed 's/^/  /'
  echo "Waiting for workspace to be ready..."
  coder ping --num 3 --timeout 30s "${workspace_name}.main" | sed 's/^/  /'
}

confirm_pvc_lifecycle_behavior() {
  workspace_name="$1"
  coder ssh "${workspace_name}.main" -- test -f /home/coder/.home-pvc-lifecycle || {
    echo "::error::Home PVC did not preserve the lifecycle marker across restarts."
    exit 1
  }
  coder ssh "${workspace_name}.main" -- test ! -f /tmp/.tmp-pvc-lifecycle || {
    echo "::error::Expected a fresh Temp PVC, but got the same as the lifecycle marker was preserved across restarts."
    exit 1
  }
}

WORKSPACE_NAME="$1"

echo "Touching lifecycle marker files on home and tmp PVCs..."
place_lifecycle_markers "${WORKSPACE_NAME}" | sed 's/^/  /'
echo

echo "Stopping workspace and waiting for tmp PVC to be deleted..."
restart_workspace "${WORKSPACE_NAME}" | sed 's/^/  /'
echo

echo "Confirming home PVC lifecycle marker is preserved and tmp PVC is replaced..."
confirm_pvc_lifecycle_behavior "${WORKSPACE_NAME}" | sed 's/^/  /'
echo
