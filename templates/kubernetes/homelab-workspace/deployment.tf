resource "kubernetes_deployment" "deployment" {
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
        labels = merge(local.common_labels, local.pod_labels)
      }
      spec {
        automount_service_account_token = false
        init_container {
          name    = "system-update"
          command = ["/bin/bash", "/system-update-script.sh"]
          image   = var.workspace_image
          env {
            name  = "SYSTEM_PACKAGES"
            value = length(local.validated_system_packages) > 0 ? join(" ", local.validated_system_packages) : "NONE"
          }
          volume_mount {
            mount_path = "/system-update-script.sh"
            name       = "coder-scripts"
            sub_path   = "system_update_script"
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
      }
    }
  }
}
