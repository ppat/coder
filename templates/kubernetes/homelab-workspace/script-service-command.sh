#!/bin/bash
set -euo pipefail

index="${1:?service command index is required}"
command="$(jq --exit-status --raw-output ".[$index]" <<<"${SUPERVISOR_SERVICE_COMMANDS}")"
exec /bin/bash --login -c "${command}"
