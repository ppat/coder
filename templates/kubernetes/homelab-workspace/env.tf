resource "coder_env" "welcome_message" {
  agent_id = coder_agent.main.id
  name     = "HOMEBREW_PREFIX"
  value    = local.homebrew_directory
}

# Rootful dockerd listens on the default /var/run/docker.sock; the coder user
# reaches it via the `docker` group (see script-workspace-entrypoint.sh), so no
# DOCKER_HOST override is needed.
