locals {
  # Marker label consumed by a Kyverno policy (separate repo) that injects
  # `hostUsers: false` onto the pod — the hashicorp/kubernetes provider has no
  # host_users attribute, so this label is the only way to request it. Absent
  # (not "false") when docker is disabled so the policy simply doesn't match.
  docker_labels = data.coder_parameter.enable_docker.value ? { "com.coder.workspace.docker-enabled" = "true" } : {}
}

resource "kubernetes_deployment_v1" "deployment" {
  count = data.coder_workspace.me.start_count

  metadata {
    name      = "coder-${data.coder_workspace.me.id}"
    namespace = "coder"
    labels    = merge(local.common_labels, local.pod_labels)
    annotations = {
      "com.coder.user.email" = data.coder_workspace_owner.me.email
    }
  }

  wait_for_rollout = false
  spec {
    replicas = 1
    selector {
      match_labels = merge(local.common_labels, local.pod_labels)
    }
    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = merge(local.common_labels, local.pod_labels, local.docker_labels)
      }
      spec {
        dynamic "affinity" {
          for_each = length(local.validated_preferred_nodes) > 0 ? toset(["kubernetes.io/hostname"]) : []
          content {
            node_affinity {
              preferred_during_scheduling_ignored_during_execution {
                preference {
                  match_expressions {
                    key      = affinity.key
                    operator = "In"
                    values   = local.validated_preferred_nodes
                  }
                }
                weight = 1
              }
            }
          }
        }
        automount_service_account_token = false
        init_container {
          name    = "prepare-workspace"
          command = ["/bin/bash", "/prepare-workspace-script.sh"]
          image   = var.workspace_image
          env {
            name  = "SYSTEM_PACKAGES"
            value = length(local.validated_system_packages) > 0 ? join(" ", local.validated_system_packages) : "NONE"
          }
          env {
            name  = "HOMEBREW_PREFIX"
            value = local.homebrew_directory
          }
          volume_mount {
            mount_path = local.home_directory
            name       = "home"
            sub_path   = data.coder_workspace.me.name
          }
          volume_mount {
            mount_path = local.homebrew_directory
            name       = "home"
            sub_path   = "${data.coder_workspace.me.name}/.linuxbrew"
          }
          volume_mount {
            mount_path = "/prepare-workspace-script.sh"
            name       = "coder-scripts"
            sub_path   = "prepare_workspace_script"
          }
          volume_mount {
            name       = "system"
            mount_path = "/updated"
          }
          security_context {
            run_as_user = 0
          }
        }
        container {
          name    = "workspace"
          command = ["/bin/bash", "/workspace-init.sh"]
          image   = var.workspace_image
          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }
          env {
            name  = "ENABLE_DOCKER"
            value = tostring(data.coder_parameter.enable_docker.value)
          }
          liveness_probe {
            exec {
              command = ["/bin/sh", "-c", "pgrep -f \"coder agent\" || exit 1"]
            }
            initial_delay_seconds = 5
            period_seconds        = 60
            timeout_seconds       = 3
          }
          resources {
            requests = {
              "cpu"    = "250m"
              "memory" = "1024Mi"
            }
            limits = {
              "cpu"    = data.coder_parameter.resources_cpu.value
              "memory" = "${data.coder_parameter.resources_memory.value}Gi"
            }
          }
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = false
            privileged                 = false
            run_as_user                = 10001
            run_as_group               = 10001
            run_as_non_root            = true
          }
          volume_mount {
            mount_path = local.home_directory
            name       = "home"
            sub_path   = data.coder_workspace.me.name
          }
          volume_mount {
            mount_path = local.homebrew_directory
            name       = "home"
            sub_path   = "${data.coder_workspace.me.name}/.linuxbrew"
          }
          volume_mount {
            mount_path = "/home/all"
            name       = "home"
          }
          volume_mount {
            mount_path = "/agent-startup.sh"
            name       = "coder-scripts"
            sub_path   = "agent_startup_script"
          }
          volume_mount {
            mount_path = "/workspace-init.sh"
            name       = "coder-scripts"
            sub_path   = "workspace_init_script"
          }
          volume_mount {
            mount_path = "/usr"
            name       = "system"
            sub_path   = "usr"
          }
          volume_mount {
            mount_path = "/etc"
            name       = "system"
            sub_path   = "etc"
          }
          volume_mount {
            mount_path = "/var"
            name       = "system"
            sub_path   = "var"
          }
          dynamic "volume_mount" {
            for_each = data.coder_parameter.enable_docker.value ? toset(["docker-data"]) : []
            content {
              name       = "docker-data"
              mount_path = "${local.home_directory}/.local/share/docker"
            }
          }
          dynamic "volume_mount" {
            for_each = data.coder_parameter.enable_docker.value ? toset(["xdg-runtime"]) : []
            content {
              name       = "xdg-runtime"
              mount_path = "/run/user/10001"
            }
          }
        }
        enable_service_links = false
        hostname             = lower(replace(data.coder_workspace.me.name, "/[^a-zA-Z0-9]/", "-"))
        node_selector = {
          "kubernetes.io/os"   = "linux"
          "kubernetes.io/arch" = "amd64"
        }
        security_context {
          run_as_user            = 10001
          run_as_group           = 10001
          run_as_non_root        = true
          fs_group               = 10001
          fs_group_change_policy = "OnRootMismatch"
        }
        dynamic "volume" {
          for_each = var.test_mode ? [] : toset(["coder-workspace-home"])
          content {
            name = "home"
            persistent_volume_claim {
              claim_name = volume.key
              read_only  = false
            }
          }
        }
        dynamic "volume" {
          for_each = var.test_mode ? toset(["home"]) : []
          content {
            name = "home"
            empty_dir {
              size_limit = "10Gi"
            }
          }
        }
        volume {
          name = "coder-scripts"
          config_map {
            name         = "init-scripts-${data.coder_workspace.me.id}"
            default_mode = "0750"
          }
        }
        volume {
          name = "system"
          empty_dir {
            size_limit = "10Gi"
          }
        }
        dynamic "volume" {
          for_each = data.coder_parameter.enable_docker.value ? toset(["docker-data"]) : []
          content {
            name = "docker-data"
            persistent_volume_claim {
              claim_name = kubernetes_persistent_volume_claim_v1.docker_data[0].metadata[0].name
              read_only  = false
            }
          }
        }
        dynamic "volume" {
          for_each = data.coder_parameter.enable_docker.value ? toset(["xdg-runtime"]) : []
          content {
            name = "xdg-runtime"
            empty_dir {}
          }
        }
      }
    }
  }
}

# Persistent storage for the rootless Docker daemon's image/layer data.
#
# Gated on enable_docker but deliberately NOT on start_count: like the external
# `coder-workspace-home` PVC, this must survive a workspace STOP (deployment
# scales to 0). Tying it to start_count would delete the volume — and every
# pulled image and built layer — on every stop. It is instead destroyed only on
# workspace DELETE or when docker is disabled.
resource "kubernetes_persistent_volume_claim_v1" "docker_data" {
  count = data.coder_parameter.enable_docker.value ? 1 : 0

  wait_until_bound = false

  metadata {
    name      = "coder-${data.coder_workspace.me.id}-docker"
    namespace = "coder"
    labels    = merge(local.common_labels, local.pod_labels)
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "sc-longhorn-local-non-replicated"
    resources {
      requests = {
        storage = "40Gi"
      }
    }
  }
}
