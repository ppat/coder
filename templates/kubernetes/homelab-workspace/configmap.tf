resource "kubernetes_config_map" "workspace_scripts" {
  count = data.coder_workspace.me.start_count

  metadata {
    name      = "init-scripts-${data.coder_workspace.me.id}"
    namespace = "coder"
    labels    = merge(local.common_labels, local.pod_labels)
  }

  data = {
    agent_startup_script  = file("${path.cwd}/script-agent-startup.sh")    
    system_update_script  = file("${path.cwd}/script-system-update.sh")
    workspace_init_script = coder_agent.main.init_script
  }
}
