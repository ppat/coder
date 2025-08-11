resource "coder_env" "welcome_message" {
  agent_id = coder_agent.main.id
  name     = "HOMEBREW_PREFIX"
  value    = local.homebrew_directory
}
