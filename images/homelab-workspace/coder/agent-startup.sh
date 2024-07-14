#!/bin/bash
set -eo pipefail

initialize_shell_config() {
  # shellcheck disable=SC2044
  for skel in $(find /etc/skel/ -type f); do
    target="${HOME}/$(basename ${skel})"
    if [[ ! -f "$target" ]]; then
      cp $skel $target
    fi
  done
}

create_log_file() {
  local prefix="$1"
  local log="$HOME/.log/${prefix}.$(date +%Y%m%d_%H%M%S).log"
  sudo touch $log
  sudo chown $USER:coder $log
  echo $log
}

install_rust() {
  if [[ ! -d ~/.rustup/toolchains/${RUST_VERSION:?}-$(arch)-unknown-linux-gnu ]]; then
    echo "$HOME/.rustup is not present, installing rust $RUST_VERSION ..."
    rustup default ${RUST_VERSION} 2>&1
  else
    echo "$HOME/.rustup is already present, skipping rust installation."
  fi
}

install_node() {
  if [[ ! -d $HOME/.fnm/node-versions/v${NODE_VERSION:?} ]]; then
    eval "$(fnm env --shell bash --use-on-cd --fnm-dir $HOME/.fnm)"
    fnm install ${NODE_VERSION}
    fnm use ${NODE_VERSION}
    fnm default --fnm-dir $HOME/.fnm ${NODE_VERSION}
    npm config set update-notifier false
    npm config set fund false
    npm config set loglevel error
  else
    echo "Node version $NODE_VERSION already exists, skipping install."
  fi
}

install_npm_packages() {
  eval "$(fnm env --shell bash --use-on-cd --fnm-dir $HOME/.fnm)"
  for i in $(jq -r '.devDependencies | to_entries | map([.key, .value] | join("@")) | .[]' /opt/fnm/npm-packages.json); do
    npm install --global --no-audit $i
  done
}

install_starship() {
  if [[ ! -f $home_bin_dir/starship ]]; then
    echo "Starship binary not found, installing..."
    curl -sS https://starship.rs/install.sh | sh -s - --bin-dir $home_bin_dir -y
  else
    echo "Starship binary already exists, skipping install."
  fi
}

main() {
  echo "Starting..."
  echo "--------------------------------------------------------------------------------------"
  echo "Loading environment..."
  set -o allexport
  source /etc/environment
  set +o allexport
  echo "--------------------------------------------------------------------------------------"
  echo "Initialize shell configuration from /etc/skel..."
  initialize_shell_config | pr -t -o 4
  echo "--------------------------------------------------------------------------------------"
  echo "Creating $HOME/.local/bin..."
  local home_bin_dir="${HOME}/.local/bin"
  mkdir -p $home_bin_dir
  echo "--------------------------------------------------------------------------------------"
  echo "Installing rust..."
  install_rust | pr -t -o 4
  echo "--------------------------------------------------------------------------------------"
  echo "Installing node..."
  install_node | pr -t -o 4
  echo "Installing npm packages..."
  install_npm_packages | pr -t -o 4
  echo "--------------------------------------------------------------------------------------"
  echo "Installing starship..."
  install_starship | pr -t -o 4
  echo "--------------------------------------------------------------------------------------"
  echo "Maintaining krew plugins (in background)..."
  local krew_log="$(create_log_file "krew-plugins")"
  $(dirname ${0})/maintain-krew-plugins.sh >$krew_log 2>&1  &
  echo "See log: $krew_log"
  echo "--------------------------------------------------------------------------------------"
  echo "Done."
}

main | sed -E 's/^(.*)/agent-startup: \1/g'
