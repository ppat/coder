terraform {
  required_version = ">= 1.8"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 1.0.0"
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

  container_volume_mounts = {
    "home"   = "/home/${local.username}",
    "docker" = "/var/lib/docker"
  }
  bind_mount_host_paths = {
    "home"   = "/srv/workspaces/${local.username}",
    "docker" = "/srv/workspaces/${local.username}-docker"
  }

  # create docker volumes in test_mode
  docker_volumes = local.test_mode ? ["home", "docker"] : []
  # create bind mounts otherwise
  bind_mounts = local.test_mode ? [] : ["home", "docker"]
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

resource "docker_volume" "volume" {
  for_each = toset(local.docker_volumes)

  name = "coder-${data.coder_workspace.me.id}-${each.key}"
  lifecycle {
    ignore_changes = all
  }
}

resource "docker_image" "workspace_image" {
  name         = var.workspace_image
  force_remove = false
  keep_locally = true
}

locals {
  agent_init_script = <<EOF
    sudo -u ${local.username} --preserve-env=CODER_AGENT_TOKEN /bin/bash -- ${replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")}
    EOF
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
      ${local.agent_init_script}
    else
      # prepare user, filesystem and other configuration
      /opt/coder/bin/entrypoint-prepare.sh --username ${local.username}
      # write out coder agent init script to file that acts as a wrapper script
      echo "${local.agent_init_script}" > /tmp/coder-agent-wrapper.sh
      chmod 700 /tmp/coder-agent-wrapper.sh
      # start supervisord (which in turn will start docker and coder agent)
      exec /usr/bin/supervisord
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

  # docker volumes
  dynamic "volumes" {
    for_each = { for k, v in docker_volume.volume : local.container_volume_mounts[k] => v.name }
    content {
      container_path = volumes.key
      volume_name    = volumes.value
      read_only      = false
    }
  }
  # bind mounts
  dynamic "volumes" {
    for_each = { for k in local.bind_mounts : local.container_volume_mounts[k] => local.bind_mount_host_paths[k] }
    content {
      container_path = volumes.key
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
