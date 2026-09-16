locals {
  home_pvc_name = data.coder_parameter.use_existing_home_pvc.value ? (
    data.coder_parameter.existing_home_pvc_name[0].value
  ) : kubernetes_persistent_volume_claim_v1.home[0].metadata[0].name
}

# This resource deliberately does not follow the workspace start count. The
# claim survives workspace stops and is removed only when Coder destroys the
# workspace. An externally supplied claim has no resource here, so it never
# enters this workspace's OpenTofu state and cannot be deleted with it.
resource "kubernetes_persistent_volume_claim_v1" "home" {
  count = data.coder_parameter.use_existing_home_pvc.value ? 0 : 1

  # A WaitForFirstConsumer class cannot bind this claim until the Deployment
  # exists. Waiting here would deadlock the apply because the Deployment needs
  # the claim name below; Kubernetes completes binding once it schedules the Pod.
  wait_until_bound = false

  metadata {
    name      = "coder-workspace-${data.coder_workspace.me.id}-home"
    namespace = "coder"
    labels    = local.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.home_pvc_storage_class
    resources {
      requests = {
        storage = "${data.coder_parameter.home_pvc_size[0].value}Gi"
      }
    }
  }
}
