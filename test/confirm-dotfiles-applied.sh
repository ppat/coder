#!/usr/bin/env bash
set -euo pipefail

check_dotfiles_status() {
  local workspace_name="$1"
  until coder ssh "${workspace_name}.main" -- test -f /home/coder/.local/state/dotfiles/applied; do
    if coder ssh "${workspace_name}.main" -- test -f /home/coder/.local/state/dotfiles/failed; then
      echo "::error::Dotfiles failed to apply. See run.log below."
      coder ssh "${workspace_name}.main" -- cat /home/coder/.local/state/dotfiles/run.log | sed 's/^/  /'
      exit 1
    fi
    sleep 5
  done
}

spotcheck_dotfiles_placement() {
  local workspace_name="$1"
  for file in /home/coder/.config/mise/config.toml /home/coder/.env; do
    echo "Spot-checking dotfiles placement: ${file}..."
    coder ssh "${workspace_name}.main" -- test -f "${file}" || (echo "::error::Dotfile ${file} is missing" && exit 1)
  done
}

confirm_dotfiles_applied() {
  local workspace_name="$1"
  check_dotfiles_status "${workspace_name}" | sed 's/^/  /'
  spotcheck_dotfiles_placement "${workspace_name}" | sed 's/^/  /'
}

export -f check_dotfiles_status
export -f spotcheck_dotfiles_placement
export -f confirm_dotfiles_applied
timeout 15m bash -c "sconfirm_dotfiles_applied ${1}"
