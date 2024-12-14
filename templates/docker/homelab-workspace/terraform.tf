terraform {
  required_version = ">= 1.8"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.0.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.2"
    }
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}
