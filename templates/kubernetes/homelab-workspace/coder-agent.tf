resource "coder_agent" "main" {
  arch                    = "amd64"
  os                      = "linux"
  startup_script          = "/bin/bash --noprofile --norc /agent-startup.sh"
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
    display_name = "CPU Usage (Host)"
    key          = "2_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 60
    timeout      = 1
  }
  metadata {
    display_name = "Memory Usage (Host)"
    key          = "3_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 60
    timeout      = 1
  }
  metadata {
    display_name = "Home Disk"
    key          = "4_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }
  metadata {
    display_name = "Load Average (Host)"
    key          = "5_load_host"
    # get load avg scaled by number of cores
    script   = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval = 60
    timeout  = 1
  }
  metadata {
    display_name = "Memory Headroom"
    key          = "6_memory_headroom"
    # Published by the memory watchdog (see scripts.tf). This is the honest
    # number: bytes left before something in the pod has to die. "Memory Usage"
    # above reads ~63% on a pod whose true unreclaimable share is ~23%, because
    # it counts page cache the kernel will hand straight back.
    script   = "cat $${HOME}/.local/state/vscode-memory-watchdog/headroom 2>/dev/null || echo '-'"
    interval = 60
    timeout  = 1
  }

}
