data "coder_parameter" "dotfiles_repo" {
  name = "dotfiles_repository"

  default      = "git@github.com:ppat/dotfiles.git"
  display_name = "Dotfiles Repository"
  icon         = "/icon/dotfiles.svg"
  mutable      = true
  type         = "string"
}

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

  default      = jsonencode(["gnupg", "nmap"])
  display_name = "System Packages"
  description  = "Additional system packages to install."
  icon         = "/icon/ubuntu.svg"
  mutable      = true
  type         = "list(string)"
}
