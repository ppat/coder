resource "kubernetes_config_map_v1" "workspace_scripts" {
  count = data.coder_workspace.me.start_count

  metadata {
    name      = "init-scripts-${data.coder_workspace.me.id}"
    namespace = "coder"
    labels    = merge(local.common_labels, local.pod_labels)
  }

  data = {
    "script-agent-startup.sh"         = file("${path.cwd}/script-agent-startup.sh")
    "script-container-entrypoint.sh"  = file("${path.cwd}/script-container-entrypoint.sh")
    "script-dotfiles.sh"              = file("${path.cwd}/script-dotfiles.sh")
    "script-memory-watchdog.sh"       = file("${path.cwd}/script-memory-watchdog.sh")
    "script-memory-watchdog-start.sh" = file("${path.cwd}/script-memory-watchdog-start.sh")
    "script-prepare-workspace.sh"     = file("${path.cwd}/script-prepare-workspace.sh")
    "script-service-command.sh"       = file("${path.cwd}/script-service-command.sh")
    "script-start-services.sh"        = file("${path.cwd}/script-start-services.sh")
    "supervisord.conf"                = file("${path.cwd}/supervisord.conf")
    "script-vscode-server-gc.sh"      = file("${path.cwd}/script-vscode-server-gc.sh")
    "workspace-init.sh"               = coder_agent.main.init_script
  }
}
