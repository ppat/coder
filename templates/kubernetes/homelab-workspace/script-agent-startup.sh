#!/bin/bash
set -eo pipefail


main() {
  echo '------------------------------------------------------------'
  echo 'Re-locating secrets from mounted location to their destinations...'
  if [[ ! -f $HOME/.ssh/id_ed25519 ]]; then
    if [[ -f $HOME/.secret/id_ed25519 ]]; then
      mkdir -p $HOME/.ssh
      cp $HOME/.secret/id_ed25519* $HOME/.ssh/
      chmod 600 $HOME/.ssh/id_*
    fi
  fi

  if [[ ! -d $HOME/.kube/conf.d ]]; then
    mkdir -p $HOME/.kube/conf.d
    if [[ -f $HOME/.secret/kubeconfig_homelab ]]; then
      cp $HOME/.secret/kubeconfig_* $HOME/.kube/conf.d/
      chmod 600 $HOME/.kube/conf.d/kubeconfig_*
    fi
  fi
  echo '------------------------------------------------------------'
  echo 'Done'
}

main
