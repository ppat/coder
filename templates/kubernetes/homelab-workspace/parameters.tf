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

data "coder_parameter" "system_packages" {
  name = "system_packages"

  default      = jsonencode([])
  display_name = "System Packages"
  description  = "Additional system packages to install."
  icon         = "/icon/ubuntu.svg"
  mutable      = true
  type         = "list(string)"
}


locals {
  validated_system_packages = (data.coder_parameter.system_packages.value != "") ? [
    for str in jsondecode(data.coder_parameter.system_packages.value) :
    str if length(regexall("[^a-zA-Z0-9-]", str)) == 0
  ] : []
}
