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

  local home_bin_dir="${HOME}/.local/bin"
  mkdir -p $home_bin_dir

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
