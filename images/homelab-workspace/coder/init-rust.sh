#!/bin/bash
set -eo pipefail


install_rust() {
  local rust_version="$1"
  if [[ ! -d $HOME/.rustup/toolchains/${rust_version:?}-$(arch)-unknown-linux-gnu ]]; then
    echo "$HOME/.rustup is not present, installing rust $rust_version ..."
    rustup default ${rust_version}
  else
    echo "$HOME/.rustup is already present, skipping rust installation."
  fi
}

main() {
  echo "Installing rust..."
  install_rust ${RUST_VERSION:?} 2>&1 | sed -E 's|^(.*)|    \1|g'
}

main
