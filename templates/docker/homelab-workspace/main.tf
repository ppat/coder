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
  entrypoint_script    = <<EOF
echo "Running entrypoint script..."
exec 2>&1
echo "Writing coder agent init script to file..."
cat > /tmp/coder-agent-init-script.sh <<'EOT'
${local.standard_init_script}
EOT
chmod 755 /tmp/coder-agent-init-script.sh
echo
echo "Checking minimum requirements for coder agent..."
if (command -v curl && command -v sudo && command -v useradd) > /dev/null; then
  echo "Minimum requirements for running coder agent is met."
else
  echo "Installing minimum required software for running coder agent..."
  apt-get update
  DEBIAN_FRONTEND="noninteractive" apt-get install -yq --no-install-recommends curl sudo adduser
fi
if grep coder /etc/passwd > /dev/null; then
  echo "Modifying user: coder -> ${local.username}..."
  usermod --home /home/${local.username} --shell /bin/bash --login $username coder
else
  echo "Creating user - ${local.username}..."
  useradd --groups sudo --home-dir /home/${local.username} --shell /bin/bash ${local.username}
fi
# allow coder user to sudo to so that they can run any system actions (such as using apt-get) within their workspace container.
echo "Enabling ${local.username} to sudo"
echo "${local.username} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/${local.username}
chmod 0440 /etc/sudoers.d/${local.username}
echo
echo "Creating directories and updating directory permissions..."
mkdir -p /home/${local.username}/.log/
chown ${local.username} /home/${local.username}
chown ${local.username} /home/${local.username}/.log/
echo
if [[ "$ENTRYPOINT_MODE" == "SUPERVISED" ]]; then
  echo "Running in supervised mode..."
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
