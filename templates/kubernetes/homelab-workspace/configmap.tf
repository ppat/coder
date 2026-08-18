resource "kubernetes_config_map_v1" "workspace_scripts" {
  count = data.coder_workspace.me.start_count

  metadata {
    name      = "init-scripts-${data.coder_workspace.me.id}"
    namespace = "coder"
    labels    = merge(local.common_labels, local.pod_labels)
  }

  data = {
    agent_startup_script        = file("${path.cwd}/script-agent-startup.sh")
    container_entrypoint_script = file("${path.cwd}/script-container-entrypoint.sh")
    memory_watchdog_script      = file("${path.cwd}/script-memory-watchdog.sh")
    prepare_workspace_script    = file("${path.cwd}/script-prepare-workspace.sh")
    vscode_server_gc_script     = file("${path.cwd}/script-vscode-server-gc.sh")
    workspace_init_script       = coder_agent.main.init_script
  }
}
