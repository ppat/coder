#!/bin/bash
set -eo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Should be run as root"
  exit 1
fi

USERNAME=""
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --username)
      USERNAME="$2"; shift;
      if [[ -z "${USERNAME}" ]]; then
        echo "--username is required"
        exit 1
      fi
      ;;
    *) echo "Unknown parameter passed: $1"; echo; exit 1 ;;
  esac
  shift
done
if [[ -z "${USERNAME}" ]]; then
  echo "--username is required"
  exit 1
fi

update_user() {
  local username="$1"

  echo "Updating user: coder -> ${username}"
  echo "- Modifying user"
  usermod --home /home/${username} --shell /bin/bash --login ${username} coder
  echo "- Updating directory permissions"
  mkdir -p /home/${username}/.var/
  chown ${username}:coder /home/${username}
  chown ${username}:coder /home/${username}/.var

  # allow coder user to sudo to so that they can run any system actions (such as using apt-get) within their workspace container.
  echo "- Enabling sudo"
  echo "${username} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/nopasswd

  echo "- Complete."
  echo
}

main() {
  update_user ${USERNAME}

  echo
}

main
