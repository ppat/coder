#!/bin/bash
set -euo pipefail

install_homebrew() {
  local brew_user="$1"
  export HOMEBREW_CELLAR="${HOMEBREW_PREFIX}/Cellar"
  export HOMEBREW_NO_ANALYTICS=1
  export PATH="${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin:$PATH"
  # init container runs as root but homebrew doesn't support running as root
  # we don't want to give any users within the coder workspace the ability to sudo, so this is a workaround
  # see: https://github.com/Homebrew/install/blob/7e3a5202cd6d783a2464e387433c4c72acdb0f49/install.sh#L366
  touch /.dockerenv
  HOME="/home/${brew_user}" NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

cleanup_homebrew() {
  echo "Cleaning up..."
  echo "    Cache..."
  find "${HOMEBREW_CACHE}/" -mindepth 1 -maxdepth 1 -exec rm -rf {} \; || true
  echo "    Prefix..."
  find "${HOMEBREW_PREFIX}/" -mindepth 1 -maxdepth 1 -exec rm -rf {} \; || true
}

prepare_homebrew() {
  echo "Creating directories and setting permissions..."
  if [[ ! -d "${HOMEBREW_CACHE}" ]]; then
    echo "Creating cache directory..."
    mkdir -p "${HOMEBREW_CACHE}"
  fi
  chown -R ${brew_user}:root "${HOMEBREW_CACHE}"
  chown -R ${brew_user}:root $(dirname "${HOMEBREW_PREFIX}")
}

ensure_permissions() {
  local brew_user="$1"
  echo "Making brew installation available to both ${brew_user} user and root..."
  chown -R ${brew_user}:root $(dirname "${HOMEBREW_PREFIX}")
  chown -R ${brew_user}:root "${HOMEBREW_CACHE}"
  echo "Ensuring ${brew_user} user retains ownership of top level directories within their home..."
  chown ${brew_user}:${brew_user} /home/${brew_user}
  chown ${brew_user}:${brew_user} /home/${brew_user}/.cache
}

setup_homebrew() {
  local brew_user="coder"
  export HOMEBREW_CACHE="/home/${brew_user}/.cache/Homebrew"

  echo '------------------------------------------------------------'
  echo 'Checking for brew installation...'
  local brew_file_count=$(find "${HOMEBREW_PREFIX}" -maxdepth 3 -type f | wc -l)
  if [[ "${brew_file_count}" -gt "0" && -f "${HOMEBREW_PREFIX}/bin/brew" ]]; then
    echo 'Brew installation already exists... skipping.'
  else
    echo 'No existing brew installation, proceeding w/ installation...'
    echo '------------------------------------------------------------'
    echo 'Preparing for homebrew...'
    cleanup_homebrew 2>&1 | sed -E -n 's|^|    |p'
    prepare_homebrew 2>&1 | sed -E -n 's|^|    |p'
    echo '------------------------------------------------------------'
    echo 'Starting homebrew installation...'
    install_homebrew "${brew_user}" 2>&1 | sed -E -n 's|^|    |p'
  fi
  echo '------------------------------------------------------------'
  echo "Ensuring directory permissions..."
  ensure_permissions "${brew_user}" 2>&1 | sed -E -n 's|^|    |p'
  echo '------------------------------------------------------------'
  echo 'Done'
}

prepare_environment() {
  echo '------------------------------------------------------------'
  grep -v '^PATH=' /etc/environment > /tmp/environment.bak
  local existing_system_path="$(grep '^PATH=' /etc/environment | cut -d'=' -f2)"
  local updated_system_path="${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin:${existing_system_path}"
  echo PATH=${updated_system_path} >> /tmp/environment.bak
  sort /tmp/environment.bak > /etc/environment
  rm /tmp/environment.bak
  cat /etc/environment
  echo '------------------------------------------------------------'
  echo 'Done'
}

main() {
  echo "Setting up homebrew..."
  setup_homebrew | sed -E -n 's|^|    |p'
  echo
  echo "Setting up workspace environment variables..."
  prepare_environment | sed -E -n 's|^|    |p'
}

main
