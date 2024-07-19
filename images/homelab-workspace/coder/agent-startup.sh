#!/bin/bash
set -eo pipefail

initialize_shell_config() {
  # shellcheck disable=SC2044
  for skel in $(find /etc/skel/ -type f); do
    skel_type="$(basename ${skel})"
    target="${HOME}/${skel_type}"
    if [[ ! -f "$target" ]]; then
      echo "${skel_type}: Copying from $skel to $target..."
      cp $skel $target
    else
      echo "${skel_type}: already exists as $target."
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
  initialize_shell_config | sed -E 's/^(.*)/    \1/g'
  echo "--------------------------------------------------------------------------------------"
  echo "Creating $HOME/.local/bin..."
  local home_bin_dir="${HOME}/.local/bin"
  mkdir -p $home_bin_dir
  echo "--------------------------------------------------------------------------------------"
  echo "Installing starship..."
  install_starship | sed -E 's/^(.*)/    \1/g'
  echo "--------------------------------------------------------------------------------------"
  BACKGROUND_INIT_LOG="$(create_log_file "init-background")"
  echo "Starting background initialization for long running tasks..."
  stdbuf -oL nohup $(dirname ${0})/init-background.sh &> ${BACKGROUND_INIT_LOG} &
  echo "See log: ${BACKGROUND_INIT_LOG}"
  echo "--------------------------------------------------------------------------------------"
  echo "Done."
}

main | sed -E 's/^(.*)/agent-startup: \1/g'
