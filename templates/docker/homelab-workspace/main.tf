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
    "docker" = "/srv/workspaces/${local.username}-${data.coder_workspace.me.name}-docker"
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
  standard_init_script = replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")
  entrypoint_script    = <<EOF
echo "Running entrypoint script..."
cat > /tmp/coder-agent-init-script.sh <<'EOT'
${local.standard_init_script}
EOT
chmod 755 /tmp/coder-agent-init-script.sh
if [[ "$ENTRYPOINT_MODE" == "SUPERVISED" ]]; then
  echo "Running in supervised mode..."
  /opt/coder/bin/entrypoint-prepare.sh --username ${local.username}
  echo -e "#!/bin/bash\nsudo -u ${local.username} --preserve-env=CODER_AGENT_TOKEN /bin/bash /tmp/coder-agent-init-script.sh" > /tmp/coder-agent-wrapper.sh
  chmod 755 /tmp/coder-agent-wrapper.sh
  exec /usr/bin/supervisord -c /etc/supervisord.conf
else
  echo "Running in unsupervised mode..."
  sudo -u ${local.username} --preserve-env=CODER_AGENT_TOKEN /bin/bash /tmp/coder-agent-init-script.sh
fi
EOF
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count

  image    = docker_image.workspace_image.image_id
  name     = local.test_mode ? data.coder_workspace.me.name : "${lower(local.username)}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name
  runtime  = "sysbox-runc"
  user     = "0:0"

  entrypoint = ["/bin/bash", "-c", local.entrypoint_script]

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "ENTRYPOINT_MODE=${local.test_mode ? "UNSUPERVISED" : "SUPERVISED"}"
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
