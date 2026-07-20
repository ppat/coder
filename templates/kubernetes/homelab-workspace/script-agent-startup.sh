#!/bin/bash
set -eo pipefail


setup_docker() {
  export XDG_RUNTIME_DIR="/run/user/10001"
  export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/docker.sock"
  # dockerd-rootless.sh and dockerd-rootless-setuptool.sh ship in /usr/bin
  export PATH="/usr/bin:${PATH}"

  echo 'Ensuring XDG_RUNTIME_DIR exists...'
  mkdir -p "${XDG_RUNTIME_DIR}"
  chmod 700 "${XDG_RUNTIME_DIR}"

  echo 'Installing rootless docker (idempotent; tolerate re-run)...'
  dockerd-rootless-setuptool.sh install 2>&1 | sed -E -n 's|^|    |p' || true

  echo 'Starting rootless dockerd...'
  # Storage driver is auto-detected by dockerd with preference order
  # overlay2 -> fuse-overlayfs -> vfs. When overlay2 is unavailable in this
  # (userns) environment docker falls back on its own; pass `--storage-driver`
  # to dockerd-rootless.sh only if a specific driver must be forced.
  setsid dockerd-rootless.sh > "${HOME}/.local/share/docker/dockerd.log" 2>&1 &

  echo 'Waiting up to ~30s for docker to become ready...'
  for _ in $(seq 1 30); do
    if docker info > /dev/null 2>&1; then
      echo 'Docker is ready.'
      return 0
    fi
    sleep 1
  done
  echo "Docker did not become ready; see ${HOME}/.local/share/docker/dockerd.log"
  return 1
}

main() {
  if [[ ! -s ~/.bashrc ]]; then
    echo "Setting up starter bash rc scripts from /etc/skel..."
    cp /etc/skel/.bashrc ~/.bashrc
    cp /etc/skel/.profile ~/.profile
    echo 'set -o allexport; source /etc/environment; set +o allexport' >> ~/.bashrc
    echo '------------------------------------------------------------'
  fi
  if [[ "${ENABLE_DOCKER:-false}" == "true" ]]; then
    echo "Setting up rootless Docker..."
    # Non-fatal: a docker failure must not abort agent startup.
    setup_docker 2>&1 | sed -E -n 's|^|    |p' || true
  fi
  echo 'Done'
}

main
