#!/bin/bash
set -euo pipefail

ENV_VARS_FILE="/home/coder/.env.pod"
STATE_DIR="${HOME}/.local/state/dotfiles"
mkdir -p "${STATE_DIR}"
rm -f "${STATE_DIR}/applied" "${STATE_DIR}/failed"
exec > >(/usr/bin/tee "${STATE_DIR}/run.log") 2>&1
record_failure() {
  local status="$?"
  if (( status != 0 )); then
    printf '%s\n' "${status}" >"${STATE_DIR}/failed"
  fi
}
trap record_failure EXIT

install_chezmoi_if_needed() {
  chezmoi_bin="${HOMEBREW_PREFIX}/bin/chezmoi"
  if [[ ! -x "${chezmoi_bin}" ]]; then
    "${HOMEBREW_PREFIX}/bin/brew" install chezmoi
  fi
}

configure_chezmoi_if_needed() {
  config_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/chezmoi"
  config_file="${config_dir}/chezmoi.toml"
  if [[ ! -e "${config_file}" ]]; then
    mkdir -p "${config_dir}"
    escape_toml() {
      local value="${1//\\/\\\\}"
      printf '%s' "${value//\"/\\\"}"
    }
    {
      printf '[data]\n'
      printf 'name = "%s"\n' "$(escape_toml "${DOTFILES_OWNER_NAME}")"
      printf 'email = "%s"\n' "$(escape_toml "${DOTFILES_OWNER_EMAIL}")"
      printf 'coderUsername = "%s"\n' "$(escape_toml "${DOTFILES_CODER_USERNAME}")"
      printf 'bwsAccessToken = ""\n'
    } >"${config_file}"
  fi
}

run_chezmoi() {
  chezmoi_bin="${HOMEBREW_PREFIX}/bin/chezmoi"
  source_dir="$(${chezmoi_bin} source-path)"

  if [[ -f "${ENV_VARS_FILE}" ]]; then
    set -a; source "${ENV_VARS_FILE}"; set +a
  fi
  if [[ -d "${source_dir}/.git" ]]; then
    "${chezmoi_bin}" update --skip-secrets
  else
    mkdir -p "$(dirname "${source_dir}")"
    git clone -- "${DOTFILES_URL}" "${source_dir}"
    if [[ "${SKIP_DOTFILES_SCRIPTS}" == "true" ]]; then
      # The integration test verifies this template's Chezmoi orchestration;
      # repository-owned workstation bootstrap scripts are outside its scope.
      "${chezmoi_bin}" init --apply --skip-secrets --exclude=scripts
    else
      "${chezmoi_bin}" init --apply --skip-secrets
    fi
  fi
}

if [[ -z "${DOTFILES_URL}" ]]; then
  echo "no dotfiles repository configured"
else
  install_chezmoi_if_needed
  configure_chezmoi_if_needed
  run_chezmoi
fi

touch "${STATE_DIR}/applied"
