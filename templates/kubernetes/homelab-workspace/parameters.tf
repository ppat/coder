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
  description  = "What the memory watchdog may do about a process that has been over its share of the 2048 MiB VS Code envelope for ten minutes"
  icon         = "/icon/memory.svg"
  mutable      = true

  option {
    name        = "Observe only"
    value       = "observe"
    description = "Measure, record every sweep, and log the action it would have taken. Sends no signals"
  }
  option {
    name        = "Enforce"
    value       = "enforce"
    description = "Also kill drifted processes, in every role. A process that has never fitted its share is reported rather than killed, so nothing is restarted on a loop"
  }
}


locals {
  # Coder already constrains this to the two option values server-side, but it
  # reaches the agent as an environment variable and from there a shell, and it
  # is the single switch that decides whether the watchdog may signal processes.
  # So it goes through the same validate-then-use step as the list parameters
  # below, and anything unrecognised falls back to the inert mode rather than to
  # whatever was supplied.
  #
  # "enforce-all" is the retired third mode: under a fixed envelope every role is
  # armed, so there is no superset left for it to name. A workspace still
  # carrying the stored value is mapped to "enforce" rather than dropped to
  # "observe", because it had asked for more enforcement and must not silently
  # get none.
  validated_watchdog_mode = (
    data.coder_parameter.memory_watchdog_mode.value == "enforce-all" ? "enforce" : (
      contains(
        ["observe", "enforce"], data.coder_parameter.memory_watchdog_mode.value
      ) ? data.coder_parameter.memory_watchdog_mode.value : "observe"
    )
  )

  validated_preferred_nodes = (data.coder_parameter.preferred_nodes.value != "") ? [
    for str in jsondecode(data.coder_parameter.preferred_nodes.value) :
    str if length(regexall("[^a-zA-Z0-9-]", str)) == 0
  ] : []
}
