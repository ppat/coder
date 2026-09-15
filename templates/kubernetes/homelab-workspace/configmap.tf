resource "kubernetes_config_map_v1" "workspace_scripts" {
  count = data.coder_workspace.me.start_count

  metadata {
    name      = "init-scripts-${data.coder_workspace.me.id}"
    namespace = "coder"
    labels    = merge(local.common_labels, local.pod_labels)
  }

  data = {
    agent_startup_script         = file("${path.cwd}/script-agent-startup.sh")
    container_entrypoint_script  = file("${path.cwd}/script-container-entrypoint.sh")
    dotfiles_script              = file("${path.cwd}/script-dotfiles.sh")
    memory_watchdog_script       = file("${path.cwd}/script-memory-watchdog.sh")
    memory_watchdog_start_script = file("${path.cwd}/script-memory-watchdog-start.sh")
    prepare_workspace_script     = file("${path.cwd}/script-prepare-workspace.sh")
    service_command_script       = file("${path.cwd}/script-service-command.sh")
    start_services_script        = file("${path.cwd}/script-start-services.sh")
    supervisor_config            = file("${path.cwd}/supervisord.conf")
    vscode_server_gc_script      = file("${path.cwd}/script-vscode-server-gc.sh")
    workspace_init_script        = coder_agent.main.init_script
  }
}
