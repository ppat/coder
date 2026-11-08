#!/usr/bin/env bash
set -euo pipefail

check_dotfiles_status() {
  workspace_name="$1"
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
  workspace_name="$1"
  for file in /home/coder/.config/mise/config.toml /home/coder/.env; do
    echo "Spot-checking dotfiles placement: ${file}..."
    coder ssh "${workspace_name}.main" -- test -f "${file}" || (echo "::error::Dotfile ${file} is missing" && exit 1)
  done
}

echo "Checking dotfiles run completion status..."
check_dotfiles_status "$1" | sed 's/^/  /'
echo

echo "Spot-checking dotfiles placement..."
spotcheck_dotfiles_placement "$1" | sed 's/^/  /'
echo
