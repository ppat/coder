module "coder-login" {
  source   = "registry.coder.com/modules/coder-login/coder"
  version  = "1.0.25"
  agent_id = coder_agent.main.id
}

# module "filebrowser" {
#   source   = "registry.coder.com/modules/filebrowser/coder"
#   version  = "1.0.23"
#   agent_id = coder_agent.main.id
# }
