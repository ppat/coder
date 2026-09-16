variable "workspace_image" {
  type = string
}

variable "home_pvc_storage_class" {
  type = string
}

variable "tmp_pvc_storage_class" {
  type = string
}

variable "kubernetes_config_path" {
  type = string
}

variable "skip_dotfiles_scripts" {
  type = bool
}
