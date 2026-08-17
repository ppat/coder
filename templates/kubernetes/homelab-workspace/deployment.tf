resource "kubernetes_deployment_v1" "deployment" {
  count = data.coder_workspace.me.start_count

  metadata {
    name      = local.workload_name
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
            mount_path = "/memory-watchdog.sh"
            name       = "coder-scripts"
            sub_path   = "memory_watchdog_script"
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
          volume_mount {
            mount_path = "/tmp"
            name       = "tmp"
          }
        }
        enable_service_links = false
        hostname             = local.sanitized_workspace_name
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
        # /tmp is scratch space (agent/tool tempfiles, build caches, downloaded
        # archives) and needs to be fast - it cannot be the NFS-backed "home"
        # PVC, and it cannot be an empty_dir either, because empty_dir lives on
        # the node's root filesystem, which is the exact partition this volume
        # exists to stay off of (single ~125Gi ext4 partition shared by every
        # pod on the node; container writable layers and empty_dirs all land
        # there, and it is what the kubelet's disk-pressure eviction threshold
        # watches). A Kubernetes "generic ephemeral volume" on
        # sc-longhorn-local-non-replicated-ephemeral instead lands on the same
        # node's much larger Longhorn-backed partition: still node-local NVMe
        # (no NFS latency), not replicated (this is scratch data - losing it on
        # node failure costs nothing, so paying to replicate it would be pure
        # overhead), and bounded by the size below instead of growing until the
        # node notices. Its lifecycle matches the Pod's (created fresh, deleted
        # with it) - like the "system" volume above, that means a Pod restart
        # gets a clean volume but a container-only restart within a live Pod
        # does not, which is why script-agent-startup.sh also wipes /tmp's
        # contents explicitly on every agent start instead of relying on this.
        volume {
          name = "tmp"
          ephemeral {
            volume_claim_template {
              spec {
                access_modes       = ["ReadWriteOnce"]
                storage_class_name = "sc-longhorn-local-non-replicated-ephemeral"
                resources {
                  requests = {
                    storage = "20Gi"
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
