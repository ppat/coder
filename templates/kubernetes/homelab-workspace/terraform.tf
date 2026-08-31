terraform {
  required_version = ">= 1.9"

  required_providers {
    coder = {
      source  = "registry.opentofu.org/coder/coder"
      version = "2.18.0"
    }
    kubernetes = {
      source  = "registry.opentofu.org/hashicorp/kubernetes"
      version = "3.2.1"
    }
  }
}

provider "coder" {
}

provider "kubernetes" {
  config_path = var.test_mode ? "/home/coder/.kube/config" : null
}
