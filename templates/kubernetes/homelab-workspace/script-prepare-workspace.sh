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

setup_homebrew() {
  local brew_user="coder"
  echo '------------------------------------------------------------'
  echo 'Checking for brew installation...'
  local brew_file_count=$(find "${HOMEBREW_PREFIX}" -maxdepth 3 -type f | wc -l)
  if [[ "${brew_file_count}" -gt "0" ]]; then
    echo 'Brew installation already exists... skipping.'
  else
    echo 'No existing brew installation, proceeding w/ installation...'
    install_homebrew "${brew_user}" 2>&1 | sed -E -n 's|^|    |p'
  fi
  echo '------------------------------------------------------------'
  echo "Making brew installation available to ${brew_user} user..."
  chown -R ${brew_user}:root $(dirname "${HOMEBREW_PREFIX}")
  chown -R ${brew_user}:root "/home/${brew_user}/.cache/Homebrew"
  echo '------------------------------------------------------------'
  echo 'Done'
}

setup_system_packages() {
  echo '------------------------------------------------------------'
  echo 'Running apt-get update...'
  apt-get update 2>&1 | sed -E -n 's|^|    |p'
  echo 'Running apt-file update...'
  apt-file update 2>&1 | sed -E -n 's|^|    |p'
  echo '------------------------------------------------------------'
  echo 'Installing additinal apt packages...'
  echo "    Packages: $SYSTEM_PACKAGES"
  echo
  if [[ "$SYSTEM_PACKAGES" != "NONE" ]]; then
    DEBIAN_FRONTEND="noninteractive" apt-get install --no-install-recommends -yq $SYSTEM_PACKAGES 2>&1 | sed -E -n 's|^|    |p'
  fi
  echo '------------------------------------------------------------'
  echo 'Rsyncing (etc, usr, var) to /updated...'
  rsync -aH --stats /etc /usr /var /updated 2>&1 | sed -E -n 's|^|    |p'
  echo '------------------------------------------------------------'
  echo 'Updated system size...'
  du -h -d 1 /updated 2>&1 | sed -E -n 's|^|    |p'
  echo '------------------------------------------------------------'
  echo 'Done'
}

main() {
  echo "Setting up system packages..."
  setup_system_packages | sed -E -n 's|^|    |p'
  echo "Setting up homebrew..."
  setup_homebrew | sed -E -n 's|^|    |p'
}

main
