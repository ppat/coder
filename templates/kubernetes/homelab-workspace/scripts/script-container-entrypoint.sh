#!/bin/bash
set -eo pipefail

main() {
  # Hand off to Coder's generated agent bootstrap, replacing this process rather
  # than spawning it: the agent has to stay PID 1, both because it reaps orphans
  # in this container and because the Deployment's liveness probe pgreps for it.
  echo "Starting Coder agent..."
  exec /bin/bash /scripts/workspace-init.sh
}

main
