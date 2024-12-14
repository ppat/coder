data "coder_workspace" "me" {
}

data "coder_workspace_owner" "me" {
}

locals {
  common_labels = {
    "app.kubernetes.io/instance"   = "coder-workspace-${data.coder_workspace.me.id}"
    "app.kubernetes.io/part-of"    = "coder-workspace"
    "app.kubernetes.io/managed-by" = "coder"
    "com.coder.resource"           = "true"
    "com.coder.workspace.id"       = data.coder_workspace.me.id
    "com.coder.workspace.name"     = data.coder_workspace.me.name
    "com.coder.user.id"            = data.coder_workspace_owner.me.id
    "com.coder.user.username"      = data.coder_workspace_owner.me.name
  }
  pod_labels = {
    "app.kubernetes.io/name" = lower(data.coder_workspace.me.name)
  }

  home_directory = "/home/coder"

  workspace_secrets = {
    "github_auth_token"  = "${local.home_directory}/.secret/github_token"
    "github_public_key"  = "${local.home_directory}/.ssh/id_ed25519.pub"
    "github_private_key" = "${local.home_directory}/.ssh/id_ed25519"
    "kubeconfig_nas"     = "${local.home_directory}/.kube/conf.d/nas"
    "kubeconfig_homelab" = "${local.home_directory}/.kube/conf.d/homelab"
  }
}
