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

  set -o allexport
  source /etc/environment
  set +o allexport

  local home_bin_dir="${HOME}/.local/bin"
  mkdir -p $home_bin_dir

  if [[ ! -d $HOME/.rustup && ! -z "$RUST_VERSION" ]]; then
    echo "$HOME/.rustup is not present, installing rust $RUST_VERSION ..."
    rustup default ${RUST_VERSION}
  else
    echo "$HOME/.rustup is already present, skipping rust installation."
  fi
  if [[ ! -f $home_bin_dir/starship ]]; then
    echo "Starship binary not found, installing..."
    curl -sS https://starship.rs/install.sh | sh -s - --bin-dir $home_bin_dir -y
  else
    echo "Starship binary already exists, skipping install."
  fi
  if [[ ! -f ${HOME}/.bashrc.optional ]]; then
    {
      # shellcheck disable=SC2016
      echo 'eval "$($FNM_ROOT/fnm env --shell bash --use-on-cd --fnm-dir $FNM_ROOT)"'
      # shellcheck disable=SC2016
      echo 'eval "$(${HOME}/.local/bin/starship init bash)"'
    } >> ${HOME}/.bashrc.optional
  fi
}

main() {
  echo "agent-startup-script: Starting..."
  initialize_shell_config
  echo "agent-startup-script: Done."
}

main
