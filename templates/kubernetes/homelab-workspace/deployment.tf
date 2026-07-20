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
        # The docker-enabled marker is what the platform Kyverno policy matches to
        # inject `hostUsers: false` (the kubernetes provider has no host_users field).
        # Docker is always enabled now, so the label is always present. hostUsers:false
        # is what makes the root/CAP_SYS_ADMIN container below safe (namespaced root).
        labels = merge(local.common_labels, local.pod_labels, { "com.coder.workspace.docker-enabled" = "true" })
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
        container {
          name = "workspace"
          # Entrypoint runs as root: prepares the workspace (apt/homebrew), starts
          # dockerd, then drops to the coder user to exec the agent. This replaces the
          # old init-container + system-volume dance, which only existed to shuttle
          # root-made changes into a non-root container -- unnecessary now.
          command = ["/bin/bash", "/workspace-entrypoint.sh"]
          image   = var.workspace_image
          # In test_mode the image is a mutable branch tag that gets rebuilt in place,
          # so a cached layer must not shadow a fresh push -> Always. Released versions
          # use immutable tags where IfNotPresent is correct (and avoids needless pulls).
          image_pull_policy = var.test_mode ? "Always" : "IfNotPresent"
          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }
          env {
            name  = "SYSTEM_PACKAGES"
            value = length(local.validated_system_packages) > 0 ? join(" ", local.validated_system_packages) : "NONE"
          }
          env {
            name  = "HOMEBREW_PREFIX"
            value = local.homebrew_directory
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
            # Root INSIDE the pod user namespace (hostUsers:false, injected by the
            # platform Kyverno policy via the marker label above). Namespaced root maps
            # to an unprivileged host uid, so these privileges are void on the host --
            # this is what lets a rootful dockerd run without being privileged-on-host.
            # SYS_ADMIN/NET_ADMIN are what dockerd needs; escalation must be true for the
            # caps to take effect. privileged stays false. The entrypoint drops to the
            # coder user before handing off to the agent.
            allow_privilege_escalation = true
            read_only_root_filesystem  = false
            privileged                 = false
            run_as_user                = 0
            run_as_group               = 0
            run_as_non_root            = false
            capabilities {
              add = ["SYS_ADMIN", "NET_ADMIN"]
            }
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
            mount_path = "/workspace-entrypoint.sh"
            name       = "coder-scripts"
            sub_path   = "workspace_entrypoint_script"
          }
          volume_mount {
            mount_path = "/workspace-init.sh"
            name       = "coder-scripts"
            sub_path   = "workspace_init_script"
          }
          volume_mount {
            # Rootful dockerd's data root; on the persistent docker-data PVC.
            mount_path = "/var/lib/docker"
            name       = "docker-data"
          }
        }
        enable_service_links = false
        hostname             = lower(replace(data.coder_workspace.me.name, "/[^a-zA-Z0-9]/", "-"))
        node_selector = {
          "kubernetes.io/os"   = "linux"
          "kubernetes.io/arch" = "amd64"
        }
        security_context {
          # Pod-level root, matching the container. Namespaced by hostUsers:false.
          # fs_group stays 10001 so the coder user owns its home PVC contents.
          run_as_user            = 0
          run_as_group           = 0
          run_as_non_root        = false
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
          name = "docker-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.docker_data[0].metadata[0].name
            read_only  = false
          }
        }
      }
    }
  }
}

# Persistent storage for the Docker daemon's image/layer data (/var/lib/docker).
#
# Deliberately NOT gated on start_count: like the external `coder-workspace-home`
# PVC, it must survive a workspace STOP (deployment scales to 0). Tying it to
# start_count would delete the volume -- and every pulled image and built layer --
# on every stop. It is destroyed only on workspace DELETE.
resource "kubernetes_persistent_volume_claim_v1" "docker_data" {
  # count = 1 (not start_count): the deployment is gated on start_count and scales
  # to 0 on stop, but this PVC must persist across stop so images/layers survive.
  # terraform destroy (workspace delete) still removes it.
  count = 1

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
