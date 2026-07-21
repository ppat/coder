#!/bin/bash
# Main container entrypoint. Runs as root (uid 0) INSIDE the pod's user
# namespace (hostUsers=false), so "root" here maps to an unprivileged uid on the
# host -- see DESIGN-DIND.md. Responsibilities, in order:
#   1. prepare the workspace (extra apt packages, Homebrew, PATH) -- previously an
#      init container; now done here directly because this container is already root.
#   2. start a rootful dockerd (non-fatal: the workspace must come up even if it fails).
#   3. drop to the unprivileged `coder` user and exec the Coder agent, so everything
#      the user interacts with runs as `coder` exactly as before.
set -eo pipefail

CODER_USER="coder"
CODER_UID="10001"
CODER_GID="10001"
HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/home/linuxbrew/.linuxbrew}"

# --------------------------------------------------------------------------------
install_homebrew() {
  export HOMEBREW_CELLAR="${HOMEBREW_PREFIX}/Cellar"
  export HOMEBREW_NO_ANALYTICS=1
  export PATH="${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin:$PATH"
  # Homebrew refuses to install as root; run its installer as the coder user.
  # (/.dockerenv makes the installer treat this as a container and skip sudo prompts.)
  touch /.dockerenv
  setpriv --reuid "${CODER_UID}" --regid "${CODER_GID}" --init-groups \
    env HOME="/home/${CODER_USER}" NONINTERACTIVE=1 \
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

setup_homebrew() {
  export HOMEBREW_CACHE="/home/${CODER_USER}/.cache/Homebrew"
  echo 'Checking for brew installation...'
  local brew_file_count
  brew_file_count=$(find "${HOMEBREW_PREFIX}" -maxdepth 3 -type f 2> /dev/null | wc -l)
  if [[ "${brew_file_count}" -gt "0" && -f "${HOMEBREW_PREFIX}/bin/brew" ]]; then
    echo 'Brew installation already exists... skipping.'
  else
    echo 'No existing brew installation, proceeding w/ installation...'
    mkdir -p "${HOMEBREW_CACHE}"
    install_homebrew 2>&1 | sed -E -n 's|^|    |p'
  fi
  echo 'Ensuring ownership of brew + home top-level dirs by coder...'
  chown -R "${CODER_USER}:root" "$(dirname "${HOMEBREW_PREFIX}")" "${HOMEBREW_CACHE}"
  chown "${CODER_USER}:${CODER_USER}" "/home/${CODER_USER}" "/home/${CODER_USER}/.cache"
}

setup_system_packages() {
  echo "Installing additional apt packages: ${SYSTEM_PACKAGES:-NONE}"
  if [[ "${SYSTEM_PACKAGES:-NONE}" != "NONE" ]]; then
    apt-get update 2>&1 | sed -E -n 's|^|    |p'
    apt-file update 2>&1 | sed -E -n 's|^|    |p' || true
    # shellcheck disable=SC2086
    DEBIAN_FRONTEND="noninteractive" apt-get install --no-install-recommends -yq ${SYSTEM_PACKAGES} 2>&1 | sed -E -n 's|^|    |p'
  fi
}

prepare_environment() {
  # Extend the system PATH (in /etc/environment) with Homebrew, in place -- no
  # /updated staging volume any more since this container owns its own rootfs.
  local existing updated
  existing="$(grep '^PATH=' /etc/environment | cut -d'=' -f2)"
  updated="${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin:${existing}"
  grep -v '^PATH=' /etc/environment > /tmp/environment.new
  echo "PATH=${updated}" >> /tmp/environment.new
  sort /tmp/environment.new > /etc/environment
  rm -f /tmp/environment.new
}

# --------------------------------------------------------------------------------
setup_docker() {
  if ! command -v dockerd > /dev/null 2>&1; then
    echo 'dockerd not found in image; skipping docker setup.'
    return 1
  fi
  # Let the coder user reach the daemon socket.
  groupadd --force docker
  usermod --append --groups docker "${CODER_USER}"

  # Docker's data root must live on a mount that dockerd can make shared and
  # bind-mount within (it does this for every layer/snapshot). A PVC mounted by
  # the kubelet is created OUTSIDE this pod's user namespace, so it is a locked,
  # private mount: `mount --make-shared` and the snapshot bind-mounts both fail
  # with EPERM even as (namespaced) root. A bind mount we create ourselves inside
  # this container's mount namespace is not locked, so dockerd can manage it.
  #
  # Back the data root with a dir under the home PVC (persists across stop) and
  # bind it to /var/lib/docker. Both dirs must be root:root 0711 -- dockerd
  # rejects a world/group-accessible data root, and the home PVC is otherwise
  # fsGroup-owned by the coder group.
  local docker_data="/home/${CODER_USER}/.var/docker"
  mkdir -p "${docker_data}" /var/lib/docker
  chown root:root "${docker_data}" /var/lib/docker
  chmod 0711 "${docker_data}" /var/lib/docker
  mount --bind "${docker_data}" /var/lib/docker
  # dockerd also sets this itself; do it up front so the data root is shared before
  # it starts. Non-fatal -- if it fails, dockerd's own attempt is what matters.
  mount --make-shared /var/lib/docker || true

  echo 'Starting dockerd...'
  # Rootful dockerd. CAP_SYS_ADMIN/NET_ADMIN (granted on the container, valid only
  # inside the userns) cover what it needs. overlay2 is the default/expected driver.
  setsid dockerd > /var/log/dockerd.log 2>&1 &

  echo 'Waiting up to ~30s for docker to become ready...'
  local waited=0
  while [[ "${waited}" -lt 30 ]]; do
    waited=$((waited + 1))
    if docker info > /dev/null 2>&1; then
      echo 'Docker is ready.'
      # socket is created 0660 root:docker; ensure the group can use it
      chgrp docker /var/run/docker.sock 2> /dev/null || true
      chmod 660 /var/run/docker.sock 2> /dev/null || true
      return 0
    fi
    sleep 1
  done
  echo 'Docker did not become ready; see /var/log/dockerd.log'
  return 1
}

# --------------------------------------------------------------------------------
main() {
  echo '=== workspace entrypoint (root) ==='

  echo '--- system packages ---'
  setup_system_packages | sed -E -n 's|^|    |p' || echo '    (system package setup failed; continuing)'

  echo '--- homebrew ---'
  setup_homebrew 2>&1 | sed -E -n 's|^|    |p' || echo '    (homebrew setup failed; continuing)'

  echo '--- environment ---'
  prepare_environment || echo '    (environment prep failed; continuing)'

  echo '--- docker ---'
  # Non-fatal by design: a docker failure must never stop the workspace coming up.
  setup_docker 2>&1 | sed -E -n 's|^|    |p' || echo '    (docker setup failed; workspace continues without docker)'

  echo '--- starting coder agent as coder ---'
  # Drop from root to the coder user and hand off to the agent. exec so the agent
  # becomes the container's main process (as it was when the container ran as coder).
  # --init-groups picks up the docker group added above. Preserve the agent env.
  exec setpriv --reuid "${CODER_UID}" --regid "${CODER_GID}" --init-groups \
    env HOME="/home/${CODER_USER}" USER="${CODER_USER}" \
    CODER_AGENT_TOKEN="${CODER_AGENT_TOKEN}" \
    /bin/bash /workspace-init.sh
}

main
