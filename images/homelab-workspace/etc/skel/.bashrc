# shellcheck disable=SC2148
# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc) for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# save bash history when multiple shell sessions are open
# see: https://unix.stackexchange.com/a/48113
export HISTCONTROL=ignoredups:erasedups  # no duplicate entries
export HISTSIZE=100000                   # big big history
export HISTFILESIZE=100000               # big big history
shopt -s histappend                      # append to history, don't overwrite it
export PROMPT_COMMAND="history -a; history -c; history -r; $PROMPT_COMMAND"  # Save & reload history after each command

# load system environment variables
set -o allexport; source /etc/environment; set +o allexport

# source bash shell defaults
. /etc/bashrc.defaults
. /etc/bash_aliases.defaults
. /etc/bash_completion.defaults

# load user environment variables
set -o allexport; source $HOME/.env; set +o allexport

# add injected coder CLI to the PATH
CODER_CLI_LOCATION=$(dirname $(find /tmp/coder* -name coder -type f -executable))
if [[ ! -z "${CODER_CLI_LOCATION}" ]]; then
  export PATH="${PATH}:${CODER_CLI_LOCATION}"
fi

# source bash shell personalizations
PERSONALIZED_BASH_CONFIGURATIONS="$(find ${HOME} -mindepth 1 -maxdepth 1 -type f -name '.bash*' -not -name .bashrc -not -name .bash_history -not -name .bash_logout)"
for file in ${PERSONALIZED_BASH_CONFIGURATIONS}; do
  . ${file}
done

unset GIT_ASKPASS
unset GIT_SSH_COMMAND
