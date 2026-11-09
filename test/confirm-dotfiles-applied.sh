#!/usr/bin/env bash
set -euo pipefail

check_dotfiles_status() {
  local workspace_name="$1"
  # Expand the positional parameter inside the runner-owned polling shell.
  # shellcheck disable=SC2016
  timeout 15m bash -c \
    'until coder ssh "$1" -- test -f /home/coder/.local/state/dotfiles/applied; do
      if coder ssh "$1" -- test -f /home/coder/.local/state/dotfiles/failed; then
        coder ssh "$1" -- cat /home/coder/.local/state/dotfiles/run.log
        exit 1
      fi
      sleep 5
    done' _ "${workspace_name}.main"
}

spotcheck_dotfiles_placement() {
  local workspace_name="$1"
  for file in /home/coder/.config/mise/config.toml /home/coder/.env; do
    echo "Spot-checking dotfiles placement: ${file}..."
    coder ssh "${workspace_name}.main" -- test -f "${file}" || (echo "::error::Dotfile ${file} is missing" && exit 1)
  done
}

WORKSPACE_NAME="$1"
check_dotfiles_status "${WORKSPACE_NAME}" | sed 's/^/  /'
echo
spotcheck_dotfiles_placement "${WORKSPACE_NAME}" | sed 's/^/  /'
echo
