terraform {
  required_version = ">= 1.9"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = "2.12.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.0.0"
    }
  }
}

provider "coder" {
}

provider "kubernetes" {
}
