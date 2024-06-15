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

  if [[ ! -f ${HOME}/.bashrc.optional ]]; then
    {
      # shellcheck disable=SC2016
      echo 'eval "$($FNM_ROOT/fnm env --shell bash --use-on-cd --fnm-dir $FNM_ROOT)"'
      # shellcheck disable=SC2016
      echo 'eval "$(starship init bash)"'
    } >> ${HOME}/.bashrc.optional
  fi
}

main() {
  initialize_shell_config
}

main
