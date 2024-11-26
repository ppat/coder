#!/bin/bash
set -eo pipefail


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
  for i in $(jq -r '.dependencies | to_entries | map([.key, .value] | join("@")) | .[]' ${npm_package_json:?}); do
    echo "Installing $i..."
    npm install --global --no-audit $i 2>&1 | sed -E 's|^(.*)|    \1|g'
    echo
  done
}

main() {
  echo "Installing node..."
  install_node ${NODE_VERSION:?} 2>&1 | sed -E 's|^(.*)|    \1|g'
  echo
  echo "Installing npm packages..."
  install_npm_packages /opt/fnm/npm-packages.json 2>&1 | sed -E 's|^(.*)|    \1|g'
}

main
