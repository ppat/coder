terraform {
  required_version = ">= 1.8"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 0.23.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.2"
    }
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}

data "coder_workspace" "me" {
}

data "coder_workspace_owner" "me" {
}

variable "workspace_image" {
  type = string
}

locals {
  test_mode = (var.workspace_image == "simple-workspace:latest")
  username  = local.test_mode ? "coder" : data.coder_workspace_owner.me.name
}


resource "coder_agent" "main" {
  arch                    = "amd64"
  os                      = "linux"
  startup_script          = local.test_mode ? "/bin/bash --noprofile --norc" : "/bin/bash --noprofile --norc /opt/coder/bin/agent-startup.sh"
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

resource "docker_volume" "test_home_volume" {
  count = local.test_mode ? 1 : 0

  name = "coder-${data.coder_workspace.me.id}-home"
  lifecycle {
    ignore_changes = all
  }
}

resource "docker_image" "workspace_image" {
  name         = var.workspace_image
  force_remove = false
  keep_locally = true
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count

  image    = docker_image.workspace_image.image_id
  name     = local.test_mode ? data.coder_workspace.me.name : "${lower(local.username)}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name
  runtime  = "sysbox-runc"
  user     = "0:0"

  entrypoint = ["/bin/bash", "-c", <<EOF
    echo "TEST_MODE=$TEST_MODE"
    echo
    if [[ "$TEST_MODE" == "1" ]]; then
      sudo -u ${local.username} --preserve-env=CODER_AGENT_TOKEN /bin/bash -- <<-'      EOT'
      ${replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")}
      EOT
    else
      /opt/coder/bin/entrypoint-prepare.sh --username ${local.username}

      # start coder agent as the "coder" user once systemd has started up
      sudo -u ${local.username} --preserve-env=CODER_AGENT_TOKEN /bin/bash -- <<-'      EOT' &
      while [[ ! $(systemctl is-system-running) =~ ^(running|degraded) ]]
      do
        echo "Waiting for system to start... $(systemctl is-system-running)"
        sleep 2
      done
      ${coder_agent.main.init_script}
      EOT

      # /sbin/init must be the last line within entrypoint script to have systemd start as the init process
      exec /sbin/init
    fi
    EOF
    ,
  ]

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "TEST_MODE=${(local.test_mode) ? 1 : 0}"
  ]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  # home volume for test mode
  dynamic "volumes" {
    for_each = local.test_mode ? { "coder" : docker_volume.test_home_volume[0].name } : {}
    content {
      container_path = "/home/${volumes.key}"
      volume_name    = volumes.value
      read_only      = false
    }
  }
  # home volume for standard mode
  dynamic "volumes" {
    for_each = local.test_mode ? {} : { (local.username) : "/srv/workspaces/${local.username}" }
    content {
      container_path = "/home/${volumes.key}"
      host_path      = volumes.value
      read_only      = false
    }
  }

  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}
