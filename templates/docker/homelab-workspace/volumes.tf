locals {
  container_volume_mounts = {
    "home"   = "/home/${local.username}",
    "docker" = "/var/lib/docker"
  }
  bind_mount_host_paths = {
    "home"   = "/srv/workspaces/${local.username}",
    "docker" = "/srv/workspaces/${local.username}-${data.coder_workspace.me.name}-docker"
  }

  # create docker volumes in test_mode
  docker_volumes = var.test_mode ? ["home", "docker"] : []
  # create bind mounts otherwise
  bind_mounts = var.test_mode ? [] : ["home", "docker"]
}


resource "docker_volume" "volume" {
  for_each = toset(local.docker_volumes)

  name = "coder-${data.coder_workspace.me.id}-${each.key}"
  lifecycle {
    ignore_changes = all
  }
}
