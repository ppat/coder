#!/bin/bash
set -eo pipefail


main() {
  if [[ ! -s ~/.bashrc ]]; then
    echo "Setting up starter bash rc scripts from /etc/skel..."
    cp /etc/skel/.bashrc ~/.bashrc
    cp /etc/skel/.profile ~/.profile
    echo 'set -o allexport; source /etc/environment; set +o allexport' >> ~/.bashrc
    echo '------------------------------------------------------------'
  fi
  echo 'Done'
}

main
