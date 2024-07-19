#!/bin/bash
set -euo pipefail


install_rust() {
  local rust_version="$1"
  if [[ ! -d $HOME/.rustup/toolchains/${rust_version:?}-$(arch)-unknown-linux-gnu ]]; then
    echo "$HOME/.rustup is not present, installing rust $rust_version ..."
    rustup default ${rust_version}
  else
    echo "$HOME/.rustup is already present, skipping rust installation."
  fi
}

install_node() {
  local node_version="$1"
  if [[ ! -d $HOME/.fnm/node-versions/v${node_version:?} ]]; then
    eval "$(fnm env --shell bash --use-on-cd --fnm-dir $HOME/.fnm)"
    fnm install ${node_version}
    fnm use ${node_version}
    fnm default --fnm-dir $HOME/.fnm ${node_version}
    npm config set update-notifier false
    npm config set fund false
    npm config set loglevel error
  else
    echo "Node version $node_version already exists, skipping install."
  fi
}

install_npm_packages() {
  local npm_package_json="$1"
  eval "$(fnm env --shell bash --use-on-cd --fnm-dir $HOME/.fnm)"
  for i in $(jq -r '.devDependencies | to_entries | map([.key, .value] | join("@")) | .[]' ${npm_package_json:?}); do
    echo "Installing $i..."
    npm install --global --no-audit $i 2>&1 | sed -E 's|^(.*)|    \1|g'
    echo
  done
}

main() {
  echo "Starting..."
  echo "--------------------------------------------------------------------------------------"
  echo "Loading environment..."
  set -o allexport
  source /etc/environment
  set +o allexport
  echo "--------------------------------------------------------------------------------------"
  echo "Installing rust..."
  install_rust ${RUST_VERSION:?} 2>&1 | sed -E 's|^(.*)|    \1|g'
  echo "--------------------------------------------------------------------------------------"
  echo "Installing node..."
  install_node ${NODE_VERSION:?} 2>&1 | sed -E 's|^(.*)|    \1|g'
  echo
  echo "Installing npm packages..."
  install_npm_packages /opt/fnm/npm-packages.json 2>&1 | sed -E 's|^(.*)|    \1|g'
  echo "--------------------------------------------------------------------------------------"
  echo "Maintaining krew plugins..."
  $(dirname ${0})/init-krew-plugins.sh 2>&1 | sed -E 's|^(.*)|    \1|g'
  echo "--------------------------------------------------------------------------------------"
  echo "Done."
}

main | sed -E 's|^(.*)|init-background: \1|g'
