data "coder_workspace" "me" {
}

data "coder_workspace_owner" "me" {
}

locals {
  username = var.test_mode ? "coder" : data.coder_workspace_owner.me.name
}

resource "docker_image" "workspace_image" {
  name         = var.workspace_image
  force_remove = false
  keep_locally = true
}

locals {
  standard_init_script = replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")
  entrypoint_template_params = {
    agent_init_script = local.standard_init_script
    coder_user        = local.username
  }
  entrypoint_script = templatefile("${path.cwd}/entrypoint.sh.tftpl", local.entrypoint_template_params)
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count

  image    = docker_image.workspace_image.image_id
  name     = var.test_mode ? data.coder_workspace.me.name : "${lower(local.username)}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name
  runtime  = "sysbox-runc"
  user     = "0:0"

  entrypoint = ["/bin/bash", "-c", local.entrypoint_script]

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "ENTRYPOINT_MODE=${var.test_mode ? "UNSUPERVISED" : "SUPERVISED"}"
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
