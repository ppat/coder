data "coder_parameter" "resources_cpu" {
  name = "resources_cpu"

  default      = "2"
  description  = "The number of CPU cores"
  display_name = "CPU Cores"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "2 Cores"
    value = "2"
  }
  option {
    name  = "4 Cores"
    value = "4"
  }
  option {
    name  = "8 Cores"
    value = "8"
  }
}

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

data "coder_parameter" "system_packages" {
  name = "system_packages"

  default      = jsonencode(["build-essential"])
  display_name = "System Packages"
  description  = "Additional system packages to install"
  icon         = "/icon/ubuntu.svg"
  mutable      = true
  type         = "list(string)"
}

data "coder_parameter" "memory_watchdog_mode" {
  name = "memory_watchdog_mode"

  default      = "observe"
  display_name = "Memory Watchdog"
  description  = "What the memory watchdog is allowed to do when the pod runs low on unreclaimable-memory headroom"
  icon         = "/icon/memory.svg"
  mutable      = true

  option {
    name        = "Observe only"
    value       = "observe"
    description = "Measure, publish headroom and log what it would have done. Sets no limits and sends no signals"
  }
  option {
    name        = "Enforce"
    value       = "enforce"
    description = "Also cap helper processes with RLIMIT_DATA and shed load as headroom falls. Do not enable before the thresholds have been set from calibration data"
  }
}


locals {
  # Coder already constrains this to the two option values server-side, but it
  # reaches the agent as an environment variable and from there a shell, and it
  # is the single switch that decides whether the watchdog may signal processes.
  # So it goes through the same validate-then-use step as the list parameters
  # below, and anything unrecognised falls back to the inert mode rather than to
  # whatever was supplied.
  validated_watchdog_mode = contains(
    ["observe", "enforce"], data.coder_parameter.memory_watchdog_mode.value
  ) ? data.coder_parameter.memory_watchdog_mode.value : "observe"

  validated_system_packages = (data.coder_parameter.system_packages.value != "") ? [
    for str in jsondecode(data.coder_parameter.system_packages.value) :
    str if length(regexall("[^a-zA-Z0-9-]", str)) == 0
  ] : []
  validated_preferred_nodes = (data.coder_parameter.preferred_nodes.value != "") ? [
    for str in jsondecode(data.coder_parameter.preferred_nodes.value) :
    str if length(regexall("[^a-zA-Z0-9-]", str)) == 0
  ] : []
}
