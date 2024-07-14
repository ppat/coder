#!/bin/bash
set -eo pipefail

K="/usr/local/sbin/kubectl"
PLUGIN_LIST_FILE="$HOME/.krew_plugins"

update_index() {
  echo "Updating index..."
  $K krew update
}

upgrade_existing_plugins() {
  echo "Upgrading existing plugins..."
  $K krew upgrade
}

install_plugin_if_not_exists() {
  local plugin="$1"
  if $K krew list | grep '^'$plugin'$' >/dev/null; then
    echo $plugin is already installed.
  else
    $K krew install --no-update-index $plugin
  fi
}

manage_krew_plugins() {
  echo "Loading required krew plugins from $PLUGIN_LIST_FILE..."
  local plugins="$(cat $PLUGIN_LIST_FILE | grep -v '^#')"
  echo
  update_index
  echo
  echo "Installing plugins..."
  for p in $plugins; do
    install_plugin_if_not_exists $p | pr -t -o 4
  done
  echo
  upgrade_existing_plugins
  echo "Done"
  echo
}

main() {
  echo "Maintaining kubectl plugins via krew..."
  if [[ ! -f $PLUGIN_LIST_FILE ]]; then
    echo "Krew plugin list file does not exist. Add any plugins you want installed to $PLUGIN_LIST_FILE."
    touch $PLUGIN_LIST_FILE
    echo
  fi
  export PATH="$HOME/.krew/bin:$PATH"
  manage_krew_plugins
}

main
