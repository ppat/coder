#!/bin/bash
set -eo pipefail

main() {
  echo '------------------------------------------------------------'
  echo 'Running apt-get update...'
  apt-get update 2>&1 | pr -t -o 4
  echo 'Running apt-file update...'
  apt-file update 2>&1 | pr -t -o 4
  echo '------------------------------------------------------------'
  echo "SYSTEM_PACKAGES=|$SYSTEM_PACKAGES|"
  echo '------------------------------------------------------------'
  ls -al /
  echo '------------------------------------------------------------'
}

main
