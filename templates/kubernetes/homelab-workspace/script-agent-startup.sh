#!/bin/bash
set -eo pipefail


fetch_dotfiles() {
  local dotfiles_repo="$1"
  mkdir -p $HOME/code

  echo "Configuring env for git..."
  unset GIT_ASKPASS
  unset GIT_SSH_COMMAND
  local git_ssh_key="$HOME/.ssh/id_ed25519"
  if [[ -e "$git_ssh_key" ]]; then
    export 'GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i '$git_ssh_key'"'
  fi

  if [[ ! -d $HOME/code/dotfiles ]]; then
    echo "Cloning dotfiles repository..."
    cd $HOME/code
    git clone $dotfiles_repo 2>&1 | sed -E 's/^(.*)/    \1/g'
  else
    cd $HOME/code/dotfiles
    if [[ -z "$(git status -s --porcelain)" ]]; then
      echo "Updating dotfiles repository..."
      git fetch --prune 2>&1 | sed -E 's/^(.*)/    \1/g'
      git pull origin master --rebase 2>&1 | sed -E 's/^(.*)/    \1/g'
    else
      echo "Uncommitted changes preset in ~/code/dotfiles... cannot update!" >&2
      return 1
    fi
  fi
}

install_dotfiles() {
  echo "Installing dotfiles..."
  cd $HOME/code/dotfiles
  ./install.sh | sed -E 's/^(.*)/    \1/g'
}

setup_dotfiles() {
  if [[ -z "${DOTFILES_REPOSITORY}" || "${DOTFILES_REPOSITORY}" == "none" ]]; then
    echo "Dotfiles repository has not been configured. Skipping..."
    return
  fi
  echo "Fetching dotfiles..."
  if fetch_dotfiles "${DOTFILES_REPOSITORY}" | sed -E 's/^(.*)/    \1/g'; then
    install_dotfiles
  elif [[ -e "$HOME/code/dotfiles/install.sh" ]]; then
    echo "Updating dotfiles to latest failed due to uncommitted changes, so running install on pre-existing clone..." >&2
    install_dotfiles
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
