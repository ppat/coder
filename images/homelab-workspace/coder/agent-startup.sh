#!/bin/bash
set -eo pipefail


DOTFILES_REPOSITORY="git@github.com:ppat/dotfiles.git"

fetch_dotfiles() {
  if [[ ! -d $HOME/code/dotfiles ]]; then
    echo "Cloning dotfiles repository..."
    cd $HOME/code
    git clone $DOTFILES_REPOSITORY 2>&1 | sed -E 's/^(.*)/    \1/g'
  elif [[ -z "$(git status -s --porcelain)" ]]; then
    echo "Updating dotfiles repository..."
    cd $HOME/code/dotfiles
    git fetch --prune 2>&1 | sed -E 's/^(.*)/    \1/g'
    git pull origin master --rebase 2>&1 | sed -E 's/^(.*)/    \1/g'
  else
    echo "Uncommitted changes preset in ~/code/dotfiles... cannot update!" >&2
    exit 1
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
  echo "Fetching dotfiles..."
  if fetch_dotfiles | sed -E 's/^(.*)/    \1/g'; then
    echo "Installing dotfiles..."
    cd $HOME/code/dotfiles
    ./install.sh | sed -E 's/^(.*)/    \1/g'
  else
    echo "Skipping dotfiles install as fetching dotfiles failed!" >&2
  fi
  echo "--------------------------------------------------------------------------------------"
  echo "Done."
}

main | sed -E 's/^(.*)/agent-startup: \1/g'
