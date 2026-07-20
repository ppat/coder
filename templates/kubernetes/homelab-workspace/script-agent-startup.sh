#!/bin/bash
# Runs as the `coder` user via the Coder agent's startup_script hook, after the
# agent is up. This is the place for per-user setup that must run unprivileged.
# (Docker + system prep now happen earlier, as root, in script-workspace-entrypoint.sh.)
set -eo pipefail

main() {
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
