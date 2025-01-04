#!/bin/bash
set -eo pipefail


fetch_dotfiles() {
  local dotfiles_repo="$1"
  mkdir -p $HOME/code

  echo "fetch:dotfiles | Configuring env for git..."
  unset GIT_ASKPASS
  unset GIT_SSH_COMMAND
  local git_ssh_key="$HOME/.ssh/id_ed25519"
  if [[ -e "$git_ssh_key" ]]; then
    export GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i ${git_ssh_key}"
  fi

  if [[ ! -d $HOME/code/dotfiles ]]; then
    echo "fetch:dotfiles | Cloning dotfiles repository..."
    cd $HOME/code
    git clone $dotfiles_repo 2>&1 | sed -E 's/^(.*)/fetch:dotfiles |    \1/g'
  else
    cd $HOME/code/dotfiles
    if [[ -z "$(git status -s --porcelain)" ]]; then
      echo "Updating dotfiles repository..."
      git fetch --prune 2>&1 | sed -E 's/^(.*)/fetch:dotfiles |    \1/g'
      git pull origin master --rebase 2>&1 | sed -E 's/^(.*)/fetch:dotfiles |    \1/g'
    else
      echo "fetch:dotfiles | Uncommitted changes preset in ~/code/dotfiles... cannot update!" >&2
      if [[ -e "$HOME/code/dotfiles/install.sh" ]]; then
        echo "fetch:dotfiles | Will use pre-existing clone..." >&2
      else
        echo "fetch:dotfiles | Skipping dotfiles install as fetching dotfiles failed!" >&2
      fi
    fi
  fi
}

main() {
  if [[ -z "${DOTFILES_REPOSITORY}" || "${DOTFILES_REPOSITORY}" == "none" ]]; then
    echo "fetch:dotfiles | Dotfiles repository has not been configured. Skipping..."
    return
  fi
  fetch_dotfiles "${DOTFILES_REPOSITORY}"
  if [[ -e "$HOME/code/dotfiles/install.sh" ]]; then
    cd $HOME/code/dotfiles
    ./install.sh
  fi
}

main
