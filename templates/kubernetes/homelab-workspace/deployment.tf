locals {
  requested_resources = {
    requests = {
      "cpu"    = "250m"
      "memory" = "1024Mi"
    }
    limits = {
      "cpu"    = data.coder_parameter.resources_cpu.value
      "memory" = "${data.coder_parameter.resources_memory.value}Gi"
    }
  }
}

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
        container {
          name              = "workspace"
          command           = ["/bin/bash", "/usr/local/bin/agent-init.sh"]
          image             = var.workspace_image
          image_pull_policy = "IfNotPresent"
          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }
          dynamic "resources" {
            for_each = var.test_mode ? {} : { values = local.requested_resources }
            content {
              requests = resources.value["requests"]
              limits   = resources.value["limits"]
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
          dynamic "volume_mount" {
            for_each = var.test_mode ? [] : toset([local.home_directory])
            content {
              name       = "home"
              mount_path = volume_mount.key
              read_only  = false
            }
          }
          dynamic "volume_mount" {
            for_each = var.test_mode ? {} : local.workspace_secrets
            content {
              name       = "workspace-secrets"
              mount_path = volume_mount.value
              sub_path   = volume_mount.key
            }
          }
          volume_mount {
            mount_path = "/usr/local/bin/agent-startup.sh"
            name       = "coder-scripts"
            sub_path   = "agent_startup_script"
          }
          volume_mount {
            mount_path = "/usr/local/bin/agent-init.sh"
            name       = "coder-scripts"
            sub_path   = "agent_init_script"
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
          fs_group_change_policy = "Always"
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
          for_each = var.test_mode ? [] : toset(["coder-workspace-secrets"])
          content {
            name = "workspace-secrets"
            secret {
              secret_name  = volume.key
              optional     = true
              default_mode = "0400"
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
      }
    }
  }
}
