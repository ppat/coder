#!/bin/bash
set -eo pipefail


fetch_dotfiles() {
  local dotfiles_repo="$1"
  mkdir -p $HOME/code
  if [[ ! -d $HOME/code/dotfiles ]]; then
    echo "Cloning dotfiles repository..."
    cd $HOME/code
    git clone $dotfiles_repo 2>&1 | sed -E 's/^(.*)/    \1/g'
  elif [[ -z "$(git status -s --porcelain)" ]]; then
    echo "Updating dotfiles repository..."
    cd $HOME/code/dotfiles
    git fetch --prune 2>&1 | sed -E 's/^(.*)/    \1/g'
    git pull origin master --rebase 2>&1 | sed -E 's/^(.*)/    \1/g'
  else
    echo "Uncommitted changes preset in ~/code/dotfiles... cannot update!" >&2
    return 1
  fi
}

setup_dotfiles() {
  if [[ -z "${DOTFILES_REPOSITORY}" ]]; then
    echo "Dotfiles repository has not been configured. Skipping..."
    return
  fi
  echo "Fetching dotfiles..."
  if fetch_dotfiles "${DOTFILES_REPOSITORY}" | sed -E 's/^(.*)/    \1/g'; then
    echo "Installing dotfiles..."
    cd $HOME/code/dotfiles
    ./install.sh | sed -E 's/^(.*)/    \1/g'
  else
    echo "Skipping dotfiles install as fetching dotfiles failed!" >&2
  fi
}

main() {
  echo "Starting..."
  echo "--------------------------------------------------------------------------------------"
  echo "Loading environment..."
  set -o allexport
  source /etc/environment
  set +o allexport
  echo "--------------------------------------------------------------------------------------"
  echo "Setting up dotfiles..."
  setup_dotfiles | sed -E 's/^(.*)/    \1/g'
  echo "--------------------------------------------------------------------------------------"
  echo "Done."
}

main | sed -E 's/^(.*)/agent-startup: \1/g'
