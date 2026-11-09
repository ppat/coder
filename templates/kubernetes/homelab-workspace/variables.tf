variable "workspace_image" {
  description = "Workspace container image"
  type        = string
}

variable "home_pvc_storage_class" {
  description = "Storage class used for the home PVC."
  type        = string
}

variable "tmp_pvc_storage_class" {
  description = "Storage class used for ephemeral tmp PVCs."
  type        = string
}

variable "kubernetes_config_path" {
  description = "Provisioner-local kubeconfig path, or in-cluster for in-cluster authentication."
  type        = string
}

variable "skip_dotfiles_scripts" {
  description = "Whether Chezmoi should skip repository-owned bootstrap scripts."
  type        = bool
}
