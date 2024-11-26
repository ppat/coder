#!/bin/bash
set -eo pipefail


install_pipx_packages() {
  local requirements_file="$1"

  # shellcheck disable=SC2013
  for t in $(grep -v '^#' $requirements_file); do
    pipx install ${t}
  done
}

main() {
  echo "Installing pipx packages..."
  install_pipx_packages /opt/pipx-package-requirements.txt 2>&1 | sed -E 's|^(.*)|    \1|g'
  echo "Installing ansible dependent apps..."
  pipx inject ansible-core --include-apps $(grep -v '^#' /opt/ansible-dependent-app-requirements.txt) 2>&1 | sed -E 's|^(.*)|    \1|g'
  echo "Installing ansible dependencies..."
  pipx inject ansible-core $(grep -v '^#' /opt/ansible-dependency-requirements.txt) 2>&1 | sed -E 's|^(.*)|    \1|g'
  echo "Installing ansible collections..."
  ansible-galaxy collection install -r /opt/ansible-collections-requirements.yaml 2>&1 | sed -E 's|^(.*)|    \1|g'
}

main
