data "coder_parameter" "resources_memory" {
  name = "memory"

  default      = "4"
  display_name = "Memory"
  description  = "The amount of memory in GiB"
  icon         = "/icon/memory.svg"
  mutable      = true

  option {
    name  = "4 GiB"
    value = "4"
  }
  option {
    name  = "8 GB"
    value = "8"
  }
}

data "coder_parameter" "preferred_nodes" {
  name = "preferred_nodes"

  default      = jsonencode([])
  display_name = "Preferred Nodes"
  description  = "Prefer scheduling on one of these nodes"
  icon         = "/icon/k8s.svg"
  mutable      = true
  type         = "list(string)"
}

data "coder_parameter" "memory_watchdog_mode" {
  name = "memory_watchdog_mode"

  default      = "enforce"
  display_name = "Memory Watchdog"
  description  = "What the memory watchdog may do about a helper process that has been over its budget for ten minutes"
  icon         = "/icon/memory.svg"
  mutable      = true

  option {
    name        = "Observe only"
    value       = "observe"
    description = "Measure, record every sweep, and log the kill it would have made. Sends no signals"
  }
  option {
    name        = "Enforce (helpers)"
    value       = "enforce"
    description = "Also kill drifted helpers: language servers, the file watcher, native extension helpers, and MCP servers an agent session spawned. Each restarts invisibly"
  }
  option {
    name        = "Enforce (helpers and editor)"
    value       = "enforce-all"
    description = "Also kill the VS Code extension host and server. These restart visibly, so they are armed separately"
  }
}

data "coder_parameter" "enable_filebrowser" {
  name         = "enable_filebrowser"
  display_name = "Enable File Browser"
  type         = "bool"
  form_type    = "checkbox"
  default      = false
  mutable      = true
}

locals {
  # Coder already constrains this to the two option values server-side, but it
  # reaches the agent as an environment variable and from there a shell, and it
  # is the single switch that decides whether the watchdog may signal processes.
  # So it goes through the same validate-then-use step as the list parameters
  # below, and anything unrecognised falls back to the inert mode rather than to
  # whatever was supplied.
  validated_watchdog_mode = contains(
    ["observe", "enforce", "enforce-all"], data.coder_parameter.memory_watchdog_mode.value
  ) ? data.coder_parameter.memory_watchdog_mode.value : "observe"

  validated_preferred_nodes = (data.coder_parameter.preferred_nodes.value != "") ? [
    for str in jsondecode(data.coder_parameter.preferred_nodes.value) :
    str if length(regexall("[^a-zA-Z0-9-]", str)) == 0
  ] : []
}
