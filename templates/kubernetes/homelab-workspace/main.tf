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

  home_directory     = "/home/coder"
  homebrew_directory = "/home/linuxbrew/.linuxbrew"

  # Kubernetes object names must be a lowercase RFC 1123 label/subdomain.
  # Coder's own name validation (NameValid in coder/coder's codersdk) already
  # restricts workspace and owner names to `^[a-zA-Z0-9]+(?:-[a-zA-Z0-9]+)*$`,
  # <= 32 chars, so lower() is the only transformation strictly required;
  # replace() mirrors the pre-existing hostname sanitization in deployment.tf
  # so there's one normalization idiom instead of two.
  sanitized_owner_name     = lower(replace(data.coder_workspace_owner.me.name, "/[^a-zA-Z0-9]/", "-"))
  sanitized_workspace_name = lower(replace(data.coder_workspace.me.name, "/[^a-zA-Z0-9]/", "-"))

  # Deployment name (see deployment.tf). Owner is included because workspace
  # names are unique per-owner, not cluster-wide - two owners could otherwise
  # pick the same workspace name and collide. The "coder-workspace-" prefix
  # distinguishes this from both the coder control-plane Deployment ("coder")
  # and other "coder-*" infra objects that live in the same namespace (e.g.
  # a CloudNativePG cluster named "coder-db-<date>") - a bare "coder-" prefix
  # is not enough to tell those apart. This name becomes the `workload`
  # Prometheus label via the cluster's existing kube_pod_owner recording
  # rule, so it's what workspace CPU/memory/PSI/OOM metrics get attributed
  # to in Grafana/PromQL - see DESIGN.md.
  workload_name = "coder-workspace-${local.sanitized_owner_name}-${local.sanitized_workspace_name}"
}
