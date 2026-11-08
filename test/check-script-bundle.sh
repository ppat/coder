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

WORKSPACE_NAME="$1"
SCRIPT_DIR="$2"
echo "Checking script bundle presence within workspace..."
scripts=$(find "${SCRIPT_DIR}/scripts" -type f -not -name '*test*' -exec basename {} + | sort)
check_placement "${WORKSPACE_NAME}" "yes" ${scripts} workspace-init.sh | sed 's/^/  /'
echo

echo "Checking config bundle presence within workspace..."
configs=$(find "${SCRIPT_DIR}/config" -type f -not -name '*test*' -exec basename {} + | sort)
check_placement "${WORKSPACE_NAME}" "no" ${configs} | sed 's/^/  /'
echo
