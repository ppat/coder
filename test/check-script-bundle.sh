#!/usr/bin/env bash
set -euo pipefail

check_placement() {
  workspace_name="$1"
  file_executable="$2"
  shift 2
  # shellcheck disable=SC2124
  files=$@
  for file in ${files}; do
    echo "Checking script: ${file}..."
    if [[ "${file_executable}" == *"yes"* ]]; then
      coder ssh "${workspace_name}.main" -- test -x "/scripts/${file}" || (echo "::error::File ${file} is missing or not executable" && exit 1)
    else
      coder ssh "${workspace_name}.main" -- test -f "/scripts/${file}" || (echo "::error::File ${file} is missing" && exit 1)
    fi
  done
}

echo "Checking script bundle presence within workspace..."
# shellcheck disable=SC2044
scripts=$(for f in $(find templates/kubernetes/homelab-workspace/scripts -type f -not -name '*test*'); do basename $f; done | sort)
check_placement "$1" "yes" ${scripts} workspace-init.sh | sed 's/^/  /'
echo

echo "Checking config bundle presence within workspace..."
# shellcheck disable=SC2044
configs=$(for f in $(find templates/kubernetes/homelab-workspace/config -type f -not -name '*test*'); do basename $f; done | sort)
check_placement "$1" "no" ${configs} | sed 's/^/  /'
echo
