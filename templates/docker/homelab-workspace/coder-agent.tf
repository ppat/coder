resource "coder_agent" "main" {
  arch                    = "amd64"
  os                      = "linux"
  startup_script          = var.test_mode ? "/bin/bash --noprofile --norc" : "/bin/bash --noprofile --norc /opt/coder/bin/agent-startup.sh"
  startup_script_behavior = "blocking"

  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage"
    key          = "1_mem_usage"
    script       = "coder stat mem --prefix Gi"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "Load Average"
    key          = "load"
    script       = <<EOT
        awk '{print $1,$2,$3}' /proc/loadavg
    EOT
    interval     = 60
    timeout      = 1
  }
}
