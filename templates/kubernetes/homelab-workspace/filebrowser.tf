module "filebrowser" {
  count         = (data.coder_parameter.enable_filebrowser.value == "true") ? data.coder_workspace.me.start_count : 0
  source        = "registry.coder.com/coder/filebrowser/coder"
  version       = "1.1.5"
  agent_id      = coder_agent.main.id
  folder        = "/home/coder"
  database_path = ".config/filebrowser.db"
}
