#!/bin/bash
set -euo pipefail

main() {
  echo "Starting..."
  echo "--------------------------------------------------------------------------------------"
  echo "Loading environment..."
  set -o allexport
  source /etc/environment
  set +o allexport
  echo "--------------------------------------------------------------------------------------"
  echo "Setting up rust..."
  $(dirname ${0})/init-rust.sh 2>&1 | sed -E 's|^(.*)|    \1|g'
  echo "--------------------------------------------------------------------------------------"
  echo "Setting up node and node packages..."
  $(dirname ${0})/init-node.sh 2>&1 | sed -E 's|^(.*)|    \1|g'
  echo "--------------------------------------------------------------------------------------"
  echo "Setting up python packages..."
  $(dirname ${0})/init-python.sh 2>&1 | sed -E 's|^(.*)|    \1|g'
  echo "--------------------------------------------------------------------------------------"
  echo "Installing packages from github-releases..."
  $(dirname ${0})/install-from-github-release.sh /opt/packages-github-releases.yaml $HOME/.local/bin
  echo "--------------------------------------------------------------------------------------"
  echo "Maintaining krew plugins..."
  $(dirname ${0})/init-krew-plugins.sh 2>&1 | sed -E 's|^(.*)|    \1|g'
  echo "--------------------------------------------------------------------------------------"
  echo "Done."
}

main | sed -E 's|^(.*)|init-background: \1|g'
