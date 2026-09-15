#!/bin/bash
set -euo pipefail

state_dir="${HOME}/.local/state/dotfiles"
mkdir -p "${state_dir}"
rm -f "${state_dir}/applied" "${state_dir}/failed"
exec > >(/usr/bin/tee "${state_dir}/run.log") 2>&1
record_failure() {
  local status="$?"
  if (( status != 0 )); then
    printf '%s\n' "${status}" >"${state_dir}/failed"
  fi
}
trap record_failure EXIT

if [[ -z "${DOTFILES_URL}" ]]; then
  echo "no dotfiles repository configured"
else
  chezmoi_bin="${HOMEBREW_PREFIX}/bin/chezmoi"
  if [[ ! -x "${chezmoi_bin}" ]]; then
    "${HOMEBREW_PREFIX}/bin/brew" install chezmoi
  fi

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

  source_dir="$(${chezmoi_bin} source-path)"
  if [[ -d "${source_dir}/.git" ]]; then
    "${chezmoi_bin}" update --skip-secrets
  else
    mkdir -p "$(dirname "${source_dir}")"
    git clone -- "${DOTFILES_URL}" "${source_dir}"
    if [[ "${TEMPLATE_TEST_MODE}" == "true" ]]; then
      # The integration test verifies this template's Chezmoi orchestration;
      # repository-owned workstation bootstrap scripts are outside its scope.
      "${chezmoi_bin}" init --apply --skip-secrets --exclude=scripts
    else
      "${chezmoi_bin}" init --apply --skip-secrets
    fi
  fi
fi

touch "${state_dir}/applied"
/bin/bash /start-services.sh
