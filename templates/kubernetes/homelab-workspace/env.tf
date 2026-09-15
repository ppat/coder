resource "coder_env" "welcome_message" {
  agent_id = coder_agent.main.id
  name     = "HOMEBREW_PREFIX"
  value    = local.homebrew_directory
}

resource "coder_env" "dotfiles_url" {
  agent_id = coder_agent.main.id
  name     = "DOTFILES_URL"
  value    = local.validated_dotfiles_url
}

resource "coder_env" "dotfiles_owner_name" {
  agent_id = coder_agent.main.id
  name     = "DOTFILES_OWNER_NAME"
  value    = data.coder_workspace_owner.me.full_name
}

resource "coder_env" "dotfiles_owner_email" {
  agent_id = coder_agent.main.id
  name     = "DOTFILES_OWNER_EMAIL"
  value    = data.coder_workspace_owner.me.email
}

resource "coder_env" "dotfiles_coder_username" {
  agent_id = coder_agent.main.id
  name     = "DOTFILES_CODER_USERNAME"
  value    = data.coder_workspace_owner.me.name
}

resource "coder_env" "service_commands" {
  agent_id = coder_agent.main.id
  name     = "SUPERVISOR_SERVICE_COMMANDS"
  value    = jsonencode(local.validated_service_commands)
}

resource "coder_env" "service_count" {
  agent_id = coder_agent.main.id
  name     = "SUPERVISOR_SERVICE_COUNT"
  value    = tostring(length(local.validated_service_commands))
}

resource "coder_env" "template_test_mode" {
  agent_id = coder_agent.main.id
  name     = "TEMPLATE_TEST_MODE"
  value    = tostring(var.test_mode)
}

# The switch that arms the memory watchdog. "observe" measures and records what
# it would have done; "enforce" kills any process that has been over its share of
# the 2048 MiB VS Code envelope for ten minutes and had previously been seen
# inside it.
#
# Set from a mutable workspace parameter rather than hardcoded here, because it
# is the one control that decides whether the watchdog may signal anything, and
# because turning it off has to be a parameter change rather than a code change
# on a bad day. The shares are constants that add up to the envelope and do not
# vary with pod size, so this value does not have to be reconsidered per pod
# size either.
resource "coder_env" "memory_watchdog_mode" {
  agent_id = coder_agent.main.id
  name     = "WATCHDOG_MODE"
  value    = local.validated_watchdog_mode
}
