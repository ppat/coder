#!/bin/bash
set -eo pipefail


main() {
  echo '------------------------------------------------------------'
  echo 'Running apt-get update...'
  apt-get update 2>&1 | pr -t -o 4
  echo 'Running apt-file update...'
  apt-file update 2>&1 | pr -t -o 4
  echo '------------------------------------------------------------'
  echo 'Installing additinal apt packages...'
  echo "    Packages: $SYSTEM_PACKAGES"
  echo
  if [[ "$SYSTEM_PACKAGES" != "NONE" ]]; then
    DEBIAN_FRONTEND="noninteractive" apt-get install --no-install-recommends -yq $SYSTEM_PACKAGES 2>&1 | pr -t -o 4
  fi
  echo '------------------------------------------------------------'
  echo 'Rsyncing (etc, usr, var) to /updated...'
  rsync -aH --stats /etc /usr /var /updated 2>&1 | pr -t -o 4
  echo '------------------------------------------------------------'
  echo 'Updated system size...'
  du -h -d 1 /updated 2>&1 | pr -t -o 4
  echo '------------------------------------------------------------'
  echo 'Done'
}

main
