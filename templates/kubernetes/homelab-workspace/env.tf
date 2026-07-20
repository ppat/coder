resource "coder_env" "welcome_message" {
  agent_id = coder_agent.main.id
  name     = "HOMEBREW_PREFIX"
  value    = local.homebrew_directory
}

resource "coder_env" "docker_host" {
  count = data.coder_parameter.enable_docker.value ? 1 : 0

  agent_id = coder_agent.main.id
  name     = "DOCKER_HOST"
  value    = "unix:///run/user/10001/docker.sock"
}
