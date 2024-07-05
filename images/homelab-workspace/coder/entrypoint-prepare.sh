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
  local home_dir="/home/${username}"

  echo "- Modifying user..."
  usermod --home $home_dir --shell /bin/bash --login $username coder

  # allow coder user to sudo to so that they can run any system actions (such as using apt-get) within their workspace container.
  echo "- Enabling sudo"
  echo "${username} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/nopasswd
  echo
}

maintain_directories() {
  local username="$1"
  local home_dir="/home/${username}"

  echo "- Creating directories..."
  mkdir $home_dir
  mkdir $home_dir/.log/
  echo "- Updating directory permissions..."
  chown $username:coder $home_dir
  chown $username:coder $home_dir/.log/
  echo
}

main() {
  echo "Updating user: coder -> ${username}"
  update_user $USERNAME
  echo "Maintain required directories..."
  maintain_directories $USERNAME
  echo "Complete."
}

main
